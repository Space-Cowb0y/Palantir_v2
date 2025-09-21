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
				Description: "Exemplo em Rust (tonic) â€” skeleton",
				Path:        "eyes/rust/greeter/target/release/greeter.exe",
				Args:        []string{},
				Env:         map[string]string{},
				Language:    "rust",
				Enabled:     false,
			},
			{
				Name:        "greeter-cpp",
				Description: "Exemplo em C++ (gRPC C++) â€” skeleton",
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
