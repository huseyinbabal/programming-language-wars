// Go implementation of SPEC.md: 64 shards, each a map plus a container/list LRU behind a mutex.
package main

import (
	"container/list"
	"fmt"
	"hash/maphash"
	"io"
	"log"
	"net/http"
	"os"
	"runtime"
	"strconv"
	"sync"
	"sync/atomic"
)

const shards = 64

type entry struct {
	key   string
	value []byte
}

type shard struct {
	mu    sync.Mutex
	items map[string]*list.Element
	order *list.List // front = most recently used
	limit int
}

type cache struct {
	seed                    maphash.Seed
	shards                  [shards]shard
	hits, misses, evictions atomic.Int64
	entries                 atomic.Int64
}

func newCache(capacity int) *cache {
	c := &cache{seed: maphash.MakeSeed()}
	for i := range c.shards {
		limit := capacity / shards
		if i < capacity%shards {
			limit++
		}
		c.shards[i] = shard{items: make(map[string]*list.Element), order: list.New(), limit: limit}
	}
	return c
}

func (c *cache) shard(key string) *shard {
	return &c.shards[maphash.String(c.seed, key)%shards]
}

func (c *cache) get(key string) ([]byte, bool) {
	s := c.shard(key)
	s.mu.Lock()
	el, ok := s.items[key]
	if !ok {
		s.mu.Unlock()
		c.misses.Add(1)
		return nil, false
	}
	s.order.MoveToFront(el)
	v := el.Value.(*entry).value
	s.mu.Unlock()
	c.hits.Add(1)
	return v, true
}

func (c *cache) put(key string, value []byte) {
	s := c.shard(key)
	s.mu.Lock()
	defer s.mu.Unlock()
	if el, ok := s.items[key]; ok {
		el.Value.(*entry).value = value
		s.order.MoveToFront(el)
		return
	}
	if s.order.Len() >= s.limit {
		oldest := s.order.Back()
		s.order.Remove(oldest)
		delete(s.items, oldest.Value.(*entry).key)
		c.evictions.Add(1)
		c.entries.Add(-1)
	}
	s.items[key] = s.order.PushFront(&entry{key: key, value: value})
	c.entries.Add(1)
}

func validKey(k string) bool {
	if len(k) == 0 || len(k) > 64 {
		return false
	}
	for i := 0; i < len(k); i++ {
		b := k[i]
		if !(b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b >= '0' && b <= '9' || b == '_' || b == '-') {
			return false
		}
	}
	return true
}

func main() {
	capacity := 500000
	if v, err := strconv.Atoi(os.Getenv("CAPACITY")); err == nil && v > 0 {
		capacity = v
	}
	c := newCache(capacity)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /kv/{key}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")
		if !validKey(key) {
			http.Error(w, "bad key", http.StatusBadRequest)
			return
		}
		v, ok := c.get(key)
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Write(v)
	})
	mux.HandleFunc("PUT /kv/{key}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")
		if !validKey(key) {
			http.Error(w, "bad key", http.StatusBadRequest)
			return
		}
		body, err := io.ReadAll(io.LimitReader(r.Body, 1025))
		if err != nil {
			http.Error(w, "read error", http.StatusBadRequest)
			return
		}
		switch {
		case len(body) > 1024:
			w.WriteHeader(http.StatusRequestEntityTooLarge)
		case len(body) == 0:
			http.Error(w, "empty value", http.StatusBadRequest)
		default:
			c.put(key, body)
			w.WriteHeader(http.StatusNoContent)
		}
	})
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "ok") })
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "cache_entries %d\ncache_hits_total %d\ncache_misses_total %d\ncache_evictions_total %d\n",
			c.entries.Load(), c.hits.Load(), c.misses.Load(), c.evictions.Load())
	})

	log.Printf("listening on :8000 cpus=%d capacity=%d gomaxprocs=%d", runtime.NumCPU(), capacity, runtime.GOMAXPROCS(0))
	log.Fatal(http.ListenAndServe("0.0.0.0:8000", mux))
}
