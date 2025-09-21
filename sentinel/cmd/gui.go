package cmd

import (
	"context"
	"fmt"
	"net/http"
	"time"
	"sort"

	"github.com/Space-Cowb0y/Palantir/sentinel/internal/logging"
	ui "github.com/Space-Cowb0y/Palantir/sentinel/pkg/ui"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/config"
	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/plugin"
	web "github.com/Space-Cowb0y/Palantir_v2/sentinel/pkg/web"
	"github.com/spf13/cobra"
/* 	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget" */
)

/* func runFyne() error {
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
} */


/* 
var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run sentinel services (gRPC + HTTP) and watch for Eyes",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfgPath, _ := cmd.Flags().GetString("config")
		cfg, err := config.Load(cfgPath)
		if err != nil { return err }

		log := logging.New(cfg.LogLevel)
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		// Start HTTP server (serves /healthz and static webui)
		httpSrv := web.NewHTTPServer(cfg, log)
		go func(){ _ = httpSrv.Start() }()

		// Start gRPC server (for Eyes)
		grpcSrv := web.NewGRPCServer(cfg, log)
		go func(){ _ = grpcSrv.Start() }()

		// Start plugin watcher/loader
		mgr := plugin.NewManager(cfg, log)
		go mgr.Watch(ctx)

		log.Info("Sentinel running", "http", fmt.Sprintf("http://%s", httpSrv.Addr()), "grpc", grpcSrv.Addr())
		<-ctx.Done()
		return nil
	},
}

var uiCmd = &cobra.Command{
	Use:   "ui",
	Short: "Open the TUI (Bubble Tea) dashboard",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.Load("sentinel.yaml"); if err != nil { return err }
		// log := logging.New(cfg.LogLevel)

		model := ui.NewManagerModel(func() ([]ui.EyeRow, error) {
			// Poll known Eyes from plugin manager’s registry
			return ui.QueryEyesOverHTTP(cfg.HTTP.Listen), nil
		})
		return ui.Run(model)
	},
}

var pluginsCmd = &cobra.Command{ Use: "plugins", Short: "Manage/list Eyes" }
var pluginsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List discovered Eyes",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, _ := config.Load("sentinel.yaml")
		resp, err := http.Get("http://" + cfg.HTTP.Listen + "/api/eyes")
		if err != nil { return err }
		defer resp.Body.Close()
		fmt.Println("HTTP:", resp.Status)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(runCmd, uiCmd, pluginsCmd)
	pluginsCmd.AddCommand(pluginsListCmd)

	// small delay to help Windows console attach
	time.Sleep(50 * time.Millisecond)
} */