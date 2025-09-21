package web

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/Space-Cowb0y/Palantir_v2/sentinel/internal/store"
)

func Start(addr string, st *State, db *store.Store) error {
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir("webui")))

	mux.HandleFunc("/api/agents", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(st.Snapshot())
	})
	mux.HandleFunc("/api/summary", func(w http.ResponseWriter, r *http.Request) {
		if db == nil { http.Error(w, "no db", 503); return }
		sm, _ := db.GetSummary(context.Background())
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(sm)
	})
	mux.HandleFunc("/api/logs", func(w http.ResponseWriter, r *http.Request) {
		if db == nil { http.Error(w, "no db", 503); return }
		limit := 200
		if q := r.URL.Query().Get("limit"); q != "" { if v, err := strconv.Atoi(q); err==nil { limit = v } }
		logs, _ := db.RecentLogs(context.Background(), limit)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(logs)
	})
	mux.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		flusher, ok := w.(http.Flusher)
		if !ok { http.Error(w, "stream unsupported", http.StatusInternalServerError); return }
		t := time.NewTicker(2 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-r.Context().Done():
				return
			case <-t.C:
				payload, _ := json.Marshal(st.Snapshot())
				fmt.Fprintf(w, "data: %s\n\n", payload)
				flusher.Flush()
			}
		}
	})

	log.Printf("web listening on http://%s", addr)
	return http.ListenAndServe(addr, mux)
}
