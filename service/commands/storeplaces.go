package commands

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/victorrbravo/stories-service/database"
	models "github.com/victorrbravo/stories-service/generated/models"
	"github.com/victorrbravo/stories-service/pkg/workflow/input"
	"github.com/victorrbravo/stories-service/types"
	"gopkg.in/yaml.v3"
)

type newStoryOrder struct {
	Action      string `yaml:"action"`
	Name        string `yaml:"name"`
	Summary     string `yaml:"summary"`
	Email       string `yaml:"email"`
	ContentType string `yaml:"content_type"`
}

type stepTipsOrder struct {
	Action string   `yaml:"action"`
	StepID int      `yaml:"step_id"`
	Tips   []string `yaml:"tips"`
}

type flowStepOrder struct {
	Action    string   `yaml:"action"`
	Ticket    int      `yaml:"ticket"`
	Status    string   `yaml:"status"`
	MediaDate string   `yaml:"media_date"`
	Type      string   `yaml:"type"`
	Position  string   `yaml:"position,omitempty"`
	Tips      []string `yaml:"tips,omitempty"`
	Tags      []string `yaml:"tags,omitempty"`
	Videos    []string `yaml:"videos,omitempty"`
}

type storePlacesResult struct {
	Status string `json:"status"`
	Ticket int    `json:"ticket"`
}

// StorePlaces stores the analysis result in the stories-service database,
// creating a new story and one flow step per place. DB credentials,
// USER_ID, EMAIL and CONTENT_TYPE are read from environment variables
// (already loaded by godotenv at server startup).
// Returns {"status":"ok","ticket":N} on success.
func StorePlaces(ctx context.Context, inputJSON string) (string, error) {
	var analysis VideoAnalysis
	if err := json.Unmarshal([]byte(inputJSON), &analysis); err != nil {
		return "", fmt.Errorf("parsing input JSON: %w", err)
	}
	if analysis.Places == nil {
		analysis.Places = []Place{}
	}

	contentType := envOr("CONTENT_TYPE", "Senda")
	email := envOr("EMAIL", "")
	userID, err := strconv.Atoi(envOr("USER_ID", "2"))
	if err != nil || userID <= 0 {
		return "", fmt.Errorf("invalid USER_ID: %q", envOr("USER_ID", "2"))
	}

	query, storyCtx, err := storiesConnect(ctx)
	if err != nil {
		return "", err
	}

	log.Printf("[storeplaces] creating story %q (user=%d, email=%s, contentType=%s)", analysis.Name, userID, email, contentType)
	ticket, err := storeCreateStory(storyCtx, &query, analysis, email, contentType, userID)
	if err != nil {
		log.Printf("[storeplaces] ✗ createStory failed: %v", err)
		return "", fmt.Errorf("creating story: %w", err)
	}
	log.Printf("[storeplaces] ✓ story created: ticket=%d", ticket)

	sorted := make([]Place, len(analysis.Places))
	copy(sorted, analysis.Places)
	sort.SliceStable(sorted, func(i, j int) bool { return sorted[i].ID < sorted[j].ID })

	now := time.Now()
	mediaDate := time.Date(now.Year(), now.Month(), now.Day(), 8, 0, 0, 0, now.Location())
	for k, place := range sorted {
		log.Printf("[storeplaces] adding step %d/%d %q (mediaDate=%s)", k+1, len(sorted), place.Name, mediaDate.Format("15:04"))
		if err := storeAddFlowStep(storyCtx, &query, ticket, place, mediaDate); err != nil {
			log.Printf("[storeplaces] ✗ addFlowStep %q failed: %v", place.Name, err)
			return "", fmt.Errorf("adding place %q: %w", place.Name, err)
		}
		log.Printf("[storeplaces] ✓ step %d/%d %q added", k+1, len(sorted), place.Name)
		if place.Spent > 0 {
			mediaDate = mediaDate.Add(time.Duration(place.Spent) * time.Minute)
		}
	}

	if err := storeAddTips(storyCtx, &query, ticket, sorted); err != nil {
		log.Printf("[storeplaces] ✗ storeAddTips failed: %v", err)
		return "", fmt.Errorf("adding tips: %w", err)
	}

	out, err := json.Marshal(storePlacesResult{Status: "ok", Ticket: ticket})
	if err != nil {
		return "", err
	}
	log.Printf("[storeplaces] ticket=%d — result JSON sent to macOS app: %s", ticket, string(out))
	return string(out), nil
}

func storeCreateStory(ctx context.Context, query *database.IQuery, analysis VideoAnalysis, email, contentType string, userID int) (int, error) {
	name := storeEscape(analysis.Name)
	order, err := yaml.Marshal(newStoryOrder{
		Action:      "new_story_flow",
		Name:        name,
		Summary:     storeEscape(analysis.Summary),
		Email:       email,
		ContentType: contentType,
	})
	if err != nil {
		return 0, err
	}
	if _, err := input.ProcessInput(ctx, order, query); err != nil {
		return 0, err
	}

	stories, err := models.GetTaStoryByNameAndUserID(*query, types.NewString(name), types.NewInt(userID))
	if err != nil {
		return 0, err
	}
	ticket := 0
	for _, story := range stories {
		if id := types.AsInt(story.PkStory); id > ticket {
			ticket = id
		}
	}
	if ticket == 0 {
		return 0, fmt.Errorf("story %q created but not found for user %d", analysis.Name, userID)
	}
	return ticket, nil
}

func storeAddFlowStep(ctx context.Context, query *database.IQuery, ticket int, place Place, mediaDate time.Time) error {
	order, err := yaml.Marshal(flowStepOrder{
		Action:    "add_flow_step",
		Ticket:    ticket,
		Status:    storeEscape(place.Name),
		MediaDate: mediaDate.Format(time.RFC3339),
		Type:      "step",
		Position:  place.Location,
		Tips:      storeEscapeAll(place.Tips),
		Tags:      storeEscapeAll(place.Tags),
		Videos:    []string{fmt.Sprintf("%g %g", place.StartSeconds, place.EndSeconds)},
	})
	if err != nil {
		return err
	}
	_, err = input.ProcessInput(ctx, order, query)
	return err
}

// storeAddTips fetches the just-stored flow steps via show_flow_data, matches
// each place by name to get its step ID, then calls new_step_tips for every
// place that carries tips. Tips are escaped before joining with ",".
func storeAddTips(ctx context.Context, query *database.IQuery, ticket int, places []Place) error {
	// Skip entirely if no place has tips.
	hasTips := false
	for _, p := range places {
		if len(p.Tips) > 0 {
			hasTips = true
			break
		}
	}
	if !hasTips {
		return nil
	}

	// 1. Fetch the stored flow to collect step IDs.
	showOrder := fmt.Sprintf(
		"action: show_flow_data\nticket: %d\nfilter:\nby_day: false\npage_number: 1\npage_size: 70\n",
		ticket,
	)
	log.Printf("[storeplaces] fetching flow data for ticket=%d to get step IDs", ticket)
	flowJSON, err := input.ProcessInput(ctx, []byte(showOrder), query)
	if err != nil {
		return fmt.Errorf("show_flow_data: %w", err)
	}

	// 2. Strip any leading garbage and parse the JSON response.
	raw := []byte(flowJSON)
	if i := bytes.IndexAny(raw, "{["); i > 0 {
		raw = raw[i:]
	}
	var flow struct {
		Tasks []struct {
			Name string `json:"name"`
			Data *struct {
				ID interface{} `json:"id"`
			} `json:"data"`
		} `json:"tasks"`
	}
	if err := json.Unmarshal(raw, &flow); err != nil {
		return fmt.Errorf("parsing show_flow_data response: %w", err)
	}

	// Build name → step_id map. JSON numbers decode as float64.
	stepIDs := make(map[string]int, len(flow.Tasks))
	for _, t := range flow.Tasks {
		if t.Data == nil || t.Data.ID == nil {
			continue
		}
		var id int
		switch v := t.Data.ID.(type) {
		case float64:
			id = int(v)
		case int:
			id = v
		}
		if id > 0 {
			stepIDs[t.Name] = id
		}
	}
	log.Printf("[storeplaces] collected %d step IDs from flow", len(stepIDs))

	// 3. Call new_step_tips for each place that has tips and a known step ID.
	for _, place := range places {
		if len(place.Tips) == 0 {
			continue
		}
		id, ok := stepIDs[place.Name]
		if !ok {
			log.Printf("[storeplaces] ⚠ no step ID for %q, skipping tips", place.Name)
			continue
		}
		tipsOrder, err := yaml.Marshal(stepTipsOrder{
			Action: "new_step_tips",
			StepID: id,
			Tips:   storeEscapeAll(place.Tips),
		})
		if err != nil {
			return fmt.Errorf("marshalling tips for %q: %w", place.Name, err)
		}
		log.Printf("[storeplaces] adding %d tips for %q (step_id=%d)", len(place.Tips), place.Name, id)
		if _, err := input.ProcessInput(ctx, tipsOrder, query); err != nil {
			log.Printf("[storeplaces] ✗ new_step_tips for %q: %v", place.Name, err)
			return fmt.Errorf("new_step_tips for %q: %w", place.Name, err)
		}
		log.Printf("[storeplaces] ✓ tips added for %q", place.Name)
	}
	return nil
}

// storeEscape encodes commas and apostrophes the way stories-service expects.
func storeEscape(s string) string {
	s = strings.ReplaceAll(s, ",", "#comma#")
	return strings.ReplaceAll(s, "'", "  ")
}

func storeEscapeAll(values []string) []string {
	if values == nil {
		return nil
	}
	out := make([]string, len(values))
	for i, v := range values {
		out[i] = storeEscape(v)
	}
	return out
}

// CallStories passes an order YAML string directly to input.ProcessInput and
// returns the result string. DB credentials are read from the same env vars
// used by StorePlaces (DB_HOST/PORT/NAME/USER/PASS, USER_ID, EMAIL).
func CallStories(ctx context.Context, order string) (string, error) {
	if order == "" {
		return "", fmt.Errorf("order is required")
	}

	query, storyCtx, err := storiesConnect(ctx)
	if err != nil {
		return "", err
	}

	log.Printf("[callstories] calling ProcessInput (order %d bytes)", len(order))
	result, err := input.ProcessInput(storyCtx, []byte(order), &query)
	if err != nil {
		log.Printf("[callstories] ✗ ProcessInput error: %v", err)
		return "", fmt.Errorf("ProcessInput: %w", err)
	}
	log.Printf("[callstories] ✓ result: %s", result)
	return result, nil
}

// storiesConnect opens a database connection using the DB_* env vars and
// returns a query handle and a context enriched with EMAIL and USER_ID.
func storiesConnect(ctx context.Context) (database.IQuery, context.Context, error) {
	port, err := strconv.Atoi(envOr("DB_PORT", "5432"))
	if err != nil {
		return nil, ctx, fmt.Errorf("invalid DB_PORT: %w", err)
	}
	userID, err := strconv.Atoi(envOr("USER_ID", "2"))
	if err != nil || userID <= 0 {
		return nil, ctx, fmt.Errorf("invalid USER_ID: %q", envOr("USER_ID", "2"))
	}
	email := envOr("EMAIL", "")

	cfg := database.DatabaseConfig{
		Host:     envOr("DB_HOST", "localhost"),
		Name:     envOr("DB_NAME", "stories"),
		Port:     port,
		User:     envOr("DB_USER", "stories"),
		Password: envOr("DB_PASS", "stories"),
	}
	var pgQuery database.PostgresQuery
	pgQuery.Initialize(&cfg)
	if err := pgQuery.Connect(); err != nil {
		return nil, ctx, fmt.Errorf("database connection: %w", err)
	}
	query := pgQuery.NewQuery()
	storyCtx := context.WithValue(ctx, "email", email)
	storyCtx = context.WithValue(storyCtx, "user_id", userID)
	return query, storyCtx, nil
}

func envOr(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
