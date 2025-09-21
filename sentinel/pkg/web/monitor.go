package web

import (
	"sync"
	"time"
)

type AgentInfo struct {
	ID        string
	Name      string
	Version   string
	Language  string
	Hostname  string
	Started   time.Time
	LastBeat  time.Time
	Status    string
	Note      string
	Enabled   bool
}

type State struct {
	mu     sync.RWMutex
	agents map[string]*AgentInfo
}

func NewState() *State {
	return &State{agents: make(map[string]*AgentInfo)}
}

func (s *State) UpsertAgent(a *AgentInfo) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if old, ok := s.agents[a.ID]; ok {
		if a.Name != "" { old.Name = a.Name }
		if !a.Started.IsZero() { old.Started = a.Started }
		if a.Language != "" { old.Language = a.Language }
		if a.Version != "" { old.Version = a.Version }
		if a.Hostname != "" { old.Hostname = a.Hostname }
		if a.Status != "" { old.Status = a.Status }
		if a.Note != "" { old.Note = a.Note }
		return
	}
	s.agents[a.ID] = a
}

func (s *State) EnsureAgentStart(id string, started time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	ag, ok := s.agents[id]
	if !ok {
		s.agents[id] = &AgentInfo{ID: id, Started: started, Status: "running"}
		return
	}
	if ag.Started.IsZero() || started.Before(ag.Started) {
		ag.Started = started
	}
}

func (s *State) UpdateHeartbeat(id string, now time.Time, status, note string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if ag, ok := s.agents[id]; ok {
		ag.LastBeat = now
		if status != "" { ag.Status = status }
		if note != "" { ag.Note = note }
	}
}

func (s *State) Snapshot() []AgentInfo {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]AgentInfo, 0, len(s.agents))
	for _, a := range s.agents {
		out = append(out, *a)
	}
	return out
}
