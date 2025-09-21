package plugin

import (
	//"context"
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
