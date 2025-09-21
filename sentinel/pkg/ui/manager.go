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
	title := lipgloss.NewStyle().Bold(true).Underline(true).Render("Sentinel â€” Eyes Manager")
	rows := m.rows()
	header := "  NAME                 LANG   ENABLED  RUNNING  STATUS      UPTIME      NOTE\n"
	body := strings.Join(rows, "\n")
	footer := "\n\n[â†‘/â†“] mover  [Enter] start/stop  [d] enable/disable  [h] help  [q] quit"
	if m.help {
		footer += "\nHelp: O menu permite ativar/desativar eyes, iniciar/parar processos e visualizar uptime em tempo real.\nUse o config.yaml para editar paths/args/env/descriÃ§Ã£o."
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
	return string(r[:n-1])+"â€¦"
}
