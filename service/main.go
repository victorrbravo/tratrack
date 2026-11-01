// Command show-flow-data is a standalone program that uses the stories-service
// library to run the "show_flow_data" workflow action against PostgreSQL and
// print the JSON response. It mirrors TestProcessShowFlowDataCtgFunction in
// pkg/workflow/input/input_test.go.
//
//	go run . -ticket 243 -by-day
//	go run . -ticket 239 -filter ">apr30 and ctg- bill,coffee,cash" -page-size 20
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strconv"

	"github.com/joho/godotenv"

	"github.com/victorrbravo/stories-service/database"
	"github.com/victorrbravo/stories-service/pkg/workflow/input"
)

func main() {
	ticket := flag.Int("ticket", 243, "ticket (story) id to show")
	filter := flag.String("filter", "", `filter expression, e.g. ">apr30 and ctg- bill,coffee"`)
	byDay := flag.Bool("by-day", true, "group the data by day")
	pageNumber := flag.Int("page", 1, "page number")
	pageSize := flag.Int("page-size", 12, "page size")
	email := flag.String("email", "", "email of the user running the action (optional)")
	flag.Parse()

	// Database settings come from the environment or a local .env file
	_ = godotenv.Load()
	port, err := strconv.Atoi(getEnv("DB_PORT", "5432"))
	if err != nil {
		log.Fatalf("invalid DB_PORT: %v", err)
	}
	config := database.DatabaseConfig{
		Host:     getEnv("DB_HOST", "localhost"),
		Name:     getEnv("DB_NAME", "stories"),
		Port:     port,
		User:     getEnv("DB_USER", "stories"),
		Password: getEnv("DB_PASS", "stories"),
	}
	var pgQuery database.PostgresQuery
	pgQuery.Initialize(&config)
	if err = pgQuery.Connect(); err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	query := pgQuery.NewQuery()

	// Actions are YAML documents; "action" selects the workflow processor
	order := fmt.Sprintf(`
action: show_flow_data
ticket: %d
filter: %s
by_day: %t
page_number: %d
page_size: %d
`, *ticket, *filter, *byDay, *pageNumber, *pageSize)

	ctx := context.Background()
	if *email != "" {
		ctx = context.WithValue(ctx, "email", *email)
	}
	response, err := input.ProcessInput(ctx, []byte(order), &query)
	if err != nil {
		log.Fatalf("show_flow_data failed: %v", err)
	}

	// Pretty-print the JSON response when possible
	var pretty any
	if json.Unmarshal([]byte(response), &pretty) == nil {
		out, _ := json.MarshalIndent(pretty, "", "  ")
		fmt.Println(string(out))
		return
	}
	fmt.Println(response)
}

func getEnv(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
