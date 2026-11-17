# Programming Language Wars

The same in-memory cache in several languages, under the same load, all the time, on one machine.
Grafana shows the live numbers, and every merged pull request is marked on the graphs, so each line can be matched to the code that ran.

| Implementation | Stack |
| --- | --- |
| [`impls/go`](impls/go) | Go, standard library: `net/http`, `container/list`, `sync.Mutex` |
| [`impls/rust`](impls/rust) | Rust: `axum`, `tokio`, `lru` |

## How it works

- **The service** is in [`SPEC.md`](SPEC.md): `PUT` and `GET` on `/kv/{key}`, at most 500,000 entries, LRU eviction, four counters on `/metrics`.
- **The load** is [`load/cache.js`](load/cache.js): k6 sends 5,000 GET requests per second to each implementation at the same time, and a PUT after every miss. 20% of the requests go to 100 hot keys.
- **The limits** are in [`stack/compose.yml`](stack/compose.yml): each implementation has its own 2 CPU cores (`cpuset`) and 1 GiB of memory. k6 and the monitoring stack run on other cores.
- **The measurements**: latency and request rate from k6 (Prometheus remote write), CPU and memory per container from cAdvisor, cache counters from each `/metrics`.
- **The page**: [`site/index.html`](site/index.html) embeds the Grafana panels; Caddy serves it and proxies `/grafana/`. Grafana allows anonymous viewers only.
- **Deploys**: [`deploy/deployer.sh`](deploy/deployer.sh) checks `main` every minute, rebuilds the implementations whose folder changed, and writes a Grafana annotation per commit.

## Other comparisons

| Folder | What |
| --- | --- |
| [`rust-vs-cpp`](rust-vs-cpp) | The same four programs (sort, word count, integer-key hash maps, parallel word count) in Rust and C++ with the same LLVM version, measured on one 16-core server: code, raw results, profiles |

## The machine

Live at https://plw.huseyinbabal.dev (one DigitalOcean CPU-Optimized droplet, 8 dedicated vCPUs). One-time setup: [`deploy/setup.sh`](deploy/setup.sh).

## Run it locally

```bash
cp stack/.env.example stack/.env      # set GF_ADMIN_PASSWORD; adjust the CPU sets to your machine
docker compose -f stack/compose.yml --env-file stack/.env up -d --build
open http://localhost:8097
```

Check one implementation against the spec:

```bash
docker run --rm -d --name plw-check -p 8000:8000 -e CAPACITY=128 plw-go
bash tests/conformance.sh http://127.0.0.1:8000
```

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).
