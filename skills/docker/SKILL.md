---
name: docker
description: Use when writing or changing a Dockerfile or a compose file for an app that deploys as an image — multi-stage builds, pinned base images, a non-root user, HEALTHCHECK, .dockerignore, labels with the git sha, build secrets instead of build args, images in the GitLab registry as $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA deployed by digest and promoted without a rebuild, an image scan in CI, and compose on one host with restart policies, env files, named volumes, resource and log limits (e.g. "write a Dockerfile for this app", "add a compose file for the API on our Docker host", "make the container run as non-root", "why does the container take ten seconds to stop", "promote the staging image to prod without rebuilding", "add a Trivy scan to the pipeline", "the Docker logs filled the disk"). For reviewing a Dockerfile or compose file, use docker-review.
---

# Docker

Write images that are built once and run unchanged in every environment. The pipeline
builds the image on `main`, pushes it to the GitLab registry, and deploys it by digest to
staging and then prod (`gitlab-ci`, section 5); the host runs it with compose. So the
image holds the app and nothing that differs per environment. Most container trouble in
production is one of these: a secret left in a layer, a process running as root, a tag
that moved, a container that ignores SIGTERM or never says it is ready, logs that fill
the disk, or data that lived inside the container.

The app's own Dockerfiles are in `dotnet` (section 7) and `angular` (section 7); the
pipeline jobs are `gitlab-ci`; the host (the engine, the compose file, the env file) is
prepared by `ansible`. For a review of a finished Dockerfile or compose file,
`docker-review`. For comments, `code-comments`. The worked example is
`evals/examples/docker/` in the skills repo: the compose file that runs the image of
`evals/examples/dotnet/Dockerfile` on one host.

## 0. Check what is there

- `docker version` and `docker compose version`. Compose is the plugin, `docker compose`,
  not the old `docker-compose`; the file is `compose.yaml`, with no `version:` key. The
  CI build job uses `docker:29.9.3` with the matching `dind` service.
- The app's `Dockerfile` and `.dockerignore`, at the repo root.
- On a host, `/opt/<app>/`: `compose.yaml` and the app's env file from Ansible, `.env`
  from the deploy job.

## 1. The Dockerfile

```dockerfile
# Build stage: the SDK, dependencies first, then the source.
FROM <sdk image>:<full version> AS build
WORKDIR /src
COPY <dependency manifests and lock files> ./
RUN <restore in locked mode>
COPY <source> ./
RUN <build into /out>

# Runtime stage: only what runs.
FROM <runtime image>:<full version>
WORKDIR /app
COPY --from=build /out ./
USER <non-root user>
EXPOSE <port>
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
    CMD ["<client>", "<the app's health URL>"]
ENTRYPOINT ["<program>", "<args>"]
```

- **Multi-stage.** The SDK, compilers, and dev dependencies stay in the build stage. The
  runtime image gets the published output and the runtime only.
- **Pinned base images:** a full version (`aspnet:10.0.15`, `nginx-unprivileged:1.30.6-alpine`),
  never `latest`, a major, or `10.0`. A base update is then a commit that names the new
  version, tested like any other change. A digest (`@sha256:…`) after the tag pins it
  completely; Renovate can keep both current.
- **Dependencies before source.** Copy the manifests and lock files, restore, then copy
  the source, so a code change reuses the restore layer.
- **Non-root.** Use the image's own user: `USER $APP_UID` in the .NET images, `USER node` in
  the Node images, `nginx-unprivileged` for nginx. Otherwise create one with a fixed
  number (`RUN useradd --system --uid 10001 app`, then `USER 10001`). The app's files stay
  owned by root, so the process cannot change its own code; `COPY --chown` only for a path
  it must write, and a volume is better for that.
- **`HEALTHCHECK` asks the app,** not the port: `/health` for the API, `/` for a static
  site, with a client the runtime image has (curl in the .NET example, busybox `wget` in an
  Alpine image). Compose's `--wait` waits for it, and the deploy fails when the container
  turns unhealthy.
- **Exec form** for `ENTRYPOINT` and `CMD` (a JSON array). The app runs as PID 1 and gets
  SIGTERM directly; the shell form puts `/bin/sh -c` in between, and the app is killed
  after the grace period instead of stopping cleanly. An entrypoint script ends with
  `exec "$@"`.
- **`.dockerignore`** for `.git`, build output (`bin/`, `obj/`, `dist/`, `node_modules/`),
  local `.env` files, and test results. Without it `COPY . .` sends the whole folder,
  secrets included, and every edit breaks the cache.
- **Packages in one `RUN`:** `apt-get update && apt-get install --yes --no-install-recommends …
  && rm -rf /var/lib/apt/lists/*`. Only what the runtime needs.
- **`COPY`, not `ADD`.** `ADD` unpacks archives and fetches URLs, mostly by accident.
- **No environment values in the image:** no `ENV` with a URL or connection string, no
  config file per environment. Settings come at run time from the env file or a mounted
  file (section 4), so the image that passed staging is the one prod runs.

### Secrets during the build

`ARG` and `ENV` values are stored in the image: `docker history` shows them, and so does
anyone who pulls it. `--build-arg` is for values that are not secret, such as
`CI_COMMIT_SHA`. A credential the build needs, such as a private NuGet or npm feed, goes
in as a build secret, which is mounted for one `RUN` and never stored:

```dockerfile
RUN --mount=type=secret,id=nuget_config,target=/root/.nuget/NuGet/NuGet.Config \
    dotnet restore src/Orders.Api/Orders.Api.csproj --locked-mode
```

```
docker build --secret id=nuget_config,src="$NUGET_CONFIG_FILE" .
```

In CI, `NUGET_CONFIG_FILE` is a masked, protected File variable. For npm, the same with
`id=npmrc,target=/root/.npmrc`. Never copy a credential file in and delete it in a later
step: the earlier layer still holds it.

## 2. Images in the registry

- **One image per commit:** `$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA`, built once, on `main`, in
  the package stage, by `.docker-image` in `ci-templates` (`gitlab-ci`, section 5). It adds
  `--label org.opencontainers.image.revision=$CI_COMMIT_SHA`, so
  `docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'`
  on a host shows which commit runs.
- **Deploys use the digest** (`registry.example.com/group/orders@sha256:…`), which the build
  job hands on in a dotenv report as `IMAGE`. A tag can be pushed again; a digest always
  means the same bytes.
- **Promotion is the same digest.** Staging and prod deploy the same `$IMAGE`; nothing is
  rebuilt for prod, because a rebuild gets new base layers and package versions that
  nobody tested. To show in the registry what runs where, re-tag after the deploy without
  pulling anything: `docker buildx imagetools create --tag "$CI_REGISTRY_IMAGE:production" "$IMAGE"`.
  That tag is for people; no host pulls it.
- **Never `:latest`** as what a host runs, and never push the same version tag twice.
- **Rollback** re-runs an old deploy job, which deploys an old digest. The registry's cleanup
  policy keeps commit-tagged images at least as long as the pipeline artifacts (90 days).
- Hosts pull with a deploy token that has only `read_registry` (`gitlab-ci`, section 5).

## 3. Lint and scan in CI

- **hadolint** in the test stage, so a Dockerfile mistake fails the merge request:

```yaml
hadolint:
  image:
    name: hadolint/hadolint:v2.15.1-alpine
    entrypoint: [""]
  tags: [docker]
  stage: test
  needs: []
  script:
    - hadolint Dockerfile
```

- **Trivy** on the image the build job pushed, before staging gets it:

```yaml
# jobs/deploy-docker.yml in ci-templates, next to .docker-image
.container-scan:
  image:
    name: aquasec/trivy:0.76.2
    entrypoint: [""]
  tags: [docker]
  stage: package
  variables:
    TRIVY_USERNAME: $CI_REGISTRY_USER
    TRIVY_PASSWORD: $CI_REGISTRY_PASSWORD
    TRIVY_CACHE_DIR: .trivycache
  cache:
    key: trivy
    paths: [.trivycache]
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "${IMAGE:?}"
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

  The template's job `needs: [docker-image]` for `$IMAGE`, and `deploy-staging` needs the
  scan, so a high or critical finding with a fix stops the image before it deploys.
- **`--ignore-unfixed`:** a finding with no fixed version cannot be acted on, and would block
  every build. An accepted finding goes in `.trivyignore` with a comment and an end date
  (`CVE-2026-12345 exp:2027-01-31`), so it comes back for a decision.
- New advisories appear after the build. The fix is a base image update: a commit that
  bumps the pinned version, which builds, scans, and deploys like any change.

## 4. Compose on one host

```yaml
# /opt/orders/compose.yaml. Ansible writes it and orders.env; the deploy job writes .env
# with IMAGE=<the digest the pipeline built>.
name: orders

services:
  api:
    image: ${IMAGE:?IMAGE is not set}
    restart: unless-stopped
    env_file: orders.env
    ports:
      # Only nginx on this host reaches the app; a published port skips the host firewall.
      - "127.0.0.1:5000:8080"
    read_only: true
    tmpfs:
      - /tmp
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    # .NET waits up to 30 seconds for running requests; Docker's default is 10.
    stop_grace_period: 30s
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1.0"
    logging:
      driver: json-file
      options:
        max-size: 10m
        max-file: "5"

networks:
  default:
    ipam:
      config:
        # Fixed, so the app can trust this network's gateway, nginx on the host, for forwarded headers.
        - subnet: 172.30.10.0/24
```

- **`image: ${IMAGE}`, never `build:`.** The host runs what CI built and scanned. `.env` in the
  project folder holds only `IMAGE`; the deploy job overwrites it on every deploy.
- **App settings in their own env file** (`env_file: orders.env`), written by Ansible from CI
  variables, mode 0600, owned by the deploy user who runs compose. Never in `compose.yaml`
  and never in the repo. A secret in an env variable shows in `docker inspect` to anyone in
  the `docker` group, who is root on that host anyway.
- **`restart: unless-stopped`:** the container comes back after a crash and after a reboot
  (with the engine enabled), but not after someone stopped it on purpose.
- **Published ports on `127.0.0.1`.** Docker writes its own firewall rules, so a port
  published on all interfaces is reachable from the network even when the host firewall
  denies it.
- **Forwarded headers:** the container sees the host's nginx as the network's gateway
  (`172.30.10.1`), not as loopback. The app must trust that address for
  `X-Forwarded-For` and `X-Forwarded-Proto` (`dotnet`, section 3); a fixed subnet keeps it
  the same after `docker compose down`.
- **Read-only root file system** with `tmpfs` for `/tmp`, all capabilities dropped, and
  `no-new-privileges`. An app that must write gets a `tmpfs` or a named volume for that one
  path. Neither the .NET API nor nginx needs a capability.
- **Named volumes for data that must survive a new container:**

```yaml
services:
  api:
    volumes:
      - keys:/var/lib/orders/keys      # Data Protection keys, if the app uses cookies
volumes:
  keys:
```

  Never data in the container's own file system (a recreate deletes it), an anonymous
  volume (nobody knows which one it is), or a bind mount into the app's folder. A database
  does not belong on the app host; if one must, its volume needs a backup like any server.
- **Limits.** Without a memory limit one container can take the whole host down. .NET and
  Node read the limit and size their heap to it.
- **Log limits.** The `json-file` driver keeps every line forever by default, until the disk
  is full. Limit it per service as above; Ansible also sets the same default in
  `/etc/docker/daemon.json` for anything started without compose.
- **`stop_grace_period`** at least as long as the app's own shutdown timeout, or Docker kills
  it in the middle of a request.
- **More than one service:** `depends_on` with `condition: service_healthy`, so a service
  waits for the other to be ready, not only started.
- **The Angular image** (`angular`, section 7) needs no env file: compose mounts the host's
  `config.json` at `/etc/orders-web/config.json:ro` and publishes `127.0.0.1:8081:8080`.
- **A deploy restarts the container.** `docker compose up --detach --wait` replaces it and
  waits for its health check; nginx answers 502 for those seconds. Where that matters,
  run two hosts behind the load balancer: the deploy job updates them one after another.
- **Old images:** a weekly `docker image prune --all --force --filter until=720h` from a
  systemd timer that Ansible installs keeps the disk free. A rollback pulls its image
  again with the host's deploy token.

## Before calling it done

```
hadolint Dockerfile
docker build --build-arg CI_COMMIT_SHA=$(git rev-parse HEAD) --tag orders-api:local .
docker run --rm --entrypoint id orders-api:local      # not uid=0
docker image history orders-api:local                 # no secret, no SDK in the last stage
trivy image --severity HIGH,CRITICAL --ignore-unfixed orders-api:local
IMAGE=orders-api:local docker compose config          # every variable set
IMAGE=orders-api:local docker compose up --detach --wait
docker compose down
```

- The image starts, turns healthy, and stops within a second or two of `docker compose down`.
- `docker inspect` shows the revision label, and `docker history` shows no build argument
  but `CI_COMMIT_SHA`.
- Then run `docker-review` on the Dockerfile and the compose file.
