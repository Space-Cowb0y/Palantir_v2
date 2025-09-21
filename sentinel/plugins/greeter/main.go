package main

import (
	"context"
	"log"
	"os"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	addr := os.Getenv("SENTINEL_GRPC")
	if addr == "" { addr = "127.0.0.1:50060" }

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	conn, err := grpc.DialContext(ctx, addr, grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithBlock())
	if err != nil { log.Fatal(err) }
	defer conn.Close()

	c := agentpb.NewSentinelClient(conn)

	reg, err := c.Register(context.Background(), &agentpb.RegisterRequest{
		Name:        "greeter-go",
		Version:     "0.1.0",
		Language:    "go",
		Hostname:    host(),
		Description: "hello from greeter-go",
	})
	if err != nil { log.Fatal(err) }
	agentID := reg.AssignedId

	stream, err := c.StreamHeartbeats(context.Background())
	if err != nil { log.Fatal(err) }

	start := time.Now()
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for range t.C {
		now := time.Now()
		err := stream.Send(&agentpb.Heartbeat{
			AgentId:    agentID,
			StartedUnix: start.Unix(),
			NowUnix:     now.Unix(),
			Status:     "running",
			Note:       "OK",
		})
		if err != nil {
			log.Printf("send hb: %v", err)
			return
		}
	}
}

func host() string { h, _ := os.Hostname(); return h }
