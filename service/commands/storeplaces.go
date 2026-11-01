package commands

import (
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

type flowStepOrder struct {
	Action    string   `yaml:"action"`
	Ticket    int      `yaml:"ticket"`
	Status    string   `yaml:"status"`
	MediaDate string   `yaml:"media_date"`
	Type      string   `yaml:"type"`
	Position  string   `yaml:"position,omitempty"`
	Tips      []string `yaml:"tips,omitempty"`
	Tags      []string `yaml:"tags,omitempty"`
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

	port, err := strconv.Atoi(envOr("DB_PORT", "5432"))
	if err != nil {
		return "", fmt.Errorf("invalid DB_PORT: %w", err)
	}
	userID, err := strconv.Atoi(envOr("USER_ID", "2"))
	if err != nil || userID <= 0 {
		return "", fmt.Errorf("invalid USER_ID: %q", envOr("USER_ID", "2"))
	}
	email := envOr("EMAIL", "")
	contentType := envOr("CONTENT_TYPE", "Senda")

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
		return "", fmt.Errorf("database connection: %w", err)
	}
	query := pgQuery.NewQuery()

	storyCtx := context.WithValue(ctx, "email", email)
	storyCtx = context.WithValue(storyCtx, "user_id", userID)

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

	out, err := json.Marshal(storePlacesResult{Status: "ok", Ticket: ticket})
	if err != nil {
		return "", err
	}
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
	})
	if err != nil {
		return err
	}
	_, err = input.ProcessInput(ctx, order, query)
	return err
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

func envOr(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
