package cmd

import (
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/proto"
	apiSrv "github.com/Space-Cowb0y/Palantir_v2/sentinel/proto"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/config"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/logging"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/plugin"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/security"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/store"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/ui"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
	"github.com/spf13/cobra"
	tea "github.com/charmbracelet/bubbletea"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

var version = "0.3.0"

var rootCmd = &cobra.Command{
	Use:   "sentinel",
	Short: "Sentinel â€” gerenciador de plugins (eyes) de seguranÃ§a",
	Long:  "Sentinel registra/monitora 'eyes' via gRPC (com mTLS opcional), persiste em SQLite e oferece CLI, GUI e Web.",
}

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Inicia gRPC + Web + TUI + DB + Launcher",
	RunE: func(cmd *cobra.Command, args []string) error { return runServe() },
}

var guiCmd = &cobra.Command{
	Use:   "gui",
	Short: "Inicia GUI com Fyne",
	RunE: func(cmd *cobra.Command, args []string) error { return runFyne() },
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Mostra a versÃ£o",
	Run: func(cmd *cobra.Command, args []string) { fmt.Println(version) },
}

func Execute() {
	rootCmd.AddCommand(serveCmd, guiCmd, versionCmd)
	if err := rootCmd.Execute(); err != nil { fmt.Println(err); os.Exit(1) }
}

func runServe() error {
	cfg := config.Load()
	log := logging.New()
	st := web.NewState()

	// DB
	db, err := store.Open(cfg.DBPath)
	if err != nil { return err }

	// gRPC server (TLS opcional)
	var opts []grpc.ServerOption
	if cfg.TLS.Enabled {
		creds, err := security.ServerCreds(cfg.TLS); if err != nil { return err }
		opts = append(opts, grpc.Creds(creds))
	}
	grpcSrv := grpc.NewServer(opts...)
	agentpb.RegisterSentinelServer(grpcSrv, apiSrv.NewSentinelServer(st, db))

	lis, err := net.Listen("tcp", cfg.GRPCListen); if err != nil { return err }
	go func(){ _ = grpcSrv.Serve(lis) }()
	log.Infof("gRPC em %s (mTLS=%v)", cfg.GRPCListen, cfg.TLS.Enabled)

	// Web
	go func(){ _ = web.Start(cfg.HTTPListen, st, db) }()
	log.Infof("Web em http://%s", cfg.HTTPListen)

	// Plugin manager + TLS env p/ eyes
	pm := plugin.NewManager(cfg.GRPCListen, cfg.Plugins)
	if cfg.TLS.Enabled {
		pm.WithTLSEnv(true, cfg.TLS.CAFile, cfg.TLS.CertFile, cfg.TLS.KeyFile, cfg.TLS.ServerName)
	}
	pm.StartEnabled()

	// TUI
	if cfg.TUI {
		p := tea.NewProgram(ui.NewModel(st, pm))
		go func(){ _, _ = p.Run() }()
	}

	// Ctrl+C
	sig := make(chan os.Signal,1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig
	grpcSrv.GracefulStop()
	time.Sleep(200*time.Millisecond)
	return nil
}
