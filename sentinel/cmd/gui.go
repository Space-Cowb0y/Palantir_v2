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
	state := web.NewState() // Web/GRPC nÃ£o sobem aqui, Ã© sÃ³ demo local do manager; evoluir para se conectar a /api/agents

	a := app.New()
	w := a.NewWindow("Sentinel GUI")
	w.Resize(fyne.NewSize(800, 500))

	specs := pm.List()
	sort.Slice(specs, func(i,j int) bool { return specs[i].Name < specs[j].Name })

	list := widget.NewList(
		func() int { return len(specs) },
		func() fyne.CanvasObject { return widget.NewLabel("item") },
		func(i widget.ListItemID, o fyne.CanvasObject) {
			o.(*widget.Label).SetText(fmt.Sprintf("%s (%s) â€” enabled:%v", specs[i].Name, specs[i].Language, specs[i].Enabled))
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
