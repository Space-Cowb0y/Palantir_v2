package cmd

import (
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/proto"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/api"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/config"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/logging"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/plugin"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/ui"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
	"github.com/spf13/cobra"
	tea "github.com/charmbracelet/bubbletea"
	"google.golang.org/grpc"
)

var version = "0.2.0"

var rootCmd = &cobra.Command{
	Use:   "sentinel",
	Short: "Sentinel â€” gerenciador de plugins (eyes) de seguranÃ§a",
	Long:  "Sentinel Ã© o orquestrador que registra e monitora 'eyes' via gRPC e expÃµe status via CLI e Web.",
}

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Inicia gRPC + Web API + TUI + carrega eyes",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runServe()
	},
}

var guiCmd = &cobra.Command{
	Use:   "gui",
	Short: "Inicia GUI com Fyne",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runFyne()
	},
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Mostra a versÃ£o",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println(version)
	},
}

func Execute() {
	rootCmd.AddCommand(serveCmd, guiCmd, versionCmd)
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func runServe() error {
	cfg := config.Load()
	log := logging.New()

	// Estado compartilhado
	state := web.NewState()

	// gRPC server
	grpcLis, err := net.Listen("tcp", cfg.GRPCListen)
	if err != nil { return err }
	grpcSrv := grpc.NewServer()
	agentpb.RegisterSentinelServer(grpcSrv, api.NewSentinelServer(state))
	go func(){ _ = grpcSrv.Serve(grpcLis) }()
	log.Infof("gRPC em %s", cfg.GRPCListen)

	// Web server
	go func(){ _ = web.Start(cfg.HTTPListen, state) }()
	log.Infof("Web em http://%s", cfg.HTTPListen)

	// Plugin manager
	pm := plugin.NewManager(cfg.GRPCListen, cfg.Plugins)
	pm.StartEnabled()

	// TUI
	if cfg.TUI {
		p := tea.NewProgram(ui.NewModel(state, pm))
		go func(){ _, _ = p.Run() }()
	}

	// Espera Ctrl+C
	sig := make(chan os.Signal,1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig

	grpcSrv.GracefulStop()
	time.Sleep(200*time.Millisecond)
	return nil
}
