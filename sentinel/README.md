# Sentinel

- CLI Ãºnico: `sentinel serve` (sobe gRPC + Web + TUI + gerencia eyes)
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
Copiar cÃ³digo

3) Build sentinel:
go build -o sentinel.exe .

yaml
Copiar cÃ³digo

4) Rodar:
.\sentinel.exe serve

swift
Copiar cÃ³digo

Web: http://127.0.0.1:8080

## TUI
- â†‘/â†“ navega, Enter inicia/para, `d` habilita/desabilita, `q` sai, `h` ajuda.

## Rust / C++
Veja `eyes/rust/greeter` e `eyes/cpp/greeter`.
