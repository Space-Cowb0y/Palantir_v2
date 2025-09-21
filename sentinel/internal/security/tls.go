package security

import (
	"crypto/tls"
	"crypto/x509"
	"os"

	"google.golang.org/grpc/credentials"
)

type TLSConfig struct {
	Enabled    bool   `yaml:"enabled"`
	CAFile     string `yaml:"ca_file"`
	CertFile   string `yaml:"cert_file"`
	KeyFile    string `yaml:"key_file"`
	ServerName string `yaml:"servername"`
}

func ServerCreds(cfg TLSConfig) (credentials.TransportCredentials, error) {
	cert, err := tls.LoadX509KeyPair(cfg.CertFile, cfg.KeyFile)
	if err != nil { return nil, err }
	caBytes, err := os.ReadFile(cfg.CAFile)
	if err != nil { return nil, err }
	cp := x509.NewCertPool()
	if !cp.AppendCertsFromPEM(caBytes) { return nil, err }
	tlsCfg := &tls.Config{
		Certificates: []tls.Certificate{cert},
		ClientAuth:   tls.RequireAndVerifyClientCert,
		ClientCAs:    cp,
		MinVersion:   tls.VersionTLS12,
	}
	return credentials.NewTLS(tlsCfg), nil
}

func ClientCreds(cfg TLSConfig) (credentials.TransportCredentials, error) {
	cert, err := tls.LoadX509KeyPair(cfg.CertFile, cfg.KeyFile)
	if err != nil { return nil, err }
	caBytes, err := os.ReadFile(cfg.CAFile)
	if err != nil { return nil, err }
	cp := x509.NewCertPool()
	if !cp.AppendCertsFromPEM(caBytes) { return nil, err }
	tlsCfg := &tls.Config{
		ServerName:   cfg.ServerName,
		RootCAs:      cp,
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS12,
	}
	return credentials.NewTLS(tlsCfg), nil
}
