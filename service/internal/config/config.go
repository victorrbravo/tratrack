package config

import (
	"fmt"
	"os"
	"time"

	"github.com/joho/godotenv"
)

type Config struct {
	GRPCAddr string
	DSN      string
	// Duration of the (simulated) long analysis. Real work takes 5-8 min;
	// override with ANALYSIS_DURATION (Go duration, e.g. "30s") for demos/tests.
	AnalysisDuration time.Duration
	JobTimeout       time.Duration
}

func Load() (*Config, error) {
	_ = godotenv.Load() // .env in working dir (service/), optional

	duration, err := time.ParseDuration(getEnv("ANALYSIS_DURATION", "5m"))
	if err != nil {
		return nil, fmt.Errorf("invalid ANALYSIS_DURATION: %w", err)
	}
	timeout, err := time.ParseDuration(getEnv("TRATRACK_JOB_TIMEOUT", "15m"))
	if err != nil {
		return nil, fmt.Errorf("invalid TRATRACK_JOB_TIMEOUT: %w", err)
	}

	return &Config{
		GRPCAddr: getEnv("GRPC_ADDR", ":50051"),
		DSN: fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=disable",
			getEnv("DB_HOST", "localhost"), getEnv("DB_PORT", "5432"),
			getEnv("DB_NAME", "stories"), getEnv("DB_USER", "stories"),
			getEnv("DB_PASS", "stories")),
		AnalysisDuration: duration,
		JobTimeout:       timeout,
	}, nil
}

func getEnv(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
