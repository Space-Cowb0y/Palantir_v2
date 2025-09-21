param(
  [string]$Root = "$PSScriptRoot\..\Palantir_v2\sentinel"
)

function Ensure-Dir {
  param([string]$Path)
  if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Ensure-File {
  param([string]$Path, [string]$Content)
  $dir = Split-Path $Path -Parent
  Ensure-Dir $dir
  if (!(Test-Path $Path)) {
    $Content | Out-File -FilePath $Path -Encoding UTF8
    Write-Host "Created $Path"
  } else {
    Write-Host "Exists  $Path (skipped)"
  }
}

Write-Host "Scaffolding in $Root"
Ensure-Dir $Root

# ---------------- go.mod ----------------
$gomod = @'
module github.com/Space-Cowb0y/Palantir_v2/sentinel

go 1.25.1

require (
  fyne.io/fyne/v2 v2.4.5
  github.com/charmbracelet/bubbletea v0.26.6
  github.com/charmbracelet/lipgloss v0.11.0
  github.com/spf13/cobra v1.8.0
  google.golang.org/grpc v1.66.1
  google.golang.org/protobuf v1.34.2
  gopkg.in/yaml.v3 v3.0.1
)

replace fyne.io/fyne/v2 => fyne.io/fyne/v2 v2.4.5
'@

Ensure-File (Join-Path $Root "go.mod") $gomod

# ---------------- api/agent.proto ----------------
$proto = @'
syntax = "proto3";
package agent;

option go_package = "github.com/Space-Cowb0y/Palantir_v2/sentinel/api;agentpb";

message RegisterRequest {
  string id = 1;
  string name = 2;
  string version = 3;
  string language = 4;
  string hostname = 5;
  string description = 6;
}

message RegisterResponse {
  string assigned_id = 1;
}

message Heartbeat {
  string agent_id = 1;
  int64 started_unix = 2;
  int64 now_unix = 3;
  string status = 4; // running/degraded/stopped
  string note = 5;
}

message Empty {}

service Sentinel {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc StreamHeartbeats(stream Heartbeat) returns (Empty);
}
'@
Ensure-File (Join-Path $Root "api\agent.proto") $proto

# ---------------- api/sentinel_server.go ----------------
$sentinelServer = @'
package api

import (
	"context"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/api"
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
'@
Ensure-File (Join-Path $Root "api\sentinel_server.go") $sentinelServer

# ---------------- internal/config/config.go ----------------
$configGo = @'
package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

type PluginSpec struct {
	Name        string            `yaml:"name"`
	Description string            `yaml:"description"`
	Path        string            `yaml:"path"`
	Args        []string          `yaml:"args"`
	Env         map[string]string `yaml:"env"`
	Language    string            `yaml:"language"`
	Enabled     bool              `yaml:"enabled"`
}

type Config struct {
	HTTPListen string       `yaml:"http_listen"`
	GRPCListen string       `yaml:"grpc_listen"`
	TUI        bool         `yaml:"tui"`
	Plugins    []PluginSpec `yaml:"plugins"`
}

func defaultConfig() Config {
	return Config{
		HTTPListen: "127.0.0.1:8080",
		GRPCListen: "127.0.0.1:50060",
		TUI:        true,
		Plugins: []PluginSpec{
			{
				Name:        "greeter-go",
				Description: "Exemplo em Go que envia heartbeats",
				Path:        "plugins/greeter/greeter.exe",
				Args:        []string{},
				Env:         map[string]string{},
				Language:    "go",
				Enabled:     true,
			},
			{
				Name:        "greeter-rs",
				Description: "Exemplo em Rust (tonic) — skeleton",
				Path:        "eyes/rust/greeter/target/release/greeter.exe",
				Args:        []string{},
				Env:         map[string]string{},
				Language:    "rust",
				Enabled:     false,
			},
			{
				Name:        "greeter-cpp",
				Description: "Exemplo em C++ (gRPC C++) — skeleton",
				Path:        "eyes/cpp/greeter/build/greeter.exe",
				Args:        []string{},
				Env:         map[string]string{},
				Language:    "cpp",
				Enabled:     false,
			},
		},
	}
}

func Load() Config {
	cfgPath := os.Getenv("SENTINEL_CONFIG")
	if cfgPath == "" {
		cfgPath = "config.yaml"
	}
	b, err := os.ReadFile(cfgPath)
	if err != nil {
		return defaultConfig()
	}
	var cfg Config
	if err := yaml.Unmarshal(b, &cfg); err != nil {
		return defaultConfig()
	}
	if cfg.HTTPListen == "" { cfg.HTTPListen = "127.0.0.1:8080" }
	if cfg.GRPCListen == "" { cfg.GRPCListen = "127.0.0.1:50060" }
	return cfg
}
'@
Ensure-File (Join-Path $Root "internal\config\config.go") $configGo

# ---------------- internal/logging/logger.go ----------------
$loggerGo = @'
package logging

import "log"

type Logger struct{}

func New() *Logger { return &Logger{} }
func (l *Logger) Infof(f string, a ...any)  { log.Printf("[INFO] "+f, a...) }
func (l *Logger) Errorf(f string, a ...any) { log.Printf("[ERR ] "+f, a...) }
'@
Ensure-File (Join-Path $Root "internal\logging\logger.go") $loggerGo

# ---------------- internal/plugin/loader.go (manager) ----------------
$loaderGo = @'
package plugin

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"syscall"
	"time"

	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/config"
)

type Handle struct {
	Cmd     *exec.Cmd
	Started time.Time
}

type Manager struct {
	mu      sync.Mutex
	specs   map[string]config.PluginSpec
	handles map[string]*Handle
	grpcAddr string
}

func NewManager(grpcAddr string, specs []config.PluginSpec) *Manager {
	m := &Manager{
		specs:   make(map[string]config.PluginSpec),
		handles: make(map[string]*Handle),
		grpcAddr: grpcAddr,
	}
	for _, s := range specs {
		m.specs[s.Name] = s
	}
	return m
}

func (m *Manager) List() []config.PluginSpec {
	m.mu.Lock(); defer m.mu.Unlock()
	out := make([]config.PluginSpec, 0, len(m.specs))
	for _, s := range m.specs { out = append(out, s) }
	return out
}

func (m *Manager) IsRunning(name string) bool {
	m.mu.Lock(); defer m.mu.Unlock()
	_, ok := m.handles[name]
	return ok
}

func (m *Manager) SetEnabled(name string, enabled bool) error {
	m.mu.Lock(); defer m.mu.Unlock()
	s, ok := m.specs[name]
	if !ok { return errors.New("plugin not found") }
	s.Enabled = enabled
	m.specs[name] = s
	return nil
}

func (m *Manager) Start(name string) error {
	m.mu.Lock()
	s, ok := m.specs[name]
	if !ok { m.mu.Unlock(); return errors.New("plugin not found") }
	if _, exists := m.handles[name]; exists {
		m.mu.Unlock(); return nil // already running
	}
	path := s.Path
	if runtime.GOOS == "windows" && filepath.Ext(path) == "" {
		path += ".exe"
	}
	cmd := exec.Command(path, s.Args...)
	env := os.Environ()
	env = append(env, "SENTINEL_GRPC="+m.grpcAddr)
	for k, v := range s.Env {
		env = append(env, k+"="+v)
	}
	cmd.Env = env
	if err := cmd.Start(); err != nil {
		m.mu.Unlock()
		return err
	}
	m.handles[name] = &Handle{Cmd: cmd, Started: time.Now()}
	m.mu.Unlock()
	go func() {
		_ = cmd.Wait()
		m.mu.Lock()
		delete(m.handles, name)
		m.mu.Unlock()
	}()
	return nil
}

func (m *Manager) Stop(name string) error {
	m.mu.Lock()
	h, ok := m.handles[name]
	if !ok { m.mu.Unlock(); return nil }
	cmd := h.Cmd
	m.mu.Unlock()

	if cmd.Process == nil { return nil }
	if runtime.GOOS == "windows" {
		return cmd.Process.Kill()
	}
	// tente SIGTERM
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
		return cmd.Process.Kill()
	}
	return nil
}

func (m *Manager) StartEnabled() {
	for _, s := range m.List() {
		if s.Enabled {
			_ = m.Start(s.Name)
		}
	}
}
'@
Ensure-File (Join-Path $Root "internal\plugin\loader.go") $loaderGo

# ---------------- pkg/web/monitor.go ----------------
$monitorGo = @'
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
'@
Ensure-File (Join-Path $Root "pkg\web\monitor.go") $monitorGo

# ---------------- pkg/web/server.go ----------------
$webServerGo = @'
package web

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

func Start(addr string, st *State) error {
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir("webui")))
	mux.HandleFunc("/api/agents", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(st.Snapshot())
	})
	mux.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "stream unsupported", http.StatusInternalServerError)
			return
		}
		t := time.NewTicker(2 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-r.Context().Done():
				return
			case <-t.C:
				payload, _ := json.Marshal(st.Snapshot())
				fmt.Fprintf(w, "data: %s\n\n", payload)
				flusher.Flush()
			}
		}
	})

	log.Printf("web listening on http://%s", addr)
	return http.ListenAndServe(addr, mux)
}
'@
Ensure-File (Join-Path $Root "pkg\web\server.go") $webServerGo

# ---------------- pkg/ui/manager.go (Bubble Tea TUI) ----------------
$uiGo = @'
package ui

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/plugin"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type Model struct{
	state   *web.State
	pm      *plugin.Manager
	cursor  int
	help    bool
}

func NewModel(st *web.State, pm *plugin.Manager) Model {
	return Model{state: st, pm: pm}
}

type tickMsg struct{}

func (m Model) Init() tea.Cmd { return tea.Tick(time.Second, func(time.Time) tea.Msg { return tickMsg{} }) }

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg.(type) {
	case tickMsg:
		return m, tea.Tick(time.Second, func(time.Time) tea.Msg { return tickMsg{} })
	case tea.KeyMsg:
		k := msg.(tea.KeyMsg).String()
		switch k {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "j", "down":
			m.cursor++
		case "k", "up":
			if m.cursor > 0 { m.cursor-- }
		case "enter":
			// start/stop
			specs := m.sortedSpecs()
			if len(specs) == 0 { return m, nil }
			sel := specs[m.cursor % len(specs)]
			if m.pm.IsRunning(sel.Name) {
				_ = m.pm.Stop(sel.Name)
			} else {
				_ = m.pm.Start(sel.Name)
			}
		case "d":
			// enable/disable
			specs := m.sortedSpecs()
			if len(specs) == 0 { return m, nil }
			sel := specs[m.cursor % len(specs)]
			_ = m.pm.SetEnabled(sel.Name, !sel.Enabled)
		case "h", "?":
			m.help = !m.help
		}
	}
	return m, nil
}

func (m Model) View() string {
	title := lipgloss.NewStyle().Bold(true).Underline(true).Render("Sentinel — Eyes Manager")
	rows := m.rows()
	header := "  NAME                 LANG   ENABLED  RUNNING  STATUS      UPTIME      NOTE\n"
	body := strings.Join(rows, "\n")
	footer := "\n\n[↑/↓] mover  [Enter] start/stop  [d] enable/disable  [h] help  [q] quit"
	if m.help {
		footer += "\nHelp: O menu permite ativar/desativar eyes, iniciar/parar processos e visualizar uptime em tempo real.\nUse o config.yaml para editar paths/args/env/descrição."
	}
	return fmt.Sprintf("%s\n\n%s%s\n%s", title, header, body, footer)
}

func (m Model) rows() []string {
	specs := m.sortedSpecs()
	agents := m.state.Snapshot()
	stat := map[string]web.AgentInfo{}
	for _, a := range agents {
		stat[a.ID] = a
	}
	now := time.Now()
	out := make([]string, 0, len(specs))
	for i, s := range specs {
		sel := " "
		if i == (m.cursor % max(1,len(specs))) { sel = ">" }
		running := m.pm.IsRunning(s.Name)
		a := stat[s.Name] // usamos Name como ID esperado; ok p/ exemplos
		uptime := "-"
		if !a.Started.IsZero() {
			uptime = (now.Sub(a.Started)).Truncate(time.Second).String()
		}
		row := fmt.Sprintf("%s %-20s  %-5s  %-7v  %-7v  %-10s  %-10s  %-s",
			sel, clip(s.Name,20), clip(strings.ToLower(s.Language),5), s.Enabled, running, clip(a.Status,10), clip(uptime,10), clip(a.Note,50))
		out = append(out, row)
	}
	return out
}

func (m Model) sortedSpecs() []struct{
	Name string; Language string; Enabled bool;
} {
	list := m.pm.List()
	out := make([]struct{Name string; Language string; Enabled bool}, 0, len(list))
	for _, s := range list {
		out = append(out, struct{Name string; Language string; Enabled bool}{s.Name, s.Language, s.Enabled})
	}
	sort.Slice(out, func(i,j int) bool { return out[i].Name < out[j].Name })
	return out
}

func max(a,b int) int { if a>b { return a }; return b }
func clip(s string, n int) string {
	if len([]rune(s)) <= n { return s }
	r := []rune(s)
	return string(r[:n-1])+"…"
}
'@
Ensure-File (Join-Path $Root "pkg\ui\manager.go") $uiGo

# ---------------- cmd/cli.go ----------------
$cliGo = @'
package cmd

import (
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/api"
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
	Short: "Sentinel — gerenciador de plugins (eyes) de segurança",
	Long:  "Sentinel é o orquestrador que registra e monitora 'eyes' via gRPC e expõe status via CLI e Web.",
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
	Short: "Mostra a versão",
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
'@
Ensure-File (Join-Path $Root "cmd\cli.go") $cliGo

# ---------------- cmd/gui.go (Fyne GUI) ----------------
$fyneGo = @'
package cmd

import (
	"fmt"
	"sort"

	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/config"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/plugin"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

func runFyne() error {
	cfg := config.Load()
	pm := plugin.NewManager(cfg.GRPCListen, cfg.Plugins)
	state := web.NewState() // Web/GRPC não sobem aqui, é só demo local do manager; evoluir para se conectar a /api/agents

	a := app.New()
	w := a.NewWindow("Sentinel GUI")
	w.Resize(fyne.NewSize(800, 500))

	specs := pm.List()
	sort.Slice(specs, func(i,j int) bool { return specs[i].Name < specs[j].Name })

	list := widget.NewList(
		func() int { return len(specs) },
		func() fyne.CanvasObject { return widget.NewLabel("item") },
		func(i widget.ListItemID, o fyne.CanvasObject) {
			o.(*widget.Label).SetText(fmt.Sprintf("%s (%s) — enabled:%v", specs[i].Name, specs[i].Language, specs[i].Enabled))
		},
	)

	startBtn := widget.NewButton("Start", func(){
		id := list.Selected
		if id >=0 && id < len(specs) {
			_ = pm.Start(specs[id].Name)
		}
	})
	stopBtn := widget.NewButton("Stop", func(){
		id := list.Selected
		if id >=0 && id < len(specs) {
			_ = pm.Stop(specs[id].Name)
		}
	})
	toggleBtn := widget.NewButton("Enable/Disable", func(){
		id := list.Selected
		if id >=0 && id < len(specs) {
			_ = pm.SetEnabled(specs[id].Name, !specs[id].Enabled)
			specs = pm.List()
			sort.Slice(specs, func(i,j int) bool { return specs[i].Name < specs[j].Name })
			list.Refresh()
		}
	})

	w.SetContent(container.NewBorder(nil, container.NewHBox(startBtn, stopBtn, toggleBtn), nil, nil, list))
	w.ShowAndRun()
	return nil
}
'@
Ensure-File (Join-Path $Root "cmd\gui.go") $fyneGo

# ---------------- webui/index.html ----------------
$indexHtml = @'
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>Sentinel Web UI</title>
  <style>
    body{font-family:system-ui,Segoe UI,Arial;margin:20px}
    table{border-collapse:collapse;width:100%}
    th,td{border:1px solid #ddd;padding:8px}
    th{background:#f5f5f5}
  </style>
</head>
<body>
  <h1>Sentinel — Agents</h1>
  <table id="tbl">
    <thead><tr><th>Name</th><th>Lang</th><th>Status</th><th>Uptime</th><th>Note</th></tr></thead>
    <tbody></tbody>
  </table>
  <script>
    const tbody = document.querySelector('#tbl tbody');
    function render(list){
      tbody.innerHTML = '';
      const now = Date.now();
      for(const a of list){
        const started = new Date(a.Started);
        const uptimeMs = now - started.getTime();
        const d = Math.floor(uptimeMs/86400000);
        const h = String(Math.floor((uptimeMs%86400000)/3600000)).padStart(2,'0');
        const m = String(Math.floor((uptimeMs%3600000)/60000)).padStart(2,'0');
        const s = String(Math.floor((uptimeMs%60000)/1000)).padStart(2,'0');
        const upt = (d>0?d+'d ':'')+h+':'+m+':'+s;
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${a.Name}</td><td>${a.Language}</td><td>${a.Status}</td><td>${upt}</td><td>${a.Note||''}</td>`;
        tbody.appendChild(tr);
      }
    }
    const evt = new EventSource('/events');
    evt.onmessage = e => { render(JSON.parse(e.data)); };
  </script>
</body>
</html>
'@
Ensure-File (Join-Path $Root "webui\index.html") $indexHtml

# ---------------- main.go ----------------
$mainGo = @'
package main

import "github.com/Space-Cowb0y/Palantir_v2/sentinel/cmd"

func main() {
	cmd.Execute()
}
'@
Ensure-File (Join-Path $Root "main.go") $mainGo

# ---------------- README.md ----------------
$readme = @'
# Sentinel

- CLI único: `sentinel serve` (sobe gRPC + Web + TUI + gerencia eyes)
- GUI opcional: `sentinel gui` (Fyne)
- Config: `config.yaml`

## Rodando

1) Gerar gRPC (Go):

param(
  [string]$Root = "$PSScriptRoot\..\Palantir\sentinel"
)

function Ensure-Dir {
  param([string]$Path)
  if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Ensure-File {
  param([string]$Path, [string]$Content)
  $dir = Split-Path $Path -Parent
  Ensure-Dir $dir
  if (!(Test-Path $Path)) {
    $Content | Out-File -FilePath $Path -Encoding UTF8
    Write-Host "Created $Path"
  } else {
    Write-Host "Exists  $Path (skipped)"
  }
}

Write-Host "Scaffolding in $Root"
Ensure-Dir $Root

# ---------------- go.mod ----------------
$gomod = @'
module github.com/Space-Cowb0y/Palantir_v2/sentinel

go 1.25.1

require (
  fyne.io/fyne/v2 v2.4.5
  github.com/charmbracelet/bubbletea v0.26.6
  github.com/charmbracelet/lipgloss v0.11.0
  github.com/spf13/cobra v1.8.0
  google.golang.org/grpc v1.66.1
  google.golang.org/protobuf v1.34.2
  gopkg.in/yaml.v3 v3.0.1
)

replace fyne.io/fyne/v2 => fyne.io/fyne/v2 v2.4.5
'@

Ensure-File (Join-Path $Root "go.mod") $gomod

# ---------------- api/agent.proto ----------------
$proto = @'
syntax = "proto3";
package agent;

option go_package = "github.com/Space-Cowb0y/Palantir_v2/sentinel/api;agentpb";

message RegisterRequest {
  string id = 1;
  string name = 2;
  string version = 3;
  string language = 4;
  string hostname = 5;
  string description = 6;
}

message RegisterResponse {
  string assigned_id = 1;
}

message Heartbeat {
  string agent_id = 1;
  int64 started_unix = 2;
  int64 now_unix = 3;
  string status = 4; // running/degraded/stopped
  string note = 5;
}

message Empty {}

service Sentinel {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc StreamHeartbeats(stream Heartbeat) returns (Empty);
}
'@
Ensure-File (Join-Path $Root "api\agent.proto") $proto

# ---------------- api/sentinel_server.go ----------------
$sentinelServer = @'
package api

import (
	"context"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/api"
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
'@
Ensure-File (Join-Path $Root "api\sentinel_server.go") $sentinelServer

# ---------------- internal/config/config.go ----------------
$configGo = @'
package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

type PluginSpec struct {
	Name        string            `yaml:"name"`
	Description string            `yaml:"description"`
	Path        string            `yaml:"path"`
	Args        []string          `yaml:"args"`
	Env         map[string]string `yaml:"env"`
	Language    string            `yaml:"language"`
	Enabled     bool              `yaml:"enabled"`
}

type Config struct {
	HTTPListen string       `yaml:"http_listen"`
	GRPCListen string       `yaml:"grpc_listen"`
	TUI        bool         `yaml:"tui"`
	Plugins    []PluginSpec `yaml:"plugins"`
}

func defaultConfig() Config {
	return Config{
		HTTPListen: "127.0.0.1:8080",
		GRPCListen: "127.0.0.1:50060",
		TUI:        true,
		Plugins: []PluginSpec{
			{
				Name:        "greeter-go",
				Description: "Exemplo em Go que envia heartbeats",
				Path:        "plugins/greeter/greeter.exe",
				Args:        []string{},
				Env:         map[string]string{},
				Language:    "go",
				Enabled:     true,
			},
			{
				Name:        "greeter-rs",
				Description: "Exemplo em Rust (tonic) — skeleton",
				Path:        "eyes/rust/greeter/target/release/greeter.exe",
				Args:        []string{},
				Env:         map[string]string{},
				Language:    "rust",
				Enabled:     false,
			},
			{
				Name:        "greeter-cpp",
				Description: "Exemplo em C++ (gRPC C++) — skeleton",
				Path:        "eyes/cpp/greeter/build/greeter.exe",
				Args:        []string{},
				Env:         map[string]string{},
				Language:    "cpp",
				Enabled:     false,
			},
		},
	}
}

func Load() Config {
	cfgPath := os.Getenv("SENTINEL_CONFIG")
	if cfgPath == "" {
		cfgPath = "config.yaml"
	}
	b, err := os.ReadFile(cfgPath)
	if err != nil {
		return defaultConfig()
	}
	var cfg Config
	if err := yaml.Unmarshal(b, &cfg); err != nil {
		return defaultConfig()
	}
	if cfg.HTTPListen == "" { cfg.HTTPListen = "127.0.0.1:8080" }
	if cfg.GRPCListen == "" { cfg.GRPCListen = "127.0.0.1:50060" }
	return cfg
}
'@
Ensure-File (Join-Path $Root "internal\config\config.go") $configGo

# ---------------- internal/logging/logger.go ----------------
$loggerGo = @'
package logging

import "log"

type Logger struct{}

func New() *Logger { return &Logger{} }
func (l *Logger) Infof(f string, a ...any)  { log.Printf("[INFO] "+f, a...) }
func (l *Logger) Errorf(f string, a ...any) { log.Printf("[ERR ] "+f, a...) }
'@
Ensure-File (Join-Path $Root "internal\logging\logger.go") $loggerGo

# ---------------- internal/plugin/loader.go (manager) ----------------
$loaderGo = @'
package plugin

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"syscall"
	"time"

	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/config"
)

type Handle struct {
	Cmd     *exec.Cmd
	Started time.Time
}

type Manager struct {
	mu      sync.Mutex
	specs   map[string]config.PluginSpec
	handles map[string]*Handle
	grpcAddr string
}

func NewManager(grpcAddr string, specs []config.PluginSpec) *Manager {
	m := &Manager{
		specs:   make(map[string]config.PluginSpec),
		handles: make(map[string]*Handle),
		grpcAddr: grpcAddr,
	}
	for _, s := range specs {
		m.specs[s.Name] = s
	}
	return m
}

func (m *Manager) List() []config.PluginSpec {
	m.mu.Lock(); defer m.mu.Unlock()
	out := make([]config.PluginSpec, 0, len(m.specs))
	for _, s := range m.specs { out = append(out, s) }
	return out
}

func (m *Manager) IsRunning(name string) bool {
	m.mu.Lock(); defer m.mu.Unlock()
	_, ok := m.handles[name]
	return ok
}

func (m *Manager) SetEnabled(name string, enabled bool) error {
	m.mu.Lock(); defer m.mu.Unlock()
	s, ok := m.specs[name]
	if !ok { return errors.New("plugin not found") }
	s.Enabled = enabled
	m.specs[name] = s
	return nil
}

func (m *Manager) Start(name string) error {
	m.mu.Lock()
	s, ok := m.specs[name]
	if !ok { m.mu.Unlock(); return errors.New("plugin not found") }
	if _, exists := m.handles[name]; exists {
		m.mu.Unlock(); return nil // already running
	}
	path := s.Path
	if runtime.GOOS == "windows" && filepath.Ext(path) == "" {
		path += ".exe"
	}
	cmd := exec.Command(path, s.Args...)
	env := os.Environ()
	env = append(env, "SENTINEL_GRPC="+m.grpcAddr)
	for k, v := range s.Env {
		env = append(env, k+"="+v)
	}
	cmd.Env = env
	if err := cmd.Start(); err != nil {
		m.mu.Unlock()
		return err
	}
	m.handles[name] = &Handle{Cmd: cmd, Started: time.Now()}
	m.mu.Unlock()
	go func() {
		_ = cmd.Wait()
		m.mu.Lock()
		delete(m.handles, name)
		m.mu.Unlock()
	}()
	return nil
}

func (m *Manager) Stop(name string) error {
	m.mu.Lock()
	h, ok := m.handles[name]
	if !ok { m.mu.Unlock(); return nil }
	cmd := h.Cmd
	m.mu.Unlock()

	if cmd.Process == nil { return nil }
	if runtime.GOOS == "windows" {
		return cmd.Process.Kill()
	}
	// tente SIGTERM
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
		return cmd.Process.Kill()
	}
	return nil
}

func (m *Manager) StartEnabled() {
	for _, s := range m.List() {
		if s.Enabled {
			_ = m.Start(s.Name)
		}
	}
}
'@
Ensure-File (Join-Path $Root "internal\plugin\loader.go") $loaderGo

# ---------------- pkg/web/monitor.go ----------------
$monitorGo = @'
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
'@
Ensure-File (Join-Path $Root "pkg\web\monitor.go") $monitorGo

# ---------------- pkg/web/server.go ----------------
$webServerGo = @'
package web

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

func Start(addr string, st *State) error {
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir("webui")))
	mux.HandleFunc("/api/agents", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(st.Snapshot())
	})
	mux.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "stream unsupported", http.StatusInternalServerError)
			return
		}
		t := time.NewTicker(2 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-r.Context().Done():
				return
			case <-t.C:
				payload, _ := json.Marshal(st.Snapshot())
				fmt.Fprintf(w, "data: %s\n\n", payload)
				flusher.Flush()
			}
		}
	})

	log.Printf("web listening on http://%s", addr)
	return http.ListenAndServe(addr, mux)
}
'@
Ensure-File (Join-Path $Root "pkg\web\server.go") $webServerGo

# ---------------- pkg/ui/manager.go (Bubble Tea TUI) ----------------
$uiGo = @'
package ui

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/plugin"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type Model struct{
	state   *web.State
	pm      *plugin.Manager
	cursor  int
	help    bool
}

func NewModel(st *web.State, pm *plugin.Manager) Model {
	return Model{state: st, pm: pm}
}

type tickMsg struct{}

func (m Model) Init() tea.Cmd { return tea.Tick(time.Second, func(time.Time) tea.Msg { return tickMsg{} }) }

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg.(type) {
	case tickMsg:
		return m, tea.Tick(time.Second, func(time.Time) tea.Msg { return tickMsg{} })
	case tea.KeyMsg:
		k := msg.(tea.KeyMsg).String()
		switch k {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "j", "down":
			m.cursor++
		case "k", "up":
			if m.cursor > 0 { m.cursor-- }
		case "enter":
			// start/stop
			specs := m.sortedSpecs()
			if len(specs) == 0 { return m, nil }
			sel := specs[m.cursor % len(specs)]
			if m.pm.IsRunning(sel.Name) {
				_ = m.pm.Stop(sel.Name)
			} else {
				_ = m.pm.Start(sel.Name)
			}
		case "d":
			// enable/disable
			specs := m.sortedSpecs()
			if len(specs) == 0 { return m, nil }
			sel := specs[m.cursor % len(specs)]
			_ = m.pm.SetEnabled(sel.Name, !sel.Enabled)
		case "h", "?":
			m.help = !m.help
		}
	}
	return m, nil
}

func (m Model) View() string {
	title := lipgloss.NewStyle().Bold(true).Underline(true).Render("Sentinel — Eyes Manager")
	rows := m.rows()
	header := "  NAME                 LANG   ENABLED  RUNNING  STATUS      UPTIME      NOTE\n"
	body := strings.Join(rows, "\n")
	footer := "\n\n[↑/↓] mover  [Enter] start/stop  [d] enable/disable  [h] help  [q] quit"
	if m.help {
		footer += "\nHelp: O menu permite ativar/desativar eyes, iniciar/parar processos e visualizar uptime em tempo real.\nUse o config.yaml para editar paths/args/env/descrição."
	}
	return fmt.Sprintf("%s\n\n%s%s\n%s", title, header, body, footer)
}

func (m Model) rows() []string {
	specs := m.sortedSpecs()
	agents := m.state.Snapshot()
	stat := map[string]web.AgentInfo{}
	for _, a := range agents {
		stat[a.ID] = a
	}
	now := time.Now()
	out := make([]string, 0, len(specs))
	for i, s := range specs {
		sel := " "
		if i == (m.cursor % max(1,len(specs))) { sel = ">" }
		running := m.pm.IsRunning(s.Name)
		a := stat[s.Name] // usamos Name como ID esperado; ok p/ exemplos
		uptime := "-"
		if !a.Started.IsZero() {
			uptime = (now.Sub(a.Started)).Truncate(time.Second).String()
		}
		row := fmt.Sprintf("%s %-20s  %-5s  %-7v  %-7v  %-10s  %-10s  %-s",
			sel, clip(s.Name,20), clip(strings.ToLower(s.Language),5), s.Enabled, running, clip(a.Status,10), clip(uptime,10), clip(a.Note,50))
		out = append(out, row)
	}
	return out
}

func (m Model) sortedSpecs() []struct{
	Name string; Language string; Enabled bool;
} {
	list := m.pm.List()
	out := make([]struct{Name string; Language string; Enabled bool}, 0, len(list))
	for _, s := range list {
		out = append(out, struct{Name string; Language string; Enabled bool}{s.Name, s.Language, s.Enabled})
	}
	sort.Slice(out, func(i,j int) bool { return out[i].Name < out[j].Name })
	return out
}

func max(a,b int) int { if a>b { return a }; return b }
func clip(s string, n int) string {
	if len([]rune(s)) <= n { return s }
	r := []rune(s)
	return string(r[:n-1])+"…"
}
'@
Ensure-File (Join-Path $Root "pkg\ui\manager.go") $uiGo

# ---------------- cmd/cli.go ----------------
$cliGo = @'
package cmd

import (
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/api"
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
	Short: "Sentinel — gerenciador de plugins (eyes) de segurança",
	Long:  "Sentinel é o orquestrador que registra e monitora 'eyes' via gRPC e expõe status via CLI e Web.",
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
	Short: "Mostra a versão",
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
'@
Ensure-File (Join-Path $Root "cmd\cli.go") $cliGo

# ---------------- cmd/gui.go (Fyne GUI) ----------------
$fyneGo = @'
package cmd

import (
	"fmt"
	"sort"

	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/config"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/plugin"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

func runFyne() error {
	cfg := config.Load()
	pm := plugin.NewManager(cfg.GRPCListen, cfg.Plugins)
	state := web.NewState() // Web/GRPC não sobem aqui, é só demo local do manager; evoluir para se conectar a /api/agents

	a := app.New()
	w := a.NewWindow("Sentinel GUI")
	w.Resize(fyne.NewSize(800, 500))

	specs := pm.List()
	sort.Slice(specs, func(i,j int) bool { return specs[i].Name < specs[j].Name })

	list := widget.NewList(
		func() int { return len(specs) },
		func() fyne.CanvasObject { return widget.NewLabel("item") },
		func(i widget.ListItemID, o fyne.CanvasObject) {
			o.(*widget.Label).SetText(fmt.Sprintf("%s (%s) — enabled:%v", specs[i].Name, specs[i].Language, specs[i].Enabled))
		},
	)

	startBtn := widget.NewButton("Start", func(){
		id := list.Selected
		if id >=0 && id < len(specs) {
			_ = pm.Start(specs[id].Name)
		}
	})
	stopBtn := widget.NewButton("Stop", func(){
		id := list.Selected
		if id >=0 && id < len(specs) {
			_ = pm.Stop(specs[id].Name)
		}
	})
	toggleBtn := widget.NewButton("Enable/Disable", func(){
		id := list.Selected
		if id >=0 && id < len(specs) {
			_ = pm.SetEnabled(specs[id].Name, !specs[id].Enabled)
			specs = pm.List()
			sort.Slice(specs, func(i,j int) bool { return specs[i].Name < specs[j].Name })
			list.Refresh()
		}
	})

	w.SetContent(container.NewBorder(nil, container.NewHBox(startBtn, stopBtn, toggleBtn), nil, nil, list))
	w.ShowAndRun()
	return nil
}
'@
Ensure-File (Join-Path $Root "cmd\gui.go") $fyneGo

# ---------------- webui/index.html ----------------
$indexHtml = @'
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>Sentinel Web UI</title>
  <style>
    body{font-family:system-ui,Segoe UI,Arial;margin:20px}
    table{border-collapse:collapse;width:100%}
    th,td{border:1px solid #ddd;padding:8px}
    th{background:#f5f5f5}
  </style>
</head>
<body>
  <h1>Sentinel — Agents</h1>
  <table id="tbl">
    <thead><tr><th>Name</th><th>Lang</th><th>Status</th><th>Uptime</th><th>Note</th></tr></thead>
    <tbody></tbody>
  </table>
  <script>
    const tbody = document.querySelector('#tbl tbody');
    function render(list){
      tbody.innerHTML = '';
      const now = Date.now();
      for(const a of list){
        const started = new Date(a.Started);
        const uptimeMs = now - started.getTime();
        const d = Math.floor(uptimeMs/86400000);
        const h = String(Math.floor((uptimeMs%86400000)/3600000)).padStart(2,'0');
        const m = String(Math.floor((uptimeMs%3600000)/60000)).padStart(2,'0');
        const s = String(Math.floor((uptimeMs%60000)/1000)).padStart(2,'0');
        const upt = (d>0?d+'d ':'')+h+':'+m+':'+s;
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${a.Name}</td><td>${a.Language}</td><td>${a.Status}</td><td>${upt}</td><td>${a.Note||''}</td>`;
        tbody.appendChild(tr);
      }
    }
    const evt = new EventSource('/events');
    evt.onmessage = e => { render(JSON.parse(e.data)); };
  </script>
</body>
</html>
'@
Ensure-File (Join-Path $Root "webui\index.html") $indexHtml

# ---------------- main.go ----------------
$mainGo = @'
package main

import "github.com/Space-Cowb0y/Palantir_v2/sentinel/cmd"

func main() {
	cmd.Execute()
}
'@
Ensure-File (Join-Path $Root "main.go") $mainGo

# ---------------- README.md ----------------
$readme = @'
# Sentinel

- CLI único: `sentinel serve` (sobe gRPC + Web + TUI + gerencia eyes)
- GUI opcional: `sentinel gui` (Fyne)
- Config: `config.yaml`

## Rodando

1) Gerar gRPC (Go):
protoc --go_out=. --go-grpc_out=. api/agent.proto
Build plugins de exemplo (Go):
cd plugins/greeter
go build -o greeter.exe .
cd ../../

yaml
Copiar código

3) Build sentinel:
go build -o sentinel.exe .

yaml
Copiar código

4) Rodar:
.\sentinel.exe serve

swift
Copiar código

Web: http://127.0.0.1:8080

## TUI
- ↑/↓ navega, Enter inicia/para, `d` habilita/desabilita, `q` sai, `h` ajuda.

## Rust / C++
Veja `eyes/rust/greeter` e `eyes/cpp/greeter`.
'@
Ensure-File (Join-Path $Root "README.md") $readme

# ---------------- config.yaml ----------------
$configYaml = @'
http_listen: "127.0.0.1:8080"
grpc_listen: "127.0.0.1:50060"
tui: true

plugins:
  - name: "greeter-go"
    description: "Exemplo em Go que envia heartbeats"
    path: "plugins/greeter/greeter.exe"
    args: []
    env: {}
    language: "go"
    enabled: true

  - name: "greeter-rs"
    description: "Exemplo em Rust (tonic)"
    path: "eyes/rust/greeter/target/release/greeter.exe"
    args: []
    env: {}
    language: "rust"
    enabled: false

  - name: "greeter-cpp"
    description: "Exemplo em C++ (gRPC C++)"
    path: "eyes/cpp/greeter/build/greeter.exe"
    args: []
    env: {}
    language: "cpp"
    enabled: false
'@
Ensure-File (Join-Path $Root "config.yaml") $configYaml

# ---------------- plugins/greeter/main.go (Go eye) ----------------
$goEye = @'
package main

import (
	"context"
	"log"
	"os"
	"time"

	agentpb "github.com/Space-Cowb0y/Palantir_v2/sentinel/api"
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
'@
Ensure-File (Join-Path $Root "plugins\greeter\main.go") $goEye

# ---------------- eyes/rust/greeter (Cargo) ----------------
$rustCargo = @'
[package]
name = "greeter"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
tonic = "0.11"
prost = "0.12"

[build-dependencies]
tonic-build = "0.11"
'@
$rustBuild = @'
fn main() {
    tonic_build::configure()
        .out_dir("src/pb")
        .compile(&["../../../api/agent.proto"], &["../../../api"])
        .unwrap();
    println!("cargo:rerun-if-changed=../../../api/agent.proto");
}
'@
$rustMain = @'
mod pb {
    pub mod agent {
        include!("pb/agent.rs");
    }
}

use pb::agent::{sentinel_client::SentinelClient, RegisterRequest, Heartbeat};
use std::time::{SystemTime, UNIX_EPOCH, Duration};
use tonic::Request;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = std::env::var("SENTINEL_GRPC").unwrap_or_else(|_| "http://127.0.0.1:50060".to_string());
    let mut client = SentinelClient::connect(addr.clone()).await?;

    let hostname = hostname::get().unwrap_or_default().to_string_lossy().to_string();
    let reg = RegisterRequest{
        id: "".into(),
        name: "greeter-rs".into(),
        version: "0.1.0".into(),
        language: "rust".into(),
        hostname,
        description: "hello from greeter-rs".into(),
    };
    let rsp = client.register(Request::new(reg)).await?.into_inner();
    let agent_id = rsp.assigned_id;

    let mut stream = client.stream_heartbeats().await?.into_inner();
    let start = now_unix();

    let mut interval = tokio::time::interval(Duration::from_secs(2));
    loop {
        interval.tick().await;
        let hb = Heartbeat{
            agent_id: agent_id.clone(),
            started_unix: start as i64,
            now_unix: now_unix() as i64,
            status: "running".into(),
            note: "OK".into(),
        };
        if let Err(e) = stream.send(hb).await {
            eprintln!("send hb: {e}");
            break;
        }
    }
    Ok(())
}

fn now_unix() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
}
'@
$rustTomlExtra = @'
hostname = "0.4"
'@
Ensure-File (Join-Path $Root "eyes\rust\greeter\Cargo.toml") $rustCargo
Ensure-File (Join-Path $Root "eyes\rust\greeter\build.rs") $rustBuild
Ensure-File (Join-Path $Root "eyes\rust\greeter\src\main.rs") $rustMain

# append hostname dep if missing
$cargoPath = Join-Path $Root "eyes\rust\greeter\Cargo.toml"
if (Test-Path $cargoPath) {
  $txt = Get-Content $cargoPath -Raw
  if ($txt -notmatch "hostname = ") {
    ($txt + "`n" + $rustTomlExtra) | Out-File -FilePath $cargoPath -Encoding UTF8 -Force
  }
}

# ---------------- eyes/cpp/greeter (CMake) ----------------
$cppCMake = @'
cmake_minimum_required(VERSION 3.20)
project(greeter)
set(CMAKE_CXX_STANDARD 17)

find_package(Protobuf CONFIG REQUIRED)
find_package(gRPC CONFIG REQUIRED)

add_executable(greeter main.cpp)
target_include_directories(greeter PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(greeter PRIVATE gRPC::grpc++ protobuf::libprotobuf)

# Gere os stubs a partir de ../../api/agent.proto antes (protoc):
# protoc --grpc_out=. --plugin=protoc-gen-grpc=<path_grpc_cpp_plugin> --cpp_out=. -I ../../api ../../api/agent.proto
# Isso criará agent.pb.h/.cc e agent.grpc.pb.h/.cc; adicione-os ao target:
# target_sources(greeter PRIVATE agent.pb.cc agent.grpc.pb.cc)
'@
$cppMain = @'
#include <iostream>
#include <memory>
#include <string>
#include <chrono>
#include <thread>

// #include "agent.grpc.pb.h" // gere os stubs conforme instruções no CMake

int main(int argc, char** argv) {
    std::string addr = std::getenv("SENTINEL_GRPC") ? std::getenv("SENTINEL_GRPC") : "127.0.0.1:50060";
    std::cout << "greeter-cpp skeleton. Set up gRPC stubs and send heartbeats to " << addr << std::endl;

    // Pseudocódigo:
    // auto channel = grpc::CreateChannel(addr, grpc::InsecureChannelCredentials());
    // std::unique_ptr<agent::Sentinel::Stub> stub = agent::Sentinel::NewStub(channel);
    // RegisterRequest req; req.set_name("greeter-cpp"); ...
    // auto reg = stub->Register(ctx, req);
    // auto stream = stub->StreamHeartbeats(&ctx);
    // loop: cria Heartbeat (started_unix fixo + now_unix variável), stream->Write(hb)

    // Mantém vivo para teste
    std::this_thread::sleep_for(std::chrono::seconds(5));
    return 0;
}
'@
Ensure-File (Join-Path $Root "eyes\cpp\greeter\CMakeLists.txt") $cppCMake
Ensure-File (Join-Path $Root "eyes\cpp\greeter\main.cpp") $cppMain

# ---------------- utils/push.ps1 (se não existir, deixa dummy) ----------------
$push = @'
Write-Host "git add/commit/push helper - personalize conforme seu fluxo."
'@
Ensure-File (Join-Path $Root "..\..\utils\push.ps1") $push

Write-Host "Done."