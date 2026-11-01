-- tratrack analysis jobs: one row per StartAnalysis call.
-- Applied automatically by the service on startup (models.Store.Migrate)
-- and safe to apply manually: psql "$DSN" -f models/schema.sql

CREATE TABLE IF NOT EXISTS analysis_jobs (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_file          TEXT        NOT NULL,
    status           TEXT        NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING', 'RUNNING', 'COMPLETED', 'FAILED')),
    progress_percent INT         NOT NULL DEFAULT 0
                     CHECK (progress_percent BETWEEN 0 AND 100),
    result_json      JSONB,
    error            TEXT        NOT NULL DEFAULT '',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at       TIMESTAMPTZ,
    finished_at      TIMESTAMPTZ
);

-- LastResult: most recent completed job.
CREATE INDEX IF NOT EXISTS idx_analysis_jobs_last_result
    ON analysis_jobs (finished_at DESC) WHERE status = 'COMPLETED';

CREATE INDEX IF NOT EXISTS idx_analysis_jobs_status
    ON analysis_jobs (status, created_at DESC);
