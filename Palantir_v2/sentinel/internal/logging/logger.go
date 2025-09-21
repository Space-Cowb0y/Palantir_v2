package logging

import "log"

type Logger struct{}

func New() *Logger { return &Logger{} }
func (l *Logger) Infof(f string, a ...any)  { log.Printf("[INFO] "+f, a...) }
func (l *Logger) Errorf(f string, a ...any) { log.Printf("[ERR ] "+f, a...) }
