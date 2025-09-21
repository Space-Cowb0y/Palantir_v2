package plugin

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
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
	mu       sync.Mutex
	specs    map[string]config.PluginSpec
	handles  map[string]*Handle
	grpcAddr string
	tlsEnv   map[string]string
}

func NewManager(grpcAddr string, specs []config.PluginSpec) *Manager {
	m := &Manager{
		specs:   make(map[string]config.PluginSpec),
		handles: make(map[string]*Handle),
		grpcAddr: grpcAddr,
	}
	for _, s := range specs { m.specs[s.Name] = s }
	return m
}

func (m *Manager) WithTLSEnv(enable bool, ca, cert, key, servername string) {
	if !enable { m.tlsEnv = nil; return }
	m.tlsEnv = map[string]string{
		"SENTINEL_TLS": "1",
		"SENTINEL_TLS_CA": ca,
		"SENTINEL_TLS_CERT": cert,
		"SENTINEL_TLS_KEY": key,
		"SENTINEL_TLS_SERVERNAME": servername,
	}
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

func (m *Manager) Build(name string) error {
	m.mu.Lock()
	s, ok := m.specs[name]
	m.mu.Unlock()
	if !ok { return errors.New("plugin not found") }
	if len(s.Build.Steps) == 0 { return nil }
	wd := s.Build.WorkDir
	if wd == "" { wd = "." }
	for _, step := range s.Build.Steps {
		var cmd *exec.Cmd
		if runtime.GOOS == "windows" {
			cmd = exec.Command("cmd.exe", "/c", step)
		} else {
			cmd = exec.Command("bash", "-lc", step)
		}
		cmd.Dir = wd
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		// inherit env
		if err := cmd.Run(); err != nil {
			return err
		}
	}
	return nil
}

func (m *Manager) Start(name string) error {
	m.mu.Lock()
	s, ok := m.specs[name]
	if !ok { m.mu.Unlock(); return errors.New("plugin not found") }
	if _, exists := m.handles[name]; exists { m.mu.Unlock(); return nil }
	path := s.Path
	if runtime.GOOS == "windows" && filepath.Ext(path) == "" {
		path += ".exe"
	}
	cmd := exec.Command(path, s.Args...)
	env := os.Environ()
	env = append(env, "SENTINEL_GRPC="+m.grpcAddr)
	for k, v := range s.Env { env = append(env, k+"="+v) }
	for k, v := range m.tlsEnv { env = append(env, k+"="+v) }
	// set AGENT_ID default to Name (helps correlacionar)
	env = append(env, "SENTINEL_AGENT_ID="+s.Name)
	cmd.Env = env
	// capture stdout/stderr to prepend agent name (agregaÃ§Ã£o simples)
	cmd.Stdout = prefixWriter(os.Stdout, s.Name)
	cmd.Stderr = prefixWriter(os.Stderr, s.Name)
	if err := cmd.Start(); err != nil { m.mu.Unlock(); return err }
	m.handles[name] = &Handle{Cmd: cmd, Started: time.Now()}
	m.mu.Unlock()
	go func() {
		_ = cmd.Wait()
		m.mu.Lock(); delete(m.handles, name); m.mu.Unlock()
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
	if runtime.GOOS == "windows" { return cmd.Process.Kill() }
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil { return cmd.Process.Kill() }
	return nil
}

func (m *Manager) StartEnabled() {
	for _, s := range m.List() {
		if s.Enabled {
			_ = m.Build(s.Name)
			_ = m.Start(s.Name)
		}
	}
}

type prefWriter struct{ w *os.File; tag string }
func (p prefWriter) Write(b []byte) (int, error) {
	line := strings.TrimRight(string(b), "\r\n")
	return p.w.WriteString("["+p.tag+"] "+line+"\n")
}
func prefixWriter(w *os.File, tag string) *prefWriter { return &prefWriter{w, tag} }
