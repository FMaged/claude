---
name: docker-review
description: Use when reviewing a Dockerfile, a compose file, or a container setup (e.g. "review my Dockerfile", "check this docker-compose", "why is this image so big?", "is this container secure?"). Reports what runs as root, what leaks into a layer, and what will not stop cleanly.
---

# Docker Review

Review Dockerfiles, `compose.yaml`, `.dockerignore`, and entrypoint scripts. Report problems. Do not rewrite unless asked.

## 1. Secrets and layers

- A secret in `ENV`, `ARG`, or a `RUN` command. Every layer is kept, so deleting the file in a later layer does not remove it. Use a build secret mount or inject it at run time.
- `COPY . .` with no `.dockerignore`. It drags in `.git`, local env files, and build output.
- A credential file copied in to be used during build and deleted after. Still in the image.

## 2. Running as root

- No `USER`. The process runs as root, and with a bind mount it writes root-owned files on the host.
- The user created but `USER` set before the steps that need root, or never set at all.
- Files copied in owned by root and the app needing to write them (`COPY --chown=`).

## 3. Base image and size

- A floating tag (`latest`, or a bare major) instead of a specific version, ideally with a digest.
- No multi-stage build where a compiler or dev dependency ends up in the runtime image.
- `apt-get update` in a separate `RUN` from `install`. The update gets cached and you install from a stale index. One `RUN`, with `--no-install-recommends` and `rm -rf /var/lib/apt/lists/*` at the end.
- `ADD` where `COPY` would do. `ADD` unpacks archives and fetches URLs, usually by accident.
- Layer order: dependency manifests copied and installed before the source, so a code change does not reinstall everything.

## 4. Process behaviour

- `CMD` or `ENTRYPOINT` in shell form (a plain string). The process gets PID 1 under `/bin/sh -c` and never receives SIGTERM, so stops take the full ten seconds and then get killed. Use the exec form (a JSON array).
- A process that spawns children and needs an init to reap them (`--init` or tini).
- An entrypoint script that does not `exec` the final command.
- No `HEALTHCHECK`, or one that only checks the port is open rather than the app answering.
- `WORKDIR` absolute and set before relative paths are used.

## 5. Compose

- `privileged: true`, or added capabilities, without a stated reason. Prefer `cap_drop: [ALL]` and adding back only what is needed.
- No `read_only: true` with `tmpfs` for the paths that must be written, where the app allows it.
- No memory or CPU limit, so one container can take the host down.
- A port published as `8080:8080` when it only needs to be reachable inside the network, or bound to all interfaces when `127.0.0.1:8080:8080` would do.
- Secrets passed as environment variables rather than files. Env vars show up in `inspect` and in child processes.
- `depends_on` without `condition: service_healthy`. It waits for started, not for ready.
- Data in an anonymous volume or in the container, so it goes on the next recreate.
- No `restart` policy on anything meant to stay up.

## Commands

```
hadolint Dockerfile
docker build -t review:test .
docker image history review:test       # see what each layer added
docker run --rm review:test id         # confirm it is not root
docker compose config                  # the merged, resolved file
```

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what it causes at run time>
Fix: <the change, one line>
```

Separate "this is a security hole" from "this image is bigger than it needs to be". Both are worth saying, but not at the same volume.
