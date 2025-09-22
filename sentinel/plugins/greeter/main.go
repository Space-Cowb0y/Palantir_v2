package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"log"
	"os"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	addr := os.Getenv("SENTINEL_GRPC"); if addr == "" { addr = "127.0.0.1:50060" }
	useTLS := os.Getenv("SENTINEL_TLS") == "1"
	var dial grpc.DialOption
	if useTLS {
		creds, err := clientCredsFromEnv()
		if err != nil { log.Fatal(err) }
		dial = grpc.WithTransportCredentials(creds)
	} else {
		dial = grpc.WithTransportCredentials(insecure.NewCredentials())
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := grpc.DialContext(ctx, addr, dial, grpc.WithBlock())
	if err != nil { log.Fatal(err) }
	defer conn.Close()

	c := agentpb.NewSentinelClient(conn)

	agentID := os.Getenv("SENTINEL_AGENT_ID")
	if agentID == "" { agentID = "greeter-go" }
	reg, err := c.Register(context.Background(), &agentpb.RegisterRequest{
		Id:          agentID,
		Name:        "greeter-go",
		Version:     "0.2.0",
		Language:    "go",
		Hostname:    host(),
		Description: "demo with logs",
	})
	if err != nil { log.Fatal(err) }
	agentID = reg.AssignedId

	hbs, err := c.StreamHeartbeats(context.Background())
	if err != nil { log.Fatal(err) }
	logs, err := c.SendLogs(context.Background())
	if err != nil { log.Fatal(err) }

	start := time.Now()
	hbtick := time.NewTicker(2*time.Second)
	logtick := time.NewTicker(5*time.Second)
	defer hbtick.Stop(); defer logtick.Stop()
	for {
		select {
		case <-hbtick.C:
			now := time.Now()
			_ = hbs.Send(&agentpb.Heartbeat{
				AgentId: agentID,
				StartedUnix: start.Unix(),
				NowUnix: now.Unix(),
				Status: "running",
				Note:   "OK",
			})
		case <-logtick.C:
			_ = logs.Send(&agentpb.LogLine{
				AgentId: agentID,
				TsUnix:  time.Now().Unix(),
				Level:   "INFO",
				Message: "heartbeat ok",
				Fields:  map[string]string{"example":"1"},
			})
		}
	}
}

func host() string { h, _ := os.Hostname(); return h }

func clientCredsFromEnv() (credentials.TransportCredentials, error) {
	ca := os.Getenv("SENTINEL_TLS_CA")
	certf := os.Getenv("SENTINEL_TLS_CERT")
	keyf := os.Getenv("SENTINEL_TLS_KEY")
	sn := os.Getenv("SENTINEL_TLS_SERVERNAME")
	cert, err := tls.LoadX509KeyPair(certf, keyf)
	if err != nil { return nil, err }
	caBytes, err := os.ReadFile(ca)
	if err != nil { return nil, err }
	cp := x509.NewCertPool()
	cp.AppendCertsFromPEM(caBytes)
	return credentials.NewTLS(&tls.Config{
		ServerName: sn,
		RootCAs: cp,
		Certificates: []tls.Certificate{cert},
		MinVersion: tls.VersionTLS12,
	}), nil
}
