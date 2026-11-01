package service

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"tratrack/service/commands"
	"tratrack/service/models"
)

type JobStore interface {
	Create(ctx context.Context, idFile string) (*models.Job, error)
	Get(ctx context.Context, id string) (*models.Job, error)
	LastCompleted(ctx context.Context) (*models.Job, error)
	MarkRunning(ctx context.Context, id string) (*models.Job, error)
	UpdateProgress(ctx context.Context, id string, percent int) (*models.Job, error)
	Complete(ctx context.Context, id, resultJSON string) (*models.Job, error)
	Fail(ctx context.Context, id, errMsg string) (*models.Job, error)
}

// Analyzer performs the long (5-8 min) analysis for one file.
// progress reports 0-100. Return value is stored as result_json.
type Analyzer interface {
	Analyze(ctx context.Context, idFile string, progress func(int)) (string, error)
}

// SimulatedAnalyzer stands in for the real analysis until it is plugged in
// behind this interface (deliberately independent of the commands/ programs).
type SimulatedAnalyzer struct {
	Duration time.Duration
}

func (a SimulatedAnalyzer) Analyze(ctx context.Context, idFile string, progress func(int)) (string, error) {
	const steps = 20
	tick := a.Duration / steps
	if tick <= 0 {
		tick = time.Millisecond
	}
	ticker := time.NewTicker(tick)
	defer ticker.Stop()
	for i := 1; i <= steps; i++ {
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-ticker.C:
			progress(i * 100 / steps)
		}
	}
	out, err := json.Marshal(map[string]any{
		"id_file":    idFile,
		"summary":    fmt.Sprintf("analysis completed for %s", idFile),
		"steps":      []any{},
		"created_by": "tratrack-analysis-service",
	})
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// Broker fans out job updates to SubscribeAnalysis stream subscribers.
type Broker struct {
	mu   sync.Mutex
	subs map[string]map[chan *models.Job]struct{}
}

func NewBroker() *Broker {
	return &Broker{subs: make(map[string]map[chan *models.Job]struct{})}
}

func (b *Broker) Subscribe(jobID string) (chan *models.Job, func()) {
	ch := make(chan *models.Job, 16)
	b.mu.Lock()
	if b.subs[jobID] == nil {
		b.subs[jobID] = make(map[chan *models.Job]struct{})
	}
	b.subs[jobID][ch] = struct{}{}
	b.mu.Unlock()
	return ch, func() {
		b.mu.Lock()
		delete(b.subs[jobID], ch)
		if len(b.subs[jobID]) == 0 {
			delete(b.subs, jobID)
		}
		b.mu.Unlock()
	}
}

func (b *Broker) Publish(job *models.Job) {
	b.mu.Lock()
	defer b.mu.Unlock()
	for ch := range b.subs[job.ID] {
		select {
		case ch <- job:
		default: // slow subscriber: drop, it can re-poll via StatusAnalysis
		}
	}
}

type Service struct {
	store    JobStore
	analyzer Analyzer
	broker   *Broker
	timeout  time.Duration
}

func New(store JobStore, analyzer Analyzer, timeout time.Duration) *Service {
	return &Service{store: store, analyzer: analyzer, broker: NewBroker(), timeout: timeout}
}

// StartAnalysis creates the job row and returns immediately; work runs async.
func (s *Service) StartAnalysis(ctx context.Context, idFile string) (*models.Job, error) {
	if idFile == "" {
		return nil, fmt.Errorf("id_file is required")
	}
	job, err := s.store.Create(ctx, idFile)
	if err != nil {
		return nil, err
	}
	s.broker.Publish(job)
	go s.run(job.ID, job.IDFile)
	return job, nil
}

func (s *Service) run(jobID, idFile string) {
	ctx := context.Background()
	if s.timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, s.timeout)
		defer cancel()
	}

	job, err := s.store.MarkRunning(ctx, jobID)
	if err != nil {
		return
	}
	s.broker.Publish(job)

	result, err := s.analyzer.Analyze(ctx, idFile, func(pct int) {
		if j, err := s.store.UpdateProgress(context.Background(), jobID, pct); err == nil {
			s.broker.Publish(j)
		}
	})
	if err != nil {
		if j, ferr := s.store.Fail(context.Background(), jobID, err.Error()); ferr == nil {
			s.broker.Publish(j)
		}
		return
	}
	if j, err := s.store.Complete(context.Background(), jobID, result); err == nil {
		s.broker.Publish(j) // terminal event: SubscribeAnalysis streams notify the UI here
	}
}

func (s *Service) StatusAnalysis(ctx context.Context, jobID string) (*models.Job, error) {
	if jobID == "" {
		return nil, fmt.Errorf("job_id is required")
	}
	return s.store.Get(ctx, jobID)
}

func (s *Service) LastResult(ctx context.Context) (*models.Job, error) {
	return s.store.LastCompleted(ctx)
}

// Subscribe registers for push updates; caller also gets future events on ch.
func (s *Service) Subscribe(jobID string) (chan *models.Job, func()) {
	return s.broker.Subscribe(jobID)
}

// MuseAnalyzer runs the real 4-step Muse API pipeline:
//  1. Places  – extract places from the video
//  2. Tips    – add tips and tags per place
//  3. Duration – add estimated visit time per place
//  4. Location – add geographic coordinates per place
//
// Progress is reported at 25 % increments after each step completes.
type MuseAnalyzer struct {
	APIKey   string
	Location string // city or country used to geocode places; defaults to "Paris"
}

func (a MuseAnalyzer) Analyze(ctx context.Context, idFile string, progress func(int)) (string, error) {
	result, err := commands.Places(ctx, a.APIKey, idFile)
	if err != nil {
		return "", fmt.Errorf("step 1 (places): %w", err)
	}
	progress(20)

	result, err = commands.Tips(ctx, a.APIKey, idFile, result)
	if err != nil {
		return "", fmt.Errorf("step 2 (tips): %w", err)
	}
	progress(40)

	result, err = commands.Duration(ctx, a.APIKey, idFile, result)
	if err != nil {
		return "", fmt.Errorf("step 3 (duration): %w", err)
	}
	progress(60)

	loc := a.Location
	if loc == "" {
		loc = "Paris"
	}
	result, err = commands.Location(ctx, a.APIKey, result, loc)
	if err != nil {
		return "", fmt.Errorf("step 4 (location): %w", err)
	}
	progress(80)

	result, err = commands.StorePlaces(ctx, result)
	if err != nil {
		return "", fmt.Errorf("step 5 (storeplaces): %w", err)
	}
	progress(100)

	return result, nil
}
