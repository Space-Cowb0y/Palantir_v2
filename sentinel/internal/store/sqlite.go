package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	_ "modernc.org/sqlite"
)

type Store struct {
	DB *sql.DB
}

type AgentRow struct {
	ID, Name, Version, Language, Hostname string
	FirstSeen, LastSeen time.Time
	Status, Note string
}

type Summary struct {
	Agents int
	Running int
	Last5m  int
	Logs24h int
}

func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil { return nil, err }
	if _, err := db.Exec(`PRAGMA journal_mode=WAL;`); err != nil { return nil, err }
	s := &Store{DB: db}
	if err := s.migrate(); err != nil { return nil, err }
	return s, nil
}

func (s *Store) migrate() error {
	_, err := s.DB.Exec(`
CREATE TABLE IF NOT EXISTS agents(
  id TEXT PRIMARY KEY,
  name TEXT, version TEXT, language TEXT, hostname TEXT,
  first_seen TIMESTAMP, last_seen TIMESTAMP,
  status TEXT, note TEXT
);
CREATE TABLE IF NOT EXISTS heartbeats(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  agent_id TEXT, ts TIMESTAMP, status TEXT, note TEXT
);
CREATE INDEX IF NOT EXISTS idx_hb_agent_ts ON heartbeats(agent_id, ts);
CREATE TABLE IF NOT EXISTS logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  agent_id TEXT, ts TIMESTAMP, level TEXT, message TEXT, fields TEXT
);
CREATE INDEX IF NOT EXISTS idx_logs_ts ON logs(ts);
`)
	return err
}

func (s *Store) UpsertAgent(ctx context.Context, a AgentRow) error {
	_, err := s.DB.ExecContext(ctx, `
INSERT INTO agents(id,name,version,language,hostname,first_seen,last_seen,status,note)
VALUES(?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
 name=excluded.name, version=excluded.version, language=excluded.language,
 hostname=excluded.hostname, last_seen=excluded.last_seen, status=excluded.status, note=excluded.note
`, a.ID,a.Name,a.Version,a.Language,a.Hostname,a.FirstSeen,a.LastSeen,a.Status,a.Note)
	return err
}

func (s *Store) InsertHeartbeat(ctx context.Context, agentID, status, note string, ts time.Time) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO heartbeats(agent_id,ts,status,note) VALUES(?,?,?,?)`, agentID, ts, status, note)
	return err
}

func (s *Store) InsertLog(ctx context.Context, agentID, level, message string, fields map[string]string, ts time.Time) error {
	var jf []byte
	if fields != nil {
		jf, _ = json.Marshal(fields)
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO logs(agent_id,ts,level,message,fields) VALUES(?,?,?,?,?)`, agentID, ts, level, message, string(jf))
	return err
}

func (s *Store) GetSummary(ctx context.Context) (Summary, error) {
	var sm Summary
	row := s.DB.QueryRowContext(ctx, `SELECT count(*) FROM agents`)
	_ = row.Scan(&sm.Agents)
	row = s.DB.QueryRowContext(ctx, `SELECT count(*) FROM agents WHERE status='running'`)
	_ = row.Scan(&sm.Running)
	row = s.DB.QueryRowContext(ctx, `SELECT count(*) FROM heartbeats WHERE ts >= datetime('now','-5 minutes')`)
	_ = row.Scan(&sm.Last5m)
	row = s.DB.QueryRowContext(ctx, `SELECT count(*) FROM logs WHERE ts >= datetime('now','-1 day')`)
	_ = row.Scan(&sm.Logs24h)
	return sm, nil
}

type LogView struct {
	AgentID string    `json:"agent_id"`
	TS      time.Time `json:"ts"`
	Level   string    `json:"level"`
	Message string    `json:"message"`
	Fields  string    `json:"fields"`
}

func (s *Store) RecentLogs(ctx context.Context, limit int) ([]LogView, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT agent_id, ts, level, message, fields FROM logs ORDER BY ts DESC LIMIT ?`, limit)
	if err != nil { return nil, err }
	defer rows.Close()
	var out []LogView
	for rows.Next() {
		var v LogView
		if err := rows.Scan(&v.AgentID, &v.TS, &v.Level, &v.Message, &v.Fields); err != nil { return nil, err }
		out = append(out, v)
	}
	return out, nil
}
