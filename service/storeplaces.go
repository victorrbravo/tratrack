//go:build ignore

package main

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

	"github.com/joho/godotenv"

	"github.com/victorrbravo/stories-service/database"
	models "github.com/victorrbravo/stories-service/generated/models"
	"github.com/victorrbravo/stories-service/pkg/workflow/input"
	"github.com/victorrbravo/stories-service/types"

	"gopkg.in/yaml.v3"
)

type Place struct {
	ID           int      `json:"id"`
	Name         string   `json:"name"`
	StartSeconds float64  `json:"start_seconds"`
	EndSeconds   float64  `json:"end_seconds"`
	Location     string   `json:"location"`
	Tips         []string `json:"tips"`
	Tags         []string `json:"tags"`
	Spent        int      `json:"spent"`
}

type PlacesFile struct {
	Name    string  `json:"name"`
	Summary string  `json:"summary"`
	Places  []Place `json:"places"`
}

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

func main() {
	if len(os.Args) != 2 {
		log.Fatalf("Usage: go run storeplaces.go <file.json>")
	}

	data, err := readPlacesFile(os.Args[1])
	if err != nil {
		log.Fatalf("reading input: %v", err)
	}

	// Database and user settings come from the environment or a local
	// .env file, with the same defaults as the stories-service tests.
	_ = godotenv.Load()
	port, err := strconv.Atoi(getEnv("DB_PORT", "5432"))
	if err != nil {
		log.Fatalf("invalid DB_PORT: %v", err)
	}
	userID, err := strconv.Atoi(getEnv("USER_ID", "2"))
	if err != nil || userID <= 0 {
		log.Fatalf("invalid USER_ID: %q", getEnv("USER_ID", "2"))
	}
	email := getEnv("EMAIL", "victorrbravo@gmail.com")
	contentType := getEnv("CONTENT_TYPE", "Senda")

	config := database.DatabaseConfig{
		Host:     getEnv("DB_HOST", "localhost"),
		Name:     getEnv("DB_NAME", "stories"),
		Port:     port,
		User:     getEnv("DB_USER", "stories"),
		Password: getEnv("DB_PASS", "stories"),
	}
	var pgQuery database.PostgresQuery
	pgQuery.Initialize(&config)
	if err := pgQuery.Connect(); err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	query := pgQuery.NewQuery()

	ctx := context.WithValue(context.Background(), "email", email)
	ctx = context.WithValue(ctx, "user_id", userID)

	ticket, err := createStory(ctx, &query, data, email, contentType, userID)
	if err != nil {
		log.Fatalf("creating story: %v", err)
	}
	fmt.Printf("Created story %q with ticket %d\n", data.Name, ticket)

	// The first place starts today at 08:00; every next place starts
	// after adding the previous place's spent time (in minutes).
	now := time.Now()
	mediaDate := time.Date(now.Year(), now.Month(), now.Day(), 8, 0, 0, 0, now.Location())

	places := make([]Place, len(data.Places))
	copy(places, data.Places)
	sort.SliceStable(places, func(i, j int) bool { return places[i].ID < places[j].ID })

	for _, place := range places {
		if err := addFlowStep(ctx, &query, ticket, place, mediaDate); err != nil {
			log.Fatalf("adding place %d %q: %v", place.ID, place.Name, err)
		}
		fmt.Printf("[%d] %s at %s (spent %d min)\n",
			place.ID, place.Name, mediaDate.Format(time.RFC3339), place.Spent)

		if place.Spent > 0 {
			mediaDate = mediaDate.Add(time.Duration(place.Spent) * time.Minute)
		}
	}

	fmt.Printf("Done: story %d with %d places\n", ticket, len(places))
}

func readPlacesFile(path string) (PlacesFile, error) {
	var result PlacesFile
	data, err := os.ReadFile(path)
	if err != nil {
		return result, err
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return result, fmt.Errorf("invalid JSON: %w", err)
	}
	if result.Name == "" {
		return result, fmt.Errorf("input JSON has no \"name\"")
	}
	if len(result.Places) == 0 {
		return result, fmt.Errorf("input JSON has no places")
	}
	return result, nil
}

// createStory runs the "new_story_flow" action (see input_test.go
// TestProcessInputNewPayment / TestProcessNewStoryFlow) and returns the
// ticket: the id of the story generated. ProcessInput discards that id,
// so it is read back by name and user, taking the newest match.
func createStory(ctx context.Context, query *database.IQuery, data PlacesFile, email, contentType string, userID int) (int, error) {
	// String values coming from the JSON file are stored with their
	// commas escaped as #comma#, as the stories-service expects.
	name := escapeText(data.Name)
	order, err := yaml.Marshal(newStoryOrder{
		Action:      "new_story_flow",
		Name:        name,
		Summary:     escapeText(data.Summary),
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
	log.Printf("Created story %q with ticket %d\n", data.Name, ticket)
	if ticket == 0 {
		return 0, fmt.Errorf("story %q was created but could not be found for user %d", data.Name, userID)
	}
	return ticket, nil
}

// addFlowStep runs the "add_flow_step" action for one place (see
// input_test.go TestProcessAddFlowStepOrderByDate), mapping location to
// position, name to status, and carrying tips and tags as lists.
func addFlowStep(ctx context.Context, query *database.IQuery, ticket int, place Place, mediaDate time.Time) error {
	order, err := yaml.Marshal(flowStepOrder{
		Action:    "add_flow_step",
		Ticket:    ticket,
		Status:    escapeText(place.Name),
		MediaDate: mediaDate.Format(time.RFC3339),
		Type:      "step",
		Position:  place.Location,
		Tips:      escapeTexts(place.Tips),
		Tags:      escapeTexts(place.Tags),
	})
	if err != nil {
		return err
	}
	_, err = input.ProcessInput(ctx, order, query)
	return err
}

// escapeText replaces "," with "#comma#" and "'" with "  " (two spaces)
// in a string value coming from the JSON file, before it is put into an
// action string. Position is intentionally not escaped: its comma
// separates latitude and longitude and the coordinates parser requires it.
func escapeText(s string) string {
	s = strings.ReplaceAll(s, ",", "#comma#")
	return strings.ReplaceAll(s, "'", "  ")
}

func escapeTexts(values []string) []string {
	if values == nil {
		return nil
	}
	escaped := make([]string, len(values))
	for i, value := range values {
		escaped[i] = escapeText(value)
	}
	return escaped
}

func getEnv(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
