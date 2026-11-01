package service

import (
	"context"
	"sync"
	"testing"
	"time"

	"tratrack/service/models"
)

type fakeStore struct {
	mu   sync.Mutex
	jobs map[string]*models.Job
	seq  int
}

func newFakeStore() *fakeStore { return &fakeStore{jobs: map[string]*models.Job{}} }

func (f *fakeStore) Create(_ context.Context, idFile string) (*models.Job, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.seq++
	j := &models.Job{ID: string(rune('a'+f.seq)) + "-job", IDFile: idFile, Status: models.StatusPending, CreatedAt: time.Now(), UpdatedAt: time.Now()}
	f.jobs[j.ID] = j
	return clone(j), nil
}

func (f *fakeStore) Get(_ context.Context, id string) (*models.Job, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	j, ok := f.jobs[id]
	if !ok {
		return nil, models.ErrNotFound
	}
	return clone(j), nil
}

func (f *fakeStore) LastCompleted(context.Context) (*models.Job, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var best *models.Job
	for _, j := range f.jobs {
		if j.Status == models.StatusCompleted && (best == nil || j.FinishedAt.After(*best.FinishedAt)) {
			best = j
		}
	}
	if best == nil {
		return nil, models.ErrNotFound
	}
	return clone(best), nil
}

func (f *fakeStore) MarkRunning(_ context.Context, id string) (*models.Job, error) {
	return f.mutate(id, func(j *models.Job) { j.Status = models.StatusRunning })
}
func (f *fakeStore) UpdateProgress(_ context.Context, id string, pct int) (*models.Job, error) {
	return f.mutate(id, func(j *models.Job) { j.ProgressPercent = pct })
}
func (f *fakeStore) Complete(_ context.Context, id, result string) (*models.Job, error) {
	return f.mutate(id, func(j *models.Job) {
		j.Status = models.StatusCompleted
		j.ProgressPercent = 100
		j.ResultJSON = result
		now := time.Now()
		j.FinishedAt = &now
	})
}
func (f *fakeStore) Fail(_ context.Context, id, msg string) (*models.Job, error) {
	return f.mutate(id, func(j *models.Job) {
		j.Status = models.StatusFailed
		j.Error = msg
		now := time.Now()
		j.FinishedAt = &now
	})
}
func (f *fakeStore) mutate(id string, fn func(*models.Job)) (*models.Job, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	j, ok := f.jobs[id]
	if !ok {
		return nil, models.ErrNotFound
	}
	fn(j)
	j.UpdatedAt = time.Now()
	return clone(j), nil
}

func clone(j *models.Job) *models.Job { c := *j; return &c }

func TestStartSubscribeCompletesAndLastResult(t *testing.T) {
	svc := New(newFakeStore(), SimulatedAnalyzer{Duration: 120 * time.Millisecond}, time.Minute)
	ctx := context.Background()

	job, err := svc.StartAnalysis(ctx, "file-42")
	if err != nil {
		t.Fatalf("StartAnalysis: %v", err)
	}
	if job.ID == "" || job.Status != models.StatusPending {
		t.Fatalf("unexpected job: %+v", job)
	}

	// Subscribe must be notified of the terminal state without polling.
	events, unsubscribe := svc.Subscribe(job.ID)
	defer unsubscribe()
	deadline := time.After(5 * time.Second)
	var terminal *models.Job
loop:
	for {
		select {
		case ev := <-events:
			if ev.Status.IsTerminal() {
				terminal = ev
				break loop
			}
		case <-deadline:
			t.Fatal("timed out waiting for completion notification")
		}
	}
	if terminal.Status != models.StatusCompleted {
		t.Fatalf("terminal status = %s, want COMPLETED", terminal.Status)
	}

	st, err := svc.StatusAnalysis(ctx, job.ID)
	if err != nil || st.Status != models.StatusCompleted || st.ProgressPercent != 100 {
		t.Fatalf("StatusAnalysis = %+v, %v", st, err)
	}

	last, err := svc.LastResult(ctx)
	if err != nil || last.ID != job.ID || last.ResultJSON == "" {
		t.Fatalf("LastResult = %+v, %v", last, err)
	}
}

func TestStartAnalysisRequiresIDFile(t *testing.T) {
	svc := New(newFakeStore(), SimulatedAnalyzer{Duration: time.Millisecond}, time.Minute)
	if _, err := svc.StartAnalysis(context.Background(), ""); err == nil {
		t.Fatal("expected error for empty id_file")
	}
}
