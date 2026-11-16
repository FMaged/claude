---
name: gitlab-ci
description: 'Use when writing or changing GitLab CI — a template in the central ci-templates repo, an app''s .gitlab-ci.yml that includes one, stages, rules and workflow, needs, artifacts and cache, runner tags, environments, a manual production deploy with resource_group, build once and promote the same artifact, deploy jobs for IIS with msdeploy, for Linux with systemd, or for Docker hosts from the GitLab registry, masked and protected variables, and the jobs that run Terraform, Packer, and Ansible (e.g. "write the .gitlab-ci.yml for our new .NET API", "add a manual prod deploy that reuses the staging artifact", "why does my pipeline run twice on a merge request", "add an IIS deploy job to ci-templates", "pin the template version in this repo", "where do the deploy credentials go?"). Not for GitHub Actions. For the Terraform, Packer, or Ansible code that the jobs run, use those skills; for reviewing a pipeline, use gitlab-ci-review.'
---

# GitLab CI

Write it so what was tested is what ships, and every pipeline shows what it will do
before it does it. Most pipeline trouble is one of these: a prod deploy that rebuilt
instead of promoting, a job on the wrong runner, a secret in a log, a template change
that broke every app at once, or a deploy that deployed nothing and still passed.

The jobs run code that other skills write. Terraform state and the plan/apply commands
are in the `terraform` skill (sections 7 and 8). The Packer build job is in the `packer`
skill (section 8). The Ansible job's image and inventory are in the `ansible` skill
(section 6). For scripts too long to inline, `bash` or `powershell`. For a review of
finished pipelines, the `gitlab-ci-review` skill, or the `gitlab-ci-reviewer` agent for a
check that runs unattended. For comments, `code-comments`. The worked example is `evals/examples/gitlab-ci/` in the skills repo:
the templates repo from section 1 and an app that includes it.

## 0. Check what is there

- **The GitLab version.** It is `CI_SERVER_VERSION` in any job's environment, or under
  Help > About. This skill and its example are checked against GitLab 19.5. On an older
  instance, validate in the pipeline editor (CI Lint) before merging, because it knows
  that version's keywords.
- **The tier.** Protected environments, deployment approvals, and environment-scoped
  *group* variables are Premium. On Free, prod is guarded by protected branches and
  protected, environment-scoped *project* variables (section 6).
- **The runners.** Which tags exist (`docker`, `windows`, `hyperv`), the executor and
  shell behind each one, and whether the `docker` runner is privileged (section 5,
  Docker).
- **The templates repo's tags,** and which tag each app includes.

## 1. Two repos: templates and apps

All the pipeline logic lives in one `ci-templates` project. An app includes one
template, pinned to a tag, and sets a few variables. Runner names, host names, and
environment values never appear in an app repo: they are CI variables.

```
ci-templates/
  .gitlab-ci.yml          its own pipeline: yamllint and a schema check
  .yamllint
  jobs/                   hidden jobs (.name) that templates extend; apps never include these
    base.yml              stages, workflow, .staging, .production, .ssh-deploy
    dotnet.yml            .dotnet, dotnet-test, .dotnet-publish
    deploy-iis.yml        .deploy-iis
    deploy-linux.yml      .deploy-linux
    deploy-docker.yml     .docker-image, .deploy-docker
  templates/              what an app includes: one file per app kind and deploy path
    dotnet-iis.yml
    dotnet-linux.yml
    dotnet-docker.yml
```

An app's whole `.gitlab-ci.yml`:

```yaml
include:
  - project: platform/ci-templates
    ref: refs/tags/v1.0.0
    file: /templates/dotnet-iis.yml

variables:
  APP_NAME: orders
  DOTNET_PROJECT: src/Orders.Api/Orders.Api.csproj
```

A template includes the shared jobs and wires them into concrete jobs:

```yaml
# templates/dotnet-iis.yml
# The app's .gitlab-ci.yml sets APP_NAME (the IIS site) and DOTNET_PROJECT (the .csproj to publish).
# Project variables per environment: DEPLOY_HOSTS, APP_URL, DEPLOY_USER, DEPLOY_PASSWORD.
include:
  - local: /jobs/base.yml
  - local: /jobs/dotnet.yml
  - local: /jobs/deploy-iis.yml

dotnet-build:
  extends: .dotnet-publish

deploy-staging:
  extends: [.deploy-iis, .staging]
  needs: [dotnet-build, dotnet-test]

deploy-prod:
  extends: [.deploy-iis, .production]
  needs: [dotnet-build, deploy-staging]
```

- **Pin a tag, fully qualified:** `ref: refs/tags/v1.0.0`. A short `v1.0.0` can match a
  branch and a tag, and then GitLab takes the tag, whichever you meant. Never a branch:
  a push to `ci-templates` would change every app's next pipeline with no merge request
  in the app.
- **Release by tag.** Semantic versions. Protect the `v*` tags so only maintainers
  create them, and never move or delete one. A renamed variable, a new required
  variable, or a renamed job that apps refer to is a major version. An app moves to a
  new tag in a merge request, and that merge request's pipeline is the test.
- A nested `include: local` in a template resolves in `ci-templates`, at the same ref.
  That is how templates use `jobs/`.
- **Jobs run in the app's checkout.** A script file in `ci-templates` is not there. Keep
  job scripts inline and short. Longer logic goes in an image built from `ci-templates`
  and tagged with the same version.
- The user who runs a pipeline needs at least Reporter on `ci-templates` (or the
  project is internal). Otherwise the pipeline fails with `not found or access denied`.
- The app's file is merged over the template. It may set `variables` and add a job of
  its own. An app that overrides a template job's `script` has forked the template:
  fix the template instead.
- Each template starts with a comment that lists every variable it needs. That comment
  is the template's interface.

## 2. When jobs run: workflow, rules, needs

```yaml
# jobs/base.yml
stages: [build, test, package, deploy-staging, deploy-prod]

workflow:
  auto_cancel:
    on_new_commit: interruptible
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    # A branch with an open merge request already gets the merge request pipeline.
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS
      when: never
    - if: $CI_COMMIT_BRANCH
```

- A branch runs a merge request pipeline while it has an open merge request, and a
  branch pipeline otherwise, never both. Without the middle rule, every push to such a
  branch runs two pipelines. No rule matches a tag, so a tag starts no pipeline. That
  is on purpose: prod comes from `main`, and a tag pipeline would build again.
- With `workflow: rules`, a job with no `rules` runs in every pipeline the workflow
  allows, merge requests included. Without a `workflow` block, such a job skips merge
  request pipelines. So the build and test jobs need no `rules` here.
- `rules:`, never `only`/`except`. The first rule that matches decides. If none
  matches, the job is not in the pipeline.
- A job only for `main`: `if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`.
- **`needs` waits only for the jobs it lists, not for earlier stages.** A deploy that
  needs only the build starts while the tests are still running, and deploys even if
  they fail. List the test job too: `needs: [dotnet-build, dotnet-test]`.
- `needs` that names a job the rules left out makes the whole pipeline fail when it is
  created. Give both jobs the same rules. `optional: true` only when the job really may
  be missing.
- `interruptible: true` on build and test jobs, with
  `auto_cancel: on_new_commit: interruptible`: a new push cancels the old build, never a
  deploy that is already running.
- `extends` merges hashes deeply but **replaces lists**. A job that extends two parents
  that both have `before_script` keeps only the last one. That is why `.ssh-deploy`
  below holds its image, packages, and SSH setup together.

## 3. Jobs: runners, images, artifacts, cache

```yaml
# jobs/dotnet.yml
.dotnet:
  image: mcr.microsoft.com/dotnet/sdk:10.0.404
  tags: [docker]
  interruptible: true
  variables:
    # The cache can only hold paths inside the project folder.
    NUGET_PACKAGES: $CI_PROJECT_DIR/.nuget/packages
    DOTNET_NOLOGO: "true"
    DOTNET_CLI_TELEMETRY_OPTOUT: "true"
  cache:
    key:
      prefix: nuget
      files: ["**/packages.lock.json"]
    paths: [.nuget/packages]

dotnet-test:
  extends: .dotnet
  stage: test
  needs: []
  script:
    - dotnet test --configuration Release -p:RestoreLockedMode=true
      --logger "junit;LogFilePath=$CI_PROJECT_DIR/test-results/{assembly}.xml"
  artifacts:
    when: always
    reports:
      junit: test-results/*.xml
    expire_in: 30 days

.dotnet-publish:
  extends: .dotnet
  stage: build
  script:
    - dotnet publish "${DOTNET_PROJECT:?Set DOTNET_PROJECT in .gitlab-ci.yml}"
      --configuration Release --output publish -p:RestoreLockedMode=true
  artifacts:
    paths: [publish/]
    # A rollback re-runs an old deploy job, which downloads this artifact again.
    expire_in: 90 days
```

- **`tags:` on every job**, one of `docker`, `windows`, `hyperv`. Never a runner's
  name. A job with no tags runs on any runner that takes untagged jobs, or waits
  forever if none does.
- **`image:` pinned to a full version** (`10.0.404`, `alpine:3.24.4`), never `latest`
  or a major alone. A version bump is a merge request in `ci-templates` and a new tag.
  A tool image whose entrypoint is the tool itself (Terraform, Packer) needs
  `entrypoint: [""]`.
- **`expire_in` on every artifact.** The artifact a deploy ships must live as long as
  you may want to roll back to it (section 4). Test reports get `when: always`, so
  failed tests show in the merge request.
- **Cache is a speedup, not a hand-off.** It can be missing, or it can come from
  another branch. Build output goes from job to job as an artifact, never through the
  cache. Key the cache on the lockfile with `cache:key:files`, which takes at most two
  entries by default in 19.5 (wildcards allowed). Point the tool's cache inside the
  project folder (`NUGET_PACKAGES`, `npm_config_cache`).
- `RestoreLockedMode` makes the restore fail when `packages.lock.json` no longer matches
  the project, instead of quietly resolving new versions. The test projects need the
  `JunitXml.TestLogger` package for the report.
- `${VAR:?message}` stops the job with that message when an app forgot a variable,
  instead of a less clear error later.
- **`GIT_STRATEGY: empty` on deploy jobs.** They need only artifacts. With `none`, files
  from earlier pipelines can still be in the folder.
- **On the `windows` runner (pwsh), a multi-line script entry is one script.** The
  runner checks for failure only at the end of each entry, so a native command that
  fails in the middle does not stop it. Check `$LASTEXITCODE` after each native command
  and `throw`, as `.deploy-iis` does.

## 4. Build once, promote the same artifact

One job builds what ships. Staging and prod deploy that same artifact: the build job's
artifact through `needs`, or the image digest through a dotenv report. Nothing after
the build compiles anything.

```yaml
# jobs/base.yml
.staging:
  stage: deploy-staging
  environment:
    name: staging
    url: $APP_URL
  resource_group: staging
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

.production:
  stage: deploy-prod
  environment:
    name: production
    url: $APP_URL
  resource_group: production
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual
      # A manual job in rules blocks the pipeline by default; a commit never promoted would stay blocked.
      allow_failure: true
```

- Staging deploys every merge to `main`. Prod is a button on the same pipeline, and
  `needs: [<build>, deploy-staging]` lets it run only after staging succeeded.
- `resource_group` lets one deploy per environment run at a time. A second one waits.
- **Who can press the button.** Running a manual job needs permission to merge to its
  branch, so `main` must be a protected branch. The prod credentials are protected and
  scoped to `production` (section 6), so no other branch and no other job gets them. On
  Premium, a protected environment with an "Allowed to deploy" list narrows it further.
- **Turn on two project settings** (Settings > CI/CD > General pipelines): "Prevent
  outdated deployment jobs", so an old pipeline's deploy cannot overwrite a newer one,
  and "Allow job retries for rollback deployments" (on by default).
- **Rollback** is Operate > Environments > production > Rollback on an earlier
  deployment. It re-runs that old deploy job and nothing else, so the old job's
  artifact must still exist (`expire_in`), and for Docker the old image must still be in
  the registry. Set the registry cleanup policy to keep commit-tagged images as long
  as the artifacts.
- **A missing variable deploys nothing.** A variable scoped to `prod` when the job's
  environment is `production` is simply not there. A loop over an empty `DEPLOY_HOSTS`
  then deploys to no host, and the health check passes against the old version. Every
  deploy job stops when `APP_NAME` or `DEPLOY_HOSTS` is empty.
- Every deploy ends with a health check against `$CI_ENVIRONMENT_URL/health`, with
  retries. A failed check fails the job, and the environment shows the deploy as failed.
  The apps answer `GET /health` with 200 when they are ready.

## 5. The three deploy paths

Ansible prepares each host once. The deploy job only sends the app. Each path below
lists what the host must already have.

### IIS with Web Deploy

```yaml
# jobs/deploy-iis.yml
.deploy-iis:
  tags: [windows]
  variables:
    GIT_STRATEGY: empty
  script:
    - |
      if (-not $env:APP_NAME -or -not $env:DEPLOY_HOSTS) {
        throw "APP_NAME and DEPLOY_HOSTS must be set for $env:CI_ENVIRONMENT_NAME"
      }
      $msdeploy = 'C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe'
      foreach ($server in (($env:DEPLOY_HOSTS -split '\s+') -ne '')) {
        # No value may hold a comma: msdeploy splits its settings on commas.
        $dest = "contentPath=$env:APP_NAME" +
          ",computerName=https://${server}:8172/msdeploy.axd?site=$env:APP_NAME" +
          ",userName=$env:DEPLOY_USER,password=$env:DEPLOY_PASSWORD,authType=Basic"
        # AppOffline stops the app first, so its DLLs are not locked during the copy.
        & $msdeploy -verb:sync "-source:contentPath=$PWD\publish" "-dest:$dest" -enableRule:AppOffline
        if ($LASTEXITCODE -ne 0) { throw "msdeploy to $server failed with exit code $LASTEXITCODE" }
      }
    - curl.exe --fail --silent --show-error --retry 12 --retry-delay 5 --retry-all-errors
      "$env:CI_ENVIRONMENT_URL/health"
```

- **The runner:** the `windows` tag, with the pwsh shell, Web Deploy (for
  `msdeploy.exe`), and `curl.exe` installed.
- **The host** (`ansible` skill, section 4): IIS, WMSvc, Web Deploy, and the Hosting
  Bundle, a site named after `APP_NAME`, and port 8172 open only to the runners.
- **The deploy account** is one domain account per environment. It is a local
  administrator on that environment's IIS hosts and nowhere else, because by default
  WMSvc accepts only administrators. A non-administrator would need IIS Manager
  permissions and Web Deploy delegation rules on every host; that is not set up.
- **The certificate.** WMSvc starts with a self-signed certificate, which msdeploy
  rejects. Bind a certificate from the internal CA to WMSvc on each host, and trust that
  CA on the runner. `-allowUntrusted` only in a lab, in that lab's own template.
- `sync` makes the site folder match `publish/`, so it deletes files the build does not
  have. Keep logs and uploads outside the site folder.
- Never put quotes around the values: PowerShell and msdeploy disagree about how quotes
  inside an argument are escaped. So the values may not contain commas or spaces. Host,
  site, and user names never do. Generate the password without commas.

### Linux with systemd

```yaml
# jobs/base.yml
.ssh-deploy:
  image: alpine:3.24.4
  tags: [docker]
  variables:
    GIT_STRATEGY: empty
  before_script:
    - apk add --no-cache openssh-client rsync curl
    - install -d -m 700 ~/.ssh
    - cp "$SSH_KNOWN_HOSTS" ~/.ssh/known_hosts
    - chmod 400 "$SSH_PRIVATE_KEY_FILE"
    - printf 'IdentityFile %s\nBatchMode yes\n' "$SSH_PRIVATE_KEY_FILE" > ~/.ssh/config

# jobs/deploy-linux.yml
.deploy-linux:
  extends: .ssh-deploy
  script:
    - ': "${APP_NAME:?}" "${DEPLOY_HOSTS:?DEPLOY_HOSTS is not set for $CI_ENVIRONMENT_NAME}"'
    - |
      for host in $DEPLOY_HOSTS; do
        rsync -a --delete publish/ "$DEPLOY_USER@$host:/opt/$APP_NAME/releases/$CI_COMMIT_SHA/"
        ssh "$DEPLOY_USER@$host" sh -s -- "$APP_NAME" "$CI_COMMIT_SHA" <<'EOF'
      set -eu
      app=/opt/$1
      ln -sfn "$app/releases/$2" "$app/current.new"
      # a rename is atomic, so the service never finds the link missing
      mv -T "$app/current.new" "$app/current"
      sudo -n systemctl restart "$1"
      # keep the five newest; a rollback to an older release copies it again
      ls -1dt "$app"/releases/* | tail -n +6 | xargs -r rm -rf
      EOF
      done
    - curl --fail --silent --show-error --retry 12 --retry-delay 5 --retry-all-errors "$CI_ENVIRONMENT_URL/health"
```

- **The host** (`ansible` skill, section 5): the ASP.NET Core runtime, nginx in front,
  and the unit with `WorkingDirectory` and `ExecStart` under `/opt/<app>/current`,
  enabled but not started. Plus what the deploy needs: a `deploy` user with the CI
  public key that owns `/opt/<app>/releases`, and a sudoers rule that lets it run only
  `systemctl restart <app>`.
- The heredoc's closing `EOF` must start the line after YAML removes the block's
  indent. Keep the heredoc lines at the same indent as the `for` line.
- `SSH_KNOWN_HOSTS` is a file variable with the hosts' keys, so the job refuses an
  unknown host. Update it when a VM is rebuilt. The `ansible` skill uses `accept-new`
  instead; that trusts any key on every run, because each job starts with an empty
  `known_hosts`.
- A file variable that holds a key must end with a newline. Without it, ssh fails with
  `error in libcrypto`.

### Docker from the GitLab registry

```yaml
# jobs/deploy-docker.yml
.docker-image:
  image: docker:29.9.3
  services: [docker:29.9.3-dind]
  tags: [docker]
  stage: package
  variables:
    DOCKER_TLS_CERTDIR: /certs
  script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login --username "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"
    - docker build --label "org.opencontainers.image.revision=$CI_COMMIT_SHA"
      --build-arg "CI_COMMIT_SHA=$CI_COMMIT_SHA" --tag "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA" .
    - docker push "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA"
    # Deploys pull by digest: a later push to the same tag cannot change what they get.
    - echo "IMAGE=$(docker inspect --format '{{index .RepoDigests 0}}' "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA")" > image.env
  artifacts:
    reports:
      dotenv: image.env
    expire_in: 90 days
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

.deploy-docker:
  extends: .ssh-deploy
  script:
    - ': "${APP_NAME:?}" "${IMAGE:?}" "${DEPLOY_HOSTS:?DEPLOY_HOSTS is not set for $CI_ENVIRONMENT_NAME}"'
    - |
      for host in $DEPLOY_HOSTS; do
        ssh "$DEPLOY_USER@$host" sh -s -- "$APP_NAME" "$IMAGE" <<'EOF'
      set -eu
      cd "/opt/$1"
      # compose.yaml reads ${IMAGE} from .env; Ansible owns every other file here
      printf 'IMAGE=%s\n' "$2" > .env
      docker compose pull --quiet
      docker compose up --detach --wait
      EOF
      done
    - curl --fail --silent --show-error --retry 12 --retry-delay 5 --retry-all-errors "$CI_ENVIRONMENT_URL/health"
```

- The image is built once from the repo's multi-stage `Dockerfile`, in the `package`
  stage, only on `main`. Every later job uses `$IMAGE`, the digest, from the dotenv
  report. The `docker` skill writes the Dockerfile, the image scan, and the host's compose
  file; `docker-review` checks them.
- Docker-in-Docker needs a privileged runner: `privileged = true` and
  `volumes = ["/certs/client"]` in that runner's `config.toml`. Where the `docker`
  runner may not be privileged, build with Buildah instead. Never mount the host's
  Docker socket: that hands every job the runner host.
- `CI_REGISTRY_USER` and `CI_REGISTRY_PASSWORD` are the job's own credentials. They
  expire with the job, so they are never sent to a host.
- **The host:** the Docker engine, the deploy user in the `docker` group (which is root
  on that host), and `/opt/<app>/compose.yaml` with `image: ${IMAGE}`, a healthcheck
  (`--wait` waits for it), restart policies, and the app's env file. The deploy user is
  logged in to the registry with a deploy token that has only `read_registry`, so the
  host can pull again on its own after a prune.

## 6. Variables and secrets

- **Where each one goes.** A value shared by many projects goes in a group variable. A
  value for one app goes in a project variable. A value that differs per environment is
  scoped to `staging` or `production`; scoping is free on project variables and needs
  Premium on group variables. The scope must match `environment:name` exactly.
- **Every secret:** visibility "Masked and hidden", "Protect variable" on, scoped to its
  environment, and "Expand variable reference" off. With expansion on, a `$` in a
  password is read as the start of a variable.
- A masked value must be one line, with no spaces, and at least 8 characters. A key or a
  certificate is a **File** variable: the environment variable holds the path of a file
  with the value (`SSH_PRIVATE_KEY_FILE`, `SSH_KNOWN_HOSTS`).
- **Masking is not protection.** It hides the exact string in the log, not a
  base64-encoded or URL-encoded copy, and not what `env` prints in a file. Never
  `set -x` and never `CI_DEBUG_TRACE` in a job that has a secret. Never `echo` a secret
  to check it.
- A merge request pipeline gets no protected variables. Since GitLab 18.1 a project
  setting lets it have them, but only when both branches are protected and the person
  has merge access to the target. Leave it off. A job that must run on a merge request
  without its secret gets a dummy value, as `packer validate` does.
- The job token (`CI_JOB_TOKEN`) is for the registry, the Terraform state, and the API
  of this project. Never put a personal access token in a CI variable.

## 7. Infrastructure jobs

The infra repo includes an infra template from `ci-templates` in the same way. Stages
`test`, `plan`, `apply`, `configure`, one set of jobs per environment, and prod a copy
of staging with `when: manual`:

```yaml
.terraform:
  image:
    name: hashicorp/terraform:1.17.2
    entrypoint: [""]  # the image's entrypoint is terraform itself
  tags: [docker]
  before_script:
    - cd "infra/envs/$TF_STATE_NAME"
    - terraform init -input=false -lockfile=readonly

terraform-plan-staging:
  extends: .terraform
  stage: plan
  variables:
    TF_STATE_NAME: staging
  environment:
    name: staging
    action: prepare  # gets staging's variables without recording a deployment
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  script:
    - terraform plan -input=false -out=plan.cache
  artifacts:
    paths: [infra/envs/staging/plan.cache]
    access: maintainer  # the plan holds secrets in clear text
    expire_in: 1 day

terraform-apply-staging:
  extends: .terraform
  stage: apply
  variables:
    TF_STATE_NAME: staging
  environment:
    name: staging
  resource_group: staging
  needs: [terraform-plan-staging]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  script:
    - terraform apply -input=false plan.cache
  artifacts:
    paths: [ansible/inventory/staging/hosts.yml]
    expire_in: 1 week

ansible-staging:
  image: $CI_REGISTRY/platform/ci-templates/ansible:1.0.0
  tags: [docker]
  stage: configure
  environment:
    name: staging
  resource_group: staging
  needs: [terraform-apply-staging]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  script:
    - cd ansible
    - export ANSIBLE_CONFIG="$PWD/ansible.cfg"
    - ansible-playbook -i inventory/staging playbooks/app.yml
```

- The `TF_HTTP_*` state variables are in the `terraform` skill, section 7. Put them in
  `.terraform`'s `variables`.
- The plan job writes `plan.cache` in the root module's folder. The apply job gets it at
  the same path through `needs`, and runs `init` again first, as a saved plan requires.
- One `resource_group` for apply and Ansible in an environment, so a second pipeline
  cannot change the VMs while the first one configures them.
- **No plan on merge requests here.** The Hyper-V credentials are protected, so a merge
  request pipeline from an unprotected branch has none and cannot connect. Hyper-V has
  no read-only role, so do not unprotect them to make that plan work. The merge request
  plan in the `terraform` skill (section 8) needs a provider with a read-only account.
- `artifacts:access: maintainer` (GitLab 18.4) limits who can download the plan in the
  UI and the API. It does not stop other jobs from reading it.
- The Packer build job and its `hyperv` runner are in the `packer` skill, section 8.
- The Ansible image is built in `ci-templates` with pinned ansible-core, the collections,
  `pywinrm[kerberos]`, and the Kerberos client (`ansible` skill, section 6).

## 8. The templates repo's own pipeline

```yaml
# ci-templates/.gitlab-ci.yml
lint:
  image: python:3.13.18-slim
  tags: [docker]
  script:
    - pip install --no-cache-dir --quiet yamllint==1.38.0 check-jsonschema==0.39.0
    - yamllint --strict .
    - check-jsonschema --builtin-schema vendor.gitlab-ci .gitlab-ci.yml jobs/*.yml templates/*.yml
```

The schema check does not look inside hidden jobs, and every deploy job here is hidden.
Before you tag a release, also check each template once as GitLab sees it: open a test
app's pipeline editor with the new ref, or merge each template with the skills repo's
`evals/check-gitlab-ci.py` and run the schema on the result.

## Before calling it done

```
yamllint --strict .                                        # in ci-templates
check-jsonschema --builtin-schema vendor.gitlab-ci .gitlab-ci.yml jobs/*.yml templates/*.yml
```

Then, in one app, change `ref` to the new tag in a merge request and check:

- The merge request pipeline shows build and test only. No deploy job appears.
- After the merge, the `main` pipeline deploys to staging by itself, and prod waits for
  the button. Both deploy jobs downloaded the build job's artifact; neither built.
- The prod job's log shows `[MASKED]` wherever a secret would have appeared.
- A rollback from Operate > Environments re-deploys the previous version.

Then run the `gitlab-ci-reviewer` agent on the change (in Codex, the `gitlab-ci-review`
skill).
