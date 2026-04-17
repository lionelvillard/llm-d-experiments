package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync/atomic"
	"time"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <serve|worker|loadgen> [flags]\n", os.Args[0])
		os.Exit(1)
	}
	cmd := os.Args[1]
	os.Args = append(os.Args[:1], os.Args[2:]...)

	switch cmd {
	case "serve":
		runServe()
	case "worker":
		runWorker()
	case "loadgen":
		runLoadgen()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", cmd)
		os.Exit(1)
	}
}

// --- serve: queue server ---

func runServe() {
	addr := flag.String("addr", ":8080", "listen address")
	flag.Parse()

	var queueLength int64
	var totalDequeued int64

	http.HandleFunc("POST /enqueue", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt64(&queueLength, 1)
		w.WriteHeader(http.StatusOK)
	})

	http.HandleFunc("POST /dequeue", func(w http.ResponseWriter, r *http.Request) {
		for {
			cur := atomic.LoadInt64(&queueLength)
			if cur <= 0 {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			if atomic.CompareAndSwapInt64(&queueLength, cur, cur-1) {
				atomic.AddInt64(&totalDequeued, 1)
				w.WriteHeader(http.StatusOK)
				return
			}
		}
	})

	http.HandleFunc("GET /metrics", func(w http.ResponseWriter, r *http.Request) {
		q := atomic.LoadInt64(&queueLength)
		d := atomic.LoadInt64(&totalDequeued)
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "# HELP queue_length Current number of items in the queue.\n")
		fmt.Fprintf(w, "# TYPE queue_length gauge\n")
		fmt.Fprintf(w, "queue_length %d\n", q)
		fmt.Fprintf(w, "# HELP queue_dequeued_total Total items dequeued.\n")
		fmt.Fprintf(w, "# TYPE queue_dequeued_total counter\n")
		fmt.Fprintf(w, "queue_dequeued_total %d\n", d)
	})

	http.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	log.Printf("queue-server listening on %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, nil))
}

// --- worker: dequeue at a fixed rate ---

func runWorker() {
	server := flag.String("server", "http://queue-server:8080", "queue server URL")
	rate := flag.Int("rate", 10, "dequeue rate (req/s)")
	startupDelay := flag.Duration("startup-delay", 60*time.Second, "delay before processing starts")
	addr := flag.String("addr", ":8081", "health check listen address")
	flag.Parse()

	var ready int32

	// Start health check server immediately (startup probe needs it).
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		if atomic.LoadInt32(&ready) == 0 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	go func() {
		log.Fatal(http.ListenAndServe(*addr, mux))
	}()

	log.Printf("worker: waiting %s before starting (simulating slow startup)...", *startupDelay)
	time.Sleep(*startupDelay)
	atomic.StoreInt32(&ready, 1)
	log.Printf("worker: ready, dequeuing at %d req/s from %s", *rate, *server)

	client := &http.Client{Timeout: 5 * time.Second}
	ticker := time.NewTicker(time.Second / time.Duration(*rate))
	defer ticker.Stop()

	dequeueURL := *server + "/dequeue"
	for range ticker.C {
		req, err := http.NewRequest(http.MethodPost, dequeueURL, nil)
		if err != nil {
			log.Printf("worker: request error: %v", err)
			continue
		}
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("worker: dequeue error: %v", err)
			continue
		}
		resp.Body.Close()
	}
}

// --- loadgen: enqueue at a fixed rate ---

func runLoadgen() {
	server := flag.String("server", "http://queue-server:8080", "queue server URL")
	rate := flag.Int("rate", 100, "enqueue rate (req/s)")
	flag.Parse()

	log.Printf("loadgen: enqueuing at %d req/s to %s", *rate, *server)

	client := &http.Client{Timeout: 5 * time.Second}
	ticker := time.NewTicker(time.Second / time.Duration(*rate))
	defer ticker.Stop()

	enqueueURL := *server + "/enqueue"
	var total int64
	logTicker := time.NewTicker(5 * time.Second)
	defer logTicker.Stop()

	for {
		select {
		case <-ticker.C:
			req, err := http.NewRequest(http.MethodPost, enqueueURL, nil)
			if err != nil {
				log.Printf("loadgen: request error: %v", err)
				continue
			}
			resp, err := client.Do(req)
			if err != nil {
				log.Printf("loadgen: enqueue error: %v", err)
				continue
			}
			resp.Body.Close()
			total++
		case <-logTicker.C:
			log.Printf("loadgen: total enqueued: %d", total)
		}
	}
}
