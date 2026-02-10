-- The Depot: Source of Truth (Immutable Event Log)
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    source TEXT NOT NULL,          -- e.g., 'polymarket'
    event_type TEXT NOT NULL,      -- e.g., 'market_resolved', 'trade_executed'
    payload JSONB NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- PStates: Materialized Views (Snapshots for recovery/cold starts)
CREATE TABLE IF NOT EXISTS markets (
    id TEXT PRIMARY KEY,           -- Polymarket ID
    question TEXT NOT NULL,
    category TEXT,
    status TEXT NOT NULL,          -- open, resolved
    outcome TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS traders (
    address TEXT PRIMARY KEY,
    total_pnl NUMERIC DEFAULT 0,
    total_volume NUMERIC DEFAULT 0,
    roi NUMERIC DEFAULT 0,
    brier_score NUMERIC DEFAULT 0,
    markets_count INTEGER DEFAULT 0,
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexing for performance
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_traders_roi ON traders(roi DESC);
CREATE INDEX IF NOT EXISTS idx_markets_category ON markets(category);

-- Phase 7: Historical Accuracy & Predictive Snapshots
CREATE TABLE IF NOT EXISTS trader_snapshots (
    id SERIAL PRIMARY KEY,
    address TEXT REFERENCES traders(address),
    snapshot_date DATE DEFAULT CURRENT_DATE,
    cumulative_brier NUMERIC,
    calibration_score NUMERIC,
    sharpness_score NUMERIC,
    UNIQUE(address, snapshot_date)
);

CREATE INDEX IF NOT EXISTS idx_snapshots_address ON trader_snapshots(address);
CREATE INDEX IF NOT EXISTS idx_snapshots_date ON trader_snapshots(snapshot_date);
CREATE INDEX IF NOT EXISTS idx_snapshots_address_date ON trader_snapshots(address, snapshot_date);
