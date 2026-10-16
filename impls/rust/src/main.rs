// Rust implementation of SPEC.md: 64 shards, each an lru::LruCache behind a mutex, served by axum on tokio.
use std::hash::{BuildHasher, RandomState};
use std::num::NonZeroUsize;
use std::sync::atomic::{AtomicI64, Ordering::Relaxed};
use std::sync::{Arc, Mutex};

use axum::{
    body::Bytes,
    extract::{Path, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Router,
};
use lru::LruCache;

const SHARDS: usize = 64;

struct Cache {
    hasher: RandomState,
    shards: Vec<Mutex<LruCache<String, Bytes>>>,
    hits: AtomicI64,
    misses: AtomicI64,
    evictions: AtomicI64,
    entries: AtomicI64,
}

impl Cache {
    fn new(capacity: usize) -> Self {
        let shards = (0..SHARDS)
            .map(|i| {
                let limit = capacity / SHARDS + usize::from(i < capacity % SHARDS);
                Mutex::new(LruCache::new(NonZeroUsize::new(limit.max(1)).unwrap()))
            })
            .collect();
        Cache {
            hasher: RandomState::new(),
            shards,
            hits: AtomicI64::new(0),
            misses: AtomicI64::new(0),
            evictions: AtomicI64::new(0),
            entries: AtomicI64::new(0),
        }
    }

    fn shard(&self, key: &str) -> &Mutex<LruCache<String, Bytes>> {
        &self.shards[(self.hasher.hash_one(key) as usize) % SHARDS]
    }

    fn get(&self, key: &str) -> Option<Bytes> {
        let found = self.shard(key).lock().unwrap().get(key).cloned();
        match found {
            Some(_) => self.hits.fetch_add(1, Relaxed),
            None => self.misses.fetch_add(1, Relaxed),
        };
        found
    }

    fn put(&self, key: String, value: Bytes) {
        let mut shard = self.shard(&key).lock().unwrap();
        if let Some(v) = shard.get_mut(&key) {
            *v = value;
            return;
        }
        if shard.push(key, value).is_some() {
            // push returns the evicted entry when the shard was full
            self.evictions.fetch_add(1, Relaxed);
        } else {
            self.entries.fetch_add(1, Relaxed);
        }
    }
}

fn valid_key(k: &str) -> bool {
    !k.is_empty() && k.len() <= 64 && k.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

async fn get_kv(State(c): State<Arc<Cache>>, Path(key): Path<String>) -> Response {
    if !valid_key(&key) {
        return (StatusCode::BAD_REQUEST, "bad key").into_response();
    }
    match c.get(&key) {
        Some(v) => ([(header::CONTENT_TYPE, "application/octet-stream")], v).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn put_kv(State(c): State<Arc<Cache>>, Path(key): Path<String>, body: Bytes) -> Response {
    if !valid_key(&key) {
        return (StatusCode::BAD_REQUEST, "bad key").into_response();
    }
    if body.len() > 1024 {
        return StatusCode::PAYLOAD_TOO_LARGE.into_response();
    }
    if body.is_empty() {
        return (StatusCode::BAD_REQUEST, "empty value").into_response();
    }
    c.put(key, body);
    StatusCode::NO_CONTENT.into_response()
}

async fn metrics(State(c): State<Arc<Cache>>) -> String {
    format!(
        "cache_entries {}\ncache_hits_total {}\ncache_misses_total {}\ncache_evictions_total {}\n",
        c.entries.load(Relaxed),
        c.hits.load(Relaxed),
        c.misses.load(Relaxed),
        c.evictions.load(Relaxed)
    )
}

#[tokio::main]
async fn main() {
    let capacity = std::env::var("CAPACITY").ok().and_then(|v| v.parse().ok()).filter(|&v| v > 0).unwrap_or(500_000);
    let cache = Arc::new(Cache::new(capacity));
    let app = Router::new()
        .route("/kv/{key}", get(get_kv).put(put_kv))
        .route("/health", get(|| async { "ok" }))
        .route("/metrics", get(metrics))
        // axum's default body limit is 2 MB; read up to 1025 bytes so larger bodies are answered with 413 by put_kv
        .layer(axum::extract::DefaultBodyLimit::max(1025))
        .with_state(cache);
    let cpus = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    println!("listening on :8000 cpus={cpus} capacity={capacity}");
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
