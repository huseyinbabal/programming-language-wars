# Contributing

Improve an implementation, or add a new language.

## Rules

1. Follow [`SPEC.md`](SPEC.md). `tests/conformance.sh` must pass; CI runs it on every pull request.
2. Stay inside the limits in `stack/compose.yml`: 2 cores and 1 GiB with the cache full. Do not change the limits, the load script or another language's folder in the same pull request.
3. Any library and any data structure is fine. No caching outside the process, no talking to other services, and no reading the load script's key pattern to special-case it (for example, hard-coding the hot keys).
4. Runtime settings for your language (for example `GOMEMLIMIT`, or a thread count) go in your service block in `stack/compose.yml`, with a comment that says why.
5. Say in the pull request description what you changed and what you expect to see on the graphs.

## What happens after a merge

The benchmark machine only runs code that is on `main`. Within a minute of a merge it rebuilds the implementations that changed and adds an annotation with the commit to every graph. Pull requests are never run on that machine.

## Adding a language

1. Create `impls/<language>/` with a `Dockerfile` that listens on port 8000.
2. Add a service to `stack/compose.yml` (copy an existing one, use the next free CPU set), a target to `prometheus.yml`, a `TARGETS` entry for k6, and the language to the CI matrix.
3. The machine has a fixed number of cores, so a new language may have to wait for a bigger machine.
