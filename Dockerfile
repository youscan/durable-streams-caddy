# syntax=docker/dockerfile:1.9
# check=skip=InvalidDefaultArgInFrom

# Version pins live in versions.env (consumed by the Makefile and GHA). This
# Dockerfile is not meant to be invoked directly — use `make build` or pass
# every --build-arg yourself.
# The lint check above is skipped because we intentionally have no defaults —
# the Makefile is the single source of truth.
#
# Note on DS_REF: upstream tags the plugin as `caddy-vX.Y.Z`, which is not a
# valid Go module semver tag for a subdirectory module. xcaddy/Go resolve it
# as a git ref and produce a pseudo-version, which is fine for a reproducible
# build.

ARG CADDY_VERSION

FROM golang:1.26.2 AS builder

ARG DS_REF
ARG CADDY_VERSION
ARG XCADDY_VERSION

RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@${XCADDY_VERSION}

ENV CGO_ENABLED=0
RUN xcaddy build v${CADDY_VERSION} \
    --with github.com/durable-streams/durable-streams/packages/caddy-plugin@${DS_REF} \
    --output /out/caddy

FROM caddy:${CADDY_VERSION}-alpine

COPY --from=builder /out/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile

EXPOSE 4437
VOLUME ["/data"]

# Sanity check: fail the build if the plugin didn't end up in the binary.
RUN caddy list-modules | grep -q '^http.handlers.durable_streams$'
