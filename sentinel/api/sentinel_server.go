package api

import (
	"context"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/proto"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/store"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
)

type SentinelServer struct {
	agentpb.UnimplementedSentinelServer
	state *web.State
	db    *store.Store
}

func NewSentinelServer(st *web.State, db *store.Store) *SentinelServer {
	return &SentinelServer{state: st, db: db}
}

func (s *SentinelServer) Register(ctx context.Context, req *agentpb.RegisterRequest) (*agentpb.RegisterResponse, error) {
	id := req.Id
	if id == "" {
		id = req.Name + "-" + time.Now().Format("150405")
	}
	now := time.Now()
	s.state.UpsertAgent(&web.AgentInfo{
		ID:         id,
		Name:       req.Name,
		Version:    req.Version,
		Language:   req.Language,
		Hostname:   req.Hostname,
		Started:    now,
		Status:     "registered",
		Note:       req.Description,
		Enabled:    true,
		LastBeat:   now,
	})
	if s.db != nil {
		_ = s.db.UpsertAgent(ctx, store.AgentRow{
			ID: id, Name: req.Name, Version: req.Version, Language: req.Language, Hostname: req.Hostname,
			FirstSeen: now, LastSeen: now, Status: "registered", Note: req.Description,
		})
	}
	return &agentpb.RegisterResponse{AssignedId: id}, nil
}

func (s *SentinelServer) StreamHeartbeats(stream agentpb.Sentinel_StreamHeartbeatsServer) error {
	for {
		hb, err := stream.Recv()
		if err != nil { return nil }
		start := time.Unix(hb.StartedUnix, 0)
		now := time.Unix(hb.NowUnix, 0)
		s.state.EnsureAgentStart(hb.AgentId, start)
		s.state.UpdateHeartbeat(hb.AgentId, now, hb.Status, hb.Note)
		if s.db != nil {
			ctx := context.Background()
			_ = s.db.UpsertAgent(ctx, store.AgentRow{ID: hb.AgentId, FirstSeen: start, LastSeen: now, Status: hb.Status, Note: hb.Note})
			_ = s.db.InsertHeartbeat(ctx, hb.AgentId, hb.Status, hb.Note, now)
		}
	}
}

func (s *SentinelServer) SendLogs(stream agentpb.Sentinel_SendLogsServer) error {
	for {
		l, err := stream.Recv()
		if err != nil { return nil }
		if s.db != nil {
			_ = s.db.InsertLog(context.Background(), l.AgentId, l.Level, l.Message, l.Fields, time.Unix(l.TsUnix,0))
		}
	}
}
