package config

import (
	"os"

	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/security"
	"gopkg.in/yaml.v3"
)

type BuildSpec struct {
	WorkDir string   `yaml:"workdir"`
	Steps   []string `yaml:"steps"`
}

type PluginSpec struct {
	Name        string            `yaml:"name"`
	Description string            `yaml:"description"`
	Path        string            `yaml:"path"`
	Args        []string          `yaml:"args"`
	Env         map[string]string `yaml:"env"`
	Language    string            `yaml:"language"`
	Enabled     bool              `yaml:"enabled"`
	Build       BuildSpec         `yaml:"build"`
}

type Config struct {
	DBPath    string              `yaml:"db_path"`
	HTTPListen string             `yaml:"http_listen"`
	GRPCListen string             `yaml:"grpc_listen"`
	TUI        bool               `yaml:"tui"`
	TLS        security.TLSConfig `yaml:"tls"`
	Plugins    []PluginSpec       `yaml:"plugins"`
}

func defaultConfig() Config {
	return Config{
		DBPath:    "sentinel.db",
		HTTPListen: "127.0.0.1:8080",
		GRPCListen: "127.0.0.1:50060",
		TUI:        true,
		TLS:        security.TLSConfig{Enabled:false},
		Plugins: []PluginSpec{
			{
				Name:        "greeter-go",
				Description: "Exemplo em Go que envia heartbeats + logs",
				Path:        "plugins/greeter/greeter.exe",
				Language:    "go",
				Enabled:     true,
				Build: BuildSpec{
					WorkDir: "plugins/greeter",
					Steps:   []string{"go build -o greeter.exe ."},
				},
			},
			{
				Name:        "greeter-rs",
				Description: "Exemplo em Rust (tonic) â€” skeleton",
				Path:        "eyes/rust/greeter/target/release/greeter.exe",
				Language:    "rust",
				Enabled:     false,
				Build: BuildSpec{
					WorkDir: "eyes/rust/greeter",
					Steps:   []string{"cargo build --release"},
				},
			},
			{
				Name:        "greeter-cpp",
				Description: "Exemplo em C++ (gRPC C++) â€” skeleton",
				Path:        "eyes/cpp/greeter/build/greeter.exe",
				Language:    "cpp",
				Enabled:     false,
				Build: BuildSpec{
					WorkDir: "eyes/cpp/greeter",
					Steps:   []string{
						"protoc -I ../../../api --cpp_out=. --grpc_out=. --plugin=protoc-gen-grpc=grpc_cpp_plugin ../../../api/agent.proto",
						"cmake -S . -B build",
						"cmake --build build --config Release",
					},
				},
			},
		},
	}
}

func Load() Config {
	cfgPath := os.Getenv("SENTINEL_CONFIG")
	if cfgPath == "" { cfgPath = "config.yaml" }
	b, err := os.ReadFile(cfgPath)
	if err != nil { return defaultConfig() }
	var cfg Config
	if err := yaml.Unmarshal(b, &cfg); err != nil { return defaultConfig() }
	if cfg.HTTPListen == "" { cfg.HTTPListen = "127.0.0.1:8080" }
	if cfg.GRPCListen == "" { cfg.GRPCListen = "127.0.0.1:50060" }
	if cfg.DBPath == "" { cfg.DBPath = "sentinel.db" }
	return cfg
}
