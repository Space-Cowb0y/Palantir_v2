package types

type Plugin interface {
	Name() string
	Run() error
}
