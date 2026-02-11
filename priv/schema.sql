-- Enable Write-Ahead Logging for concurrency
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- Markets Table
CREATE TABLE IF NOT EXISTS markets (
    id TEXT PRIMARY KEY,
    slug TEXT NOT NULL,
    question TEXT NOT NULL,
    url TEXT NOT NULL,
    description TEXT,
    created_at INTEGER DEFAULT (unixepoch())
);

-- Price History Table
CREATE TABLE IF NOT EXISTS prices (
    market_id TEXT NOT NULL,
    outcome TEXT NOT NULL,
    price REAL NOT NULL,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY(market_id) REFERENCES markets(id)
);

CREATE INDEX IF NOT EXISTS idx_prices_market_ts ON prices(market_id, timestamp);

-- Events Log (Raw Ingestion)
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    event_type TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at INTEGER DEFAULT (unixepoch())
);

-- Bets / Positions (Graph Edges)
-- Explicitly linking Traders to Markets for "Who else bet on this?" queries
CREATE TABLE IF NOT EXISTS bets (
    trader_id TEXT NOT NULL,
    market_slug TEXT NOT NULL,
    outcome TEXT NOT NULL,
    amount REAL NOT NULL,
    price REAL NOT NULL,
    timestamp INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_bets_trader ON bets(trader_id);
CREATE INDEX IF NOT EXISTS idx_bets_market ON bets(market_slug);
CREATE INDEX IF NOT EXISTS idx_bets_trader_market ON bets(trader_id, market_slug);

-- Trader Stats (Aggregates)
CREATE TABLE IF NOT EXISTS traders (
    address TEXT PRIMARY KEY,
    total_pnl REAL NOT NULL DEFAULT 0,
    roi REAL NOT NULL DEFAULT 0,
    brier_score REAL NOT NULL DEFAULT 0,
    markets_count INTEGER NOT NULL DEFAULT 0,
    last_updated_at INTEGER DEFAULT (unixepoch())
);

-- Trader Daily Snapshots (Time Series)
CREATE TABLE IF NOT EXISTS trader_snapshots (
    address TEXT NOT NULL,
    snapshot_date TEXT NOT NULL, -- YYYY-MM-DD
    cumulative_brier REAL NOT NULL,
    calibration_score REAL NOT NULL,
    sharpness_score REAL NOT NULL,
    PRIMARY KEY(address, snapshot_date),
    FOREIGN KEY(address) REFERENCES traders(address)
);
