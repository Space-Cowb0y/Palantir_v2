package web

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

func Start(addr string, st *State) error {
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir("webui")))
	mux.HandleFunc("/api/agents", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(st.Snapshot())
	})
	mux.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "stream unsupported", http.StatusInternalServerError)
			return
		}
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
