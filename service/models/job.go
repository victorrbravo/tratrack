package models

import "time"

type Status string

const (
	StatusPending   Status = "PENDING"
	StatusRunning   Status = "RUNNING"
	StatusCompleted Status = "COMPLETED"
	StatusFailed    Status = "FAILED"
)

func (s Status) IsTerminal() bool {
	return s == StatusCompleted || s == StatusFailed
}

// Job is one row of analysis_jobs (see schema.sql).
type Job struct {
	ID              string
	IDFile          string
	Status          Status
	ProgressPercent int
	ResultJSON      string // raw JSON, empty until COMPLETED
	Error           string
	CreatedAt       time.Time
	UpdatedAt       time.Time
	StartedAt       *time.Time
	FinishedAt      *time.Time
}
