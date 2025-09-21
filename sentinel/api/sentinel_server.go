package api

import (
	"context"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/proto"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
)

type SentinelServer struct {
	agentpb.UnimplementedSentinelServer
	state *web.State
}

func NewSentinelServer(st *web.State) *SentinelServer {
	return &SentinelServer{state: st}
}

func (s *SentinelServer) Register(ctx context.Context, req *agentpb.RegisterRequest) (*agentpb.RegisterResponse, error) {
	id := req.Id
	if id == "" {
		id = req.Name + "-" + time.Now().Format("150405")
	}
	s.state.UpsertAgent(&web.AgentInfo{
		ID:         id,
		Name:       req.Name,
		Version:    req.Version,
		Language:   req.Language,
		Hostname:   req.Hostname,
		Started:    time.Now(),
		Status:     "registered",
		Note:       req.Description,
		Enabled:    true,
		LastBeat:   time.Now(),
	})
	return &agentpb.RegisterResponse{AssignedId: id}, nil
}

func (s *SentinelServer) StreamHeartbeats(stream agentpb.Sentinel_StreamHeartbeatsServer) error {
	for {
		hb, err := stream.Recv()
		if err != nil {
			// stream encerrado pelo cliente
			return nil
		}
		start := time.Unix(hb.StartedUnix, 0)
		now := time.Unix(hb.NowUnix, 0)
		s.state.EnsureAgentStart(hb.AgentId, start)
		s.state.UpdateHeartbeat(hb.AgentId, now, hb.Status, hb.Note)
	}
}
