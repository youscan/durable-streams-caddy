# Durable Streams · Caddy

OCI images for the [Durable Streams](https://github.com/durable-streams/durable-streams) Caddy plugin. Upstream ships the plugin as a Caddy module but does not publish container images; this repo closes that gap.

## Quick start

```bash
docker run --rm -p 4437:4437 -v ds-data:/data \
  ghcr.io/youscan/durable-streams-caddy:latest
```

The image bakes in a default `Caddyfile` with file-backed storage at `/data`. To override, mount your own:

```bash
docker run --rm -p 4437:4437 \
  -v $(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v ds-data:/data \
  ghcr.io/youscan/durable-streams-caddy:latest
```

## What's inside

| Component | Pinned version |
|---|---|
| Caddy core | `2.10.2` |
| `durable_streams` plugin | `caddy-v0.2.1` |
| xcaddy (build only) | `v0.4.2` |
| Go (build only) | `1.26.2` |
| Conformance suite (test only) | `@durable-streams/server-conformance-tests@0.2.0` |

All pins live in [`versions.env`](./versions.env) and are consumed by the `Makefile` and (forthcoming) GHA workflows.

## Protocol coverage

This image is a faithful build of plugin **`caddy-v0.2.1`** and passes **196/196** tests in the contemporaneous conformance suite (`v0.2.0`).

[`PROTOCOL.md`](https://github.com/durable-streams/durable-streams/blob/main/PROTOCOL.md) is a live `DRAFT` document. The 0.2.x plugin line predates several spec additions:

| Spec area | In this image | Note |
|---|---|---|
| §4.1 Stream Closure | partial | Some edge cases added after `v0.2.1` |
| §4.2 Stream forking | ✗ | Added to spec 2026-04-06 |
| Sliding TTL renewal (§3, §4.2) | ✗ | Added to spec 2026-04-08 |
| §5.1–5.8 (CRUD, reads, long-poll, SSE) | ✓ | |
| §5.2.1 Idempotent producers | ✓ | |
| §6 Offsets | ✓ | |
| §7 / §7.1 Content types + JSON mode | ✓ | |
| §8 Caching / collapsing | ✓ | |

Plugin code on upstream `main` already implements fork + sliding TTL, but no `caddy-v0.3.x` tag has been cut. This repo will bump `versions.env` (plugin and conformance together) once that tag lands and re-run conformance 0.3.0.

## Configuration

Default Caddyfile baked into the image:

```caddyfile
{
    admin off
    auto_https off
}

:4437 {
    route /v1/stream/* {
        durable_streams {
            data_dir /data
        }
    }
}
```

Plugin directives (per upstream):

- `data_dir <path>` — file-backed (bbolt) storage. Omit for in-memory.
- `long_poll_timeout <duration>` — default `30s`.
- `sse_reconnect_interval <duration>` — default `120s`.

## Development

| Target | What it does |
|---|---|
| `make build` | Single-arch local build |
| `make buildx` | Multi-arch build (no push) |
| `make push` | Multi-arch build + push to `$(REGISTRY)` |
| `make smoke` | Verify `http.handlers.durable_streams` is linked into the binary |
| `make test` | Run upstream conformance suite against the built image |
| `make run` / `make up` | Run container in foreground / detached on `$(PORT)` |
| `make down` / `make logs` / `make clean` | Stop / tail / nuke |
| `make version` | Print resolved versions and image name |

`make test` spawns the image on port 14437 with a tweaked `Caddyfile` (`long_poll_timeout 500ms`, so vitest's 5s default doesn't trip on long-poll tests), runs the conformance suite via vitest's programmatic API, and tears down on exit. Requires Node ≥ 18 and Docker.

## Layout

```
Caddyfile         runtime config baked into the image
Dockerfile        ARGs only — no defaults; Makefile is the entry point
Makefile          includes versions.env, drives docker / npm / vitest
versions.env      single source of truth for upstream version pins
tests/
  package.json    pins the conformance suite version
  Caddyfile.test  short long-poll timeout for the test container
  conformance.test.mjs  programmatic harness (matches upstream pattern)
```

## License

MIT — see [`LICENSE`](./LICENSE). Matches the [upstream](https://github.com/durable-streams/durable-streams) `LICENSE` file.
