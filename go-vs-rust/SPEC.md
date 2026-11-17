# The service every implementation builds

An in-memory key-value cache with a fixed capacity and least-recently-used eviction, served over HTTP.
Every implementation in `impls/` follows this file. The load test and the conformance test only rely on what is written here.

## Endpoints

| Method and path | Request | Response |
| --- | --- | --- |
| `PUT /kv/{key}` | body: the value, 1 to 1024 bytes | `204` stored · `413` body larger than 1024 bytes · `400` empty body |
| `GET /kv/{key}` | | `200` with the stored bytes as the body · `404` not in the cache |
| `GET /health` | | `200`, body `ok` |
| `GET /metrics` | | `200`, Prometheus text format, see below |

- `{key}` is 1 to 64 characters from `[A-Za-z0-9_-]`. Anything else is `400`.
- `PUT` on an existing key replaces the value and marks the key as most recently used.
- `GET` that finds the key marks it as most recently used.
- `Content-Type` of a `200` from `GET /kv/{key}` is `application/octet-stream`.

## Capacity and eviction

- The cache holds at most `CAPACITY` entries (environment variable, default `500000`).
- When a `PUT` of a new key would exceed the capacity, the least recently used entry is removed first.
- The order may be approximate within shards: an implementation can split the cache into shards with their own LRU order, as long as the total number of entries never exceeds `CAPACITY`.

## Metrics

`GET /metrics` returns at least these four series:

```text
cache_entries 123
cache_hits_total 456
cache_misses_total 78
cache_evictions_total 9
```

CPU and memory are not reported by the implementation. They are measured from outside, per container, by cAdvisor.

## Runtime

- Listen on `0.0.0.0:8000`.
- Print one line at startup with the number of CPUs the process can use, for example `listening on :8000 cpus=2 capacity=500000`.
- The container gets the same CPU set and memory limit as every other implementation (`stack/compose.yml`). It must stay inside that memory limit with the cache full.
