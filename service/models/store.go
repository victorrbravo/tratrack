package models

import (
	"context"
	"database/sql"
	_ "embed"
	"errors"
	"fmt"

	_ "github.com/lib/pq"
)

//go:embed schema.sql
var schemaSQL string

var ErrNotFound = errors.New("job not found")

type Store struct {
	db *sql.DB
}

func Open(dsn string) (*Store, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping postgres: %w", err)
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) Migrate(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx, schemaSQL)
	return err
}

// FailInterrupted marks jobs left non-terminal by a previous process as FAILED,
// so subscribers/pollers never wait forever on a job nobody is running.
func (s *Store) FailInterrupted(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE analysis_jobs
		SET status = 'FAILED', error = 'service restarted while job was running',
		    finished_at = now(), updated_at = now()
		WHERE status IN ('PENDING', 'RUNNING')`)
	return err
}

func (s *Store) Create(ctx context.Context, idFile string) (*Job, error) {
	row := s.db.QueryRowContext(ctx, `
		INSERT INTO analysis_jobs (id_file) VALUES ($1)
		RETURNING id, id_file, status, progress_percent, COALESCE(result_json::text, ''), error,
		          created_at, updated_at, started_at, finished_at`, idFile)
	return scanJob(row)
}

func (s *Store) Get(ctx context.Context, id string) (*Job, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, id_file, status, progress_percent, COALESCE(result_json::text, ''), error,
		       created_at, updated_at, started_at, finished_at
		FROM analysis_jobs WHERE id = $1`, id)
	return scanJob(row)
}

// LastCompleted returns the most recently finished successful job (LastResult RPC).
func (s *Store) LastCompleted(ctx context.Context) (*Job, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, id_file, status, progress_percent, COALESCE(result_json::text, ''), error,
		       created_at, updated_at, started_at, finished_at
		FROM analysis_jobs
		WHERE status = 'COMPLETED'
		ORDER BY finished_at DESC LIMIT 1`)
	return scanJob(row)
}

func (s *Store) MarkRunning(ctx context.Context, id string) (*Job, error) {
	return s.update(ctx, id, `
		UPDATE analysis_jobs
		SET status = 'RUNNING', started_at = now(), updated_at = now()
		WHERE id = $1
		RETURNING id, id_file, status, progress_percent, COALESCE(result_json::text, ''), error,
		          created_at, updated_at, started_at, finished_at`)
}

func (s *Store) UpdateProgress(ctx context.Context, id string, percent int) (*Job, error) {
	return s.update(ctx, id, `
		UPDATE analysis_jobs
		SET progress_percent = $2, updated_at = now()
		WHERE id = $1
		RETURNING id, id_file, status, progress_percent, COALESCE(result_json::text, ''), error,
		          created_at, updated_at, started_at, finished_at`, percent)
}

func (s *Store) Complete(ctx context.Context, id, resultJSON string) (*Job, error) {
	return s.update(ctx, id, `
		UPDATE analysis_jobs
		SET status = 'COMPLETED', progress_percent = 100, result_json = $2::jsonb,
		    finished_at = now(), updated_at = now()
		WHERE id = $1
		RETURNING id, id_file, status, progress_percent, COALESCE(result_json::text, ''), error,
		          created_at, updated_at, started_at, finished_at`, resultJSON)
}

func (s *Store) Fail(ctx context.Context, id, errMsg string) (*Job, error) {
	return s.update(ctx, id, `
		UPDATE analysis_jobs
		SET status = 'FAILED', error = $2, finished_at = now(), updated_at = now()
		WHERE id = $1
		RETURNING id, id_file, status, progress_percent, COALESCE(result_json::text, ''), error,
		          created_at, updated_at, started_at, finished_at`, errMsg)
}

func (s *Store) update(ctx context.Context, id, query string, args ...any) (*Job, error) {
	fullArgs := append([]any{id}, args...)
	row := s.db.QueryRowContext(ctx, query, fullArgs...)
	return scanJob(row)
}

type scanner interface{ Scan(dest ...any) error }

func scanJob(row scanner) (*Job, error) {
	var j Job
	var status string
	err := row.Scan(&j.ID, &j.IDFile, &status, &j.ProgressPercent, &j.ResultJSON, &j.Error,
		&j.CreatedAt, &j.UpdatedAt, &j.StartedAt, &j.FinishedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	j.Status = Status(status)
	return &j, nil
}
