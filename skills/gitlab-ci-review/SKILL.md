---
name: gitlab-ci-review
description: Use when reviewing GitLab CI — an app's .gitlab-ci.yml, a template or hidden job in the ci-templates repo, or a merge request that changes the pipeline (e.g. "review my .gitlab-ci.yml", "check this CI template before I tag it", "is this prod deploy job safe?", "does this pipeline rebuild for production?", "could this job leak a secret?"). Reports what ships untested code, who can deploy to production, what runs on the wrong runner, and what leaks a secret, with the file and line. Not for GitHub Actions.
---

# GitLab CI Review

Review `.gitlab-ci.yml`, the `jobs/` and `templates/` files of the `ci-templates` repo,
and anything they include. Report problems. Do not rewrite unless the user asks.

A pipeline fails quietly. A prod deploy that rebuilt, a job that ran on whatever runner
was free, a test that could not fail, and a secret in a job log all look green until they
hurt. What matters most: what was tested is what ships, only the right people can deploy
to production, and no secret reaches a log or the wrong job. The writing rules are in the
`gitlab-ci` skill. The Dockerfile is `docker-review`; scripts too long to inline are
`powershell-review`, or shellcheck for Bash.

## 0. Review the merged job, not the file

GitLab merges `include`, `extends`, `default`, and `!reference` before it runs a job, so
a key missing from a job's own block may come from somewhere else.

- Resolve each job before you flag what it lacks. `tags`, `image`, `rules`, and
  `before_script` may come from a hidden job it extends or from `default:`.
  `inherit: default: false` turns `default:` off for that job.
- `extends` merges hashes deeply but **replaces lists**. A job that extends two parents
  keeps only the last parent's `tags`, `rules`, `script`, and `before_script`. Check that
  the list a job ends up with is the one that was meant.
- In an app repo whose template lives in a project you cannot read, review what is there
  and say which checks need the template (tags, images, prod rules). Mark those
  unconfirmed.
- In `ci-templates`, review each file in `templates/` as an app gets it, hidden jobs
  included. The schema check skips hidden jobs, and most deploy jobs are hidden.
- Some of what matters is in the project settings, not in YAML (section 11).

## 1. Secrets

- A secret written in the YAML: a password, token, or key in `variables:` or in a
  script. Anyone who can read the repo has it, and it is never masked.
- A secret that reaches the log: `echo` of a secret to check it, `set -x`,
  `CI_DEBUG_TRACE` or `CI_DEBUG_SERVICES` in a job that has secrets (debug output can show
  masked values), `env`, `printenv`, `Get-ChildItem env:`, a `cat` of a File variable, or
  a tool run with a verbose flag that prints its request headers.
- **Masking hides only the exact string.** A secret that is base64-encoded, URL-encoded,
  escaped inside JSON, or cut into parts is printed in clear text.
- A secret in an artifact: `.env`, `~/.ssh`, a kubeconfig, `*.tfstate`, a Terraform plan,
  or the whole checkout (`paths: [.]`). Anyone with read access to the project can
  download it. A plan needs `access: maintainer` (GitLab 18.4) and a short `expire_in`.
- A secret passed as `docker build --build-arg`. It stays in the image history.
- A personal access token in a CI variable, where `CI_JOB_TOKEN` or a deploy token with
  one scope would do.
- **The variable's flags** are in Settings > CI/CD > Variables, not in the repo. Every
  secret is masked and hidden, protected, scoped to its environment, and has "Expand
  variable reference" off. An unprotected secret reaches every branch: any developer can
  push a branch whose job prints it base64-encoded. Name the check (Commands) and mark
  the finding unconfirmed until you see the list.

## 2. Who can deploy to production

Find every job whose environment is production, or that deploys, applies, or pushes to
something real, and check:

- **Its rules limit it to the default branch:**
  `if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`. A prod job with no `rules`, with a rule
  that matches any branch, a merge request, or a tag, or with a catch-all `- when: manual`
  at the end, puts a deploy button on pipelines for code nobody merged. Anyone who may
  merge to a branch may run its manual jobs; on an unprotected branch that is every
  developer. Blocker.
- **It is manual:** `when: manual` inside the rule. A prod job that runs on its own
  deploys every merge to `main` with nobody deciding. Blocker.
- **The default branch is protected,** and the prod credentials are protected and scoped
  to `production`. Both are settings (section 11). Without them, the rules above only look
  like protection.
- **It waits for staging:** `needs: [<build>, deploy-staging]`. A prod job that does not
  need the staging deploy can run before staging, or after it failed.
- **`resource_group`** per environment, shared by every job that changes it (deploy,
  `terraform apply`, Ansible). Without it, two pipelines deploy at once and the hosts end
  up with a mix of versions.
- **`environment:` with a `name`.** Without it there is no deployment record and no
  rollback button. Environment-scoped variables reach only a job whose `environment:name`
  matches the scope exactly: `prod` against `production` leaves them empty (section 4).
- A `when: manual` rule without `allow_failure: true` shows every pipeline whose commit
  was not promoted as blocked. Nit, unless something waits on that status.

## 3. What ships is not what was tested

- **A deploy job that builds:** `dotnet publish`, `npm run build`, `ng build`,
  `docker build`, `mvn package`, or `go build` in a deploy job, or in a job only the prod
  path has. Staging and prod deploy the build job's artifact through `needs`, or the same
  image digest. A rebuild picks up new package versions, a new base image, or another
  commit. Blocker for prod, should fix for staging.
- **A deploy that does not wait for the tests.** `needs` waits only for the jobs it lists,
  not for earlier stages. `needs: [build]` deploys while the tests run, and deploys even
  when they fail. The deploy lists the test jobs too. Blocker.
- **A build per environment:** a `parallel: matrix:` over environments on the build job,
  `--configuration staging`, or an environment name baked into the build. Then no single
  artifact passes through both environments. Configuration is read at deploy time or at
  start.
- **A prod pipeline from a tag** (`if: $CI_COMMIT_TAG`) that builds again. Prod is the
  button on the `main` pipeline that already deployed to staging.
- **An image deployed by a tag that moves:** `:latest`, `:main`, `:$CI_COMMIT_REF_SLUG`,
  or a version tag pushed more than once. Deploy by digest, or at least by
  `$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA`. Re-tagging the same digest to promote is fine.
- **The cache used as the hand-off.** A deploy that takes its files from `cache:` can get
  another branch's build, or nothing. Build output goes from job to job as an artifact.
- **An artifact from somewhere else:** `needs:project`, or an API download of a ref's
  latest artifact. That is whatever passed last on that branch, not this commit's build.
- `needs: [{job: build, artifacts: false}]` or `dependencies: []` on a deploy: it gets no
  artifact. `GIT_STRATEGY: none` on a deploy can leave files from an earlier pipeline in
  the folder it ships; `empty` cannot.

## 4. Deploys that pass without deploying

- A loop over a host list with no check that the list is set. A variable scoped to
  another environment name is simply missing, the loop deploys to no host, and the job
  passes. Every deploy job stops on an empty host list or app name (`${VAR:?message}` in
  sh, `throw` in pwsh).
- No health check after the deploy, or one that cannot fail: `curl` without `--fail`
  (it exits 0 on a 500), or without retries, so it fails during the restart or passes
  against the old process.
- `allow_failure: true` on a deploy job outside the manual rule, `|| true` after the
  deploy command, or `-ErrorAction SilentlyContinue` on it. A failed deploy leaves the
  pipeline green.
- `retry:` on a deploy without `when:` limited to `runner_system_failure` and
  `stuck_or_timeout_failure`. A deploy that failed halfway runs again over a host that is
  half changed.
- `interruptible: true` on a deploy job. With `auto_cancel`, a new push cancels the
  deploy halfway. Only build and test jobs are interruptible.
- A `trigger:` job without `strategy: depend`: the parent pipeline is green while the
  downstream deploy fails.

## 5. Tests that cannot stop the pipeline

- `allow_failure: true` on a test, lint, or scan job. A failure shows as a warning and the
  deploy goes on. `allow_failure: exit_codes:` is fine for a code the tool documents as
  "warnings only", with a comment that says so.
- `|| true`, `|| echo`, `set +e`, or a `catch` that does not throw again, around the test
  command.
- **On the `windows` runner (pwsh),** a multi-line script entry is checked only at its
  end. A native command that fails in the middle (`dotnet test`, `msdeploy`) does not stop
  it unless `$LASTEXITCODE` is checked right after it.
- A test job that its rules leave out of merge request pipelines, or that
  `rules:changes` skips for files it depends on. The merge request merges untested.
- A test job with `when: manual`. Nobody runs it.
- Test reports without `artifacts:when: always`. A failed run uploads no report, so the
  merge request shows no failed tests.

## 6. Runners

- **A job without `tags`** once `extends` and `default` are resolved. It runs on any runner
  that takes untagged jobs, which may be a shared runner that must never see your
  secrets, or it waits forever. Blocker for a deploy or a job with secrets; should fix
  otherwise.
- **Tags that name a runner or a host** (`runner-03`, `web01`, `hv-host1`) instead of what
  the job needs: `docker`, `windows`, or `hyperv`. The pipeline breaks when the runners
  change, and the app now knows how CI is set up.
- **A tag from a variable the app sets** (`tags: [$RUNNER_TAG]`) in a template. An app
  can then put any job on the `hyperv` runner, which is the Hyper-V host.
- Host names, IP addresses, URLs, or environment values written in an app's
  `.gitlab-ci.yml` or in a template. They are CI variables, so a moved host is a settings
  change, not a commit in every app.
- A script for another shell than the runner's: Bash on `windows` (pwsh), or pwsh on
  `docker` without a pwsh image. It fails on the first run, so it is a nit unless it sits
  behind a rule that rarely matches.

## 7. When jobs run: workflow and rules

- **Two pipelines per push.** A pipeline that has merge request pipelines (any rule or
  `workflow` that matches `merge_request_event`) needs a `workflow:rules` that drops the
  branch pipeline while a merge request is open:
  `if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS` with `when: never`. Without it, every
  push to that branch runs both, and a job in both runs twice. GitLab's
  `Workflows/MergeRequest-Pipelines.gitlab-ci.yml` and `Branch-Pipelines` templates are
  fine too.
- **`only` or `except`.** Mixed with `rules` in one pipeline they are the usual cause of
  duplicate pipelines, and together in one job they are an error. Replace with `rules`.
- A rule list that ends in a catch-all (`- when: always`, `- when: on_success`, or a rule
  with no `if`). It puts the job in every pipeline, merge requests and tags included.
- `rules:changes` on a build or test job in the default branch pipeline. It compares with
  the previous push only, so a skipped build leaves the deploy with no artifact of this
  commit, or the pipeline fails when it is created because a `needs` is missing. In
  branch pipelines without `compare_to` it is always true for a new branch and in
  scheduled, web, and API pipelines, so it saves nothing there.
- `needs` naming a job that the rules can leave out: the pipeline fails when it is
  created. Give both jobs the same rules, or `optional: true` where the job really may be
  missing.

## 8. Pinning and drift from the template

- **`include:project` without `ref`, with a branch, or with a short tag.** No `ref` means
  the default branch: a push to `ci-templates` changes every app's next pipeline, prod
  deploy included, with no merge request in the app. A short `v1.0.0` can match a branch
  of the same name, and GitLab then takes the tag whichever was meant; pin
  `ref: refs/tags/v1.0.0`.
- **`include:remote` without `integrity:`** (GitLab 17.9). Whoever controls that URL runs
  code in your jobs, with your secrets. Blocker when the URL is outside your control.
- `include:component` at `@main` or `@~latest`. Pin a version.
- **`image:` or `services:` without a full version:** no tag, `latest`, a major only
  (`node:22`, `python:3`), or `sdk:10.0`. The job changes under a pipeline that did not
  change. A digest is stronger still.
- Tools installed in the script without a version: `pip install ansible-core`,
  `npm install -g @angular/cli`, `Install-Module` without `-RequiredVersion`, or
  `curl … | sh` of an install script from a branch.
- An app that overrides a template job's `script`, `image`, or `rules` has forked the
  template and no longer gets its fixes. The fix goes in the template.
- In `ci-templates`: a renamed or new required variable, or a renamed job that apps refer
  to, released as a minor version. Apps that move to it break without warning.

## 9. Artifacts and cache

- **`artifacts:` without `expire_in`.** The instance default applies, often 30 days. A
  rollback re-runs an old deploy job, which downloads that pipeline's build artifact
  again; if it has expired, the rollback fails when it is needed. The artifact a deploy
  ships lives as long as you may roll back to it. Plans and reports get a short expiry.
- Cache `paths` outside the project folder. They are never cached, and nothing says so.
  The tool's cache must point inside it (`NUGET_PACKAGES`, `npm_config_cache`).
- A cache key that ignores the lockfile (no `key`, or a fixed one). A dependency change
  restores the old packages, and every branch shares one cache. Key it with
  `cache:key:files` on the lockfile.
- Large artifacts kept for no reason (`node_modules/`, the whole checkout). Nit.

## 10. Infrastructure jobs

The Terraform, Packer, and Ansible code the jobs run has its own reviewer agent. In the
pipeline, check:

- `terraform apply` without the saved plan from the same pipeline (`-auto-approve` with no
  plan file). It applies what nobody looked at. The apply job `needs` the plan job and
  runs `terraform apply plan.cache`.
- A plan on merge requests, or an Ansible `--check` against hosts, that works only because
  the infrastructure credentials are unprotected. Every branch can then change the hosts.
  On a merge request, Ansible gets only `ansible-lint` and `--syntax-check`.
- One `resource_group` for apply and Ansible in each environment (section 2).
- No `entrypoint: [""]` on an image whose entrypoint is the tool itself (Terraform,
  Packer). The script then runs as arguments to the tool. Nit: it fails at once.

## 11. What only the settings show

Where the YAML relies on one of these, name it for the user to check and mark the finding
unconfirmed:

- The default branch protected, and who may merge to it. In `ci-templates`, the `v*` tags
  protected too.
- Each secret: masked and hidden, protected, environment-scoped, expansion off.
- "Prevent outdated deployment jobs" on (Settings > CI/CD > General pipelines).
- Protected variables in merge request pipelines (GitLab 18.1) off.
- The project's runners: whether any takes untagged jobs, and whether the `docker`
  runner is privileged.
- On Premium: a protected `production` environment with an "Allowed to deploy" list.

## Commands

```
yamllint --strict .
check-jsonschema --builtin-schema vendor.gitlab-ci .gitlab-ci.yml
glab ci lint .gitlab-ci.yml
glab api projects/:id/variables | jq '.[] | {key, environment_scope, protected, masked, hidden, raw}'
glab api projects/:id/protected_branches | jq '.[].name'
```

`glab ci lint` checks against the instance's own GitLab version and needs a token. The
pipeline editor's "Full configuration" tab shows the merged pipeline, with includes and
`extends` resolved: the surest view for section 0. The `jq` filter drops the variable
values, so no secret is printed. Skip what yamllint and the schema report on their own
(indentation, unknown keys); say "run `yamllint` and the schema check" in one line
instead of listing them.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what it lets happen>
Fix: <the change, one line>
```

When a job inherits the problem from a template or a hidden job, give the line it comes
from and name the jobs that inherit it. A blocker ships what was not tested, lets someone
deploy to production who should not, or leaks a secret. A should-fix runs two pipelines
for one push, runs on the wrong runner, breaks a rollback, or lets the pipeline change
while its file did not (unpinned). A nit is tidiness. If the pipeline is fine, say so in
one sentence and name the two or three things you checked hardest. Do not invent
findings to fill a list. If you add a comment as part of a fix, follow the
`code-comments` skill.
