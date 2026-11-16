---
name: ansible
description: 'Use when writing or changing Ansible — a playbook, a role, inventory and group_vars, or a Jinja template — that configures Windows or Linux VMs after first boot — WinRM with Kerberos, IIS with Web Deploy and the ASP.NET Core Hosting Bundle, an nginx site, a systemd unit for a Kestrel app, the Docker engine, changes that are safe to run twice, check mode, secrets from CI variables, the inventory Terraform writes, ansible-lint, and running Ansible from a CI job (e.g. "write an ansible role that installs IIS and Web Deploy", "connect ansible to our domain-joined Windows VMs over WinRM", "add an nginx site for my app with ansible", "set up a systemd service for my .NET app with ansible", "install docker on these hosts with ansible", "where do these variables go: group_vars or defaults?"). For reviewing finished Ansible, use the ansible-reviewer agent instead.'
---

# Ansible

Write it so a second run reports `changed=0` and `--check --diff` shows only real drift.
Most Ansible trouble is a task that reports changed on every run, so nobody trusts the
output any more; a secret printed in a CI log; a Windows host that refuses the
connection; or a play that ran against the wrong environment.

The hosts and their groups come from Terraform (`terraform` skill, section 6). For a
review of finished playbooks, run the `ansible-reviewer` agent (in Codex, the
`ansible-review` skill). For a PowerShell script a task has to run, `powershell`. For
comments, `code-comments`. The worked example is `evals/examples/ansible/` in the skills
repo: the IIS role from section 4.

## 0. Check what is installed

Run `ansible --version` and `ansible-galaxy collection list`, and read the project's
`requirements.yml`. Write for the versions it pins. Older examples get these wrong:

- **A condition must be a boolean** (ansible-core 2.19). `when: iis_host_sites` with a
  list fails with "Conditionals must have a boolean result". Write
  `iis_host_sites | length > 0`, `x is defined`, or `result.reboot_required`. Do not
  turn on `ALLOW_BROKEN_CONDITIONALS` to make it pass.
- No `{{ }}` in `when`, `changed_when`, or `failed_when`: they are already expressions.
- YAML output is `callback_result_format = yaml` in `ansible.cfg` (2.13). The
  `community.general.yaml` callback is deprecated and is removed in community.general 12.
- A third-party apt repository is `ansible.builtin.deb822_repository` (2.15), not
  `apt_key` and `apt_repository`.

## 1. Layout

```
ansible/
  ansible.cfg
  requirements.yml            collections, each pinned to one version
  .ansible-lint               profile: production
  inventory/
    staging/
      hosts.yml               written by Terraform, ignored by git
      group_vars/
        windows.yml           how to reach Windows hosts
        linux.yml             how to reach Linux hosts
        app.yml               what the app hosts run in staging
    prod/
      hosts.yml
      group_vars/
  playbooks/
    app.yml                   one playbook per purpose
  roles/
    iis_host/
      defaults/main.yml       every input that has a sensible default
      meta/argument_specs.yml every input, the required ones without a default
      tasks/main.yml          imports one file per concern
      handlers/main.yml
      templates/
```

- Every command names the environment: `-i inventory/staging`. `ansible.cfg` sets no
  `inventory`, so a forgotten `-i` reaches no host at all instead of a default one.
  Never `-i inventory/`, which loads every environment at once.
- Terraform puts each host in two groups: its OS and its role. Keep what each group's
  file holds apart. `windows.yml` and `linux.yml` hold only connection settings; the role
  group's file (`app.yml`) holds only what the hosts run. Groups at the same level are
  merged in alphabetical order, so a variable set in both `app.yml` and `windows.yml`
  silently takes the value from `windows.yml`.
- No `host_vars`: hosts come and go with Terraform. A value one host needs belongs in
  Terraform, as a group.
- A role does one job and is named for it (`iis_host`, `nginx_site`, `docker_engine`),
  never for a machine. Its variables start with its name (`iis_host_sites`), so two roles
  cannot collide. `vars/main.yml` only for constants a caller must not change.
- `meta/argument_specs.yml` lists every input. Ansible checks it before the role's first
  task, and a missing required input fails with the names of everything that is missing.
  Set defaults in `defaults/main.yml` only; a `default` in the spec is not applied.
- Fully qualified names for every module (`ansible.windows.win_feature`, not
  `win_feature`) and a `name` on every task that says what it does.
- `requirements.yml` pins each collection to one version, and CI installs exactly those.
  An unpinned collection changes under a playbook that did not change.

```ini
# ansible.cfg
[defaults]
# No default inventory: a run without -i inventory/<env> then reaches no host at all.
roles_path = roles
interpreter_python = auto_silent
callback_result_format = yaml
```

## 2. Safe to run twice, and `--check`

- A module before `command` or `shell`. A `command` that changes something needs
  `creates`, `removes`, or a `changed_when` that reads its output; a `command` that only
  reads gets `changed_when: false`.
- `state: present`, not `latest`: `latest` changes the host whenever a new package comes
  out. Pin a version where it matters.
- A template owns the whole file. `lineinfile` only for a file another package owns.
  Add `validate:` where the tool can check a file on its own (`sshd -t -f %s`,
  `visudo -cf %s`).
- A restart is a handler. When a later task needs the restarted service, add
  `ansible.builtin.meta: flush_handlers` before it. A reboot that later tasks depend on is
  a task right after the change (`win_reboot`, `reboot`), not a handler at the end.
- On Windows, `win_powershell` reports changed unless the script sets
  `$Ansible.Changed = $false`. It is skipped under `--check` unless the script declares
  `[CmdletBinding(SupportsShouldProcess)]` and checks `$Ansible.CheckMode`.

**Check mode** is for hosts that are already configured: `--check --diff` against one
must show only real drift. On a fresh host it stops at the first task that needs
something an earlier task would have installed. That is expected. Two things keep it
honest:

- A task that only reads, and whose result a later `when` uses, gets `check_mode: false`,
  so the condition sees the real answer.
- A download that a later task needs in order to decide (`win_package` reads an MSI's
  product code from the file) gets `check_mode: false` too, into a cache folder that
  holds nothing else.

## 3. Secrets

- Secrets reach Ansible as CI variables, read with the `env` lookup:

  ```yaml
  ansible_password: "{{ lookup('ansible.builtin.env', 'WINRM_PASSWORD', default=undef()) }}"
  ```

  `default=undef()` makes a missing variable fail with "The environment variable
  'WINRM_PASSWORD' is not set". Without it, the lookup returns an empty string, which
  fails much later as access denied.
- `no_log: true` on every task whose arguments or result contain a secret: a password
  argument, a template that renders an env file, a `uri` call with a token. It also hides
  the `--diff` of that task. Never on a whole play: it hides every error.
- Ansible Vault only for a file that must live in the repo, such as a certificate. The
  vault password comes from a CI file variable through `ANSIBLE_VAULT_PASSWORD_FILE`.
- A file with a secret on a Linux host is `mode: "0600"` and owned by root.

## 4. Windows hosts

The VMs join the domain at first boot (`terraform` skill, `references/hyperv.md`), and
Windows Server ships with a WinRM listener on HTTP port 5985. Ansible uses it with
Kerberos, which encrypts every message:

```yaml
# inventory/<env>/group_vars/windows.yml
ansible_connection: winrm
ansible_port: 5985
ansible_winrm_transport: kerberos
ansible_winrm_message_encryption: always
# user@REALM with the realm in capitals. Ansible gets the ticket itself with kinit.
ansible_user: "{{ lookup('ansible.builtin.env', 'WINRM_USER', default=undef()) }}"
ansible_password: "{{ lookup('ansible.builtin.env', 'WINRM_PASSWORD', default=undef()) }}"
# Otherwise become on Windows would try sudo to root.
ansible_become_method: runas
ansible_become_user: SYSTEM
```

- Inventory names are FQDNs. Kerberos issues tickets for names; an IP address fails.
- The machine that runs Ansible needs `pywinrm[kerberos]`, the MIT Kerberos client
  (`krb5-user` on Debian), and an `/etc/krb5.conf` that names the realm.
- `message_encryption: always` refuses to talk if the messages would go unencrypted.
  Never set `AllowUnencrypted` on a host. Port 5986 (HTTPS) needs a certificate on every
  host; where policy asks for it, keep certificate validation on with
  `ansible_winrm_ca_trust_path`, never `ansible_winrm_server_cert_validation: ignore`.
- NTLM only in a lab, in that lab's own `group_vars/windows.yml`
  (`ansible_winrm_transport: ntlm`). Never `basic`.
- **The second hop fails.** A task cannot use your ticket to reach a file share, so
  `win_package` from `\\server\share\setup.msi` gives access denied. Download from an
  internal HTTPS server with `win_get_url` and a `checksum` instead. Kerberos delegation
  (`ansible_winrm_kerberos_delegation`) needs a change in AD; avoid it.
- The WinRM session already runs as an administrator. `become: true` only on a task that
  refuses a network logon (DPAPI, some installers), never on a whole play.
- Windows paths in YAML go in single quotes, or unquoted: in double quotes `\t` and `\n`
  are escapes, so `"C:\temp"` contains a tab. `'{{ dir }}\webdeploy.msi'` is right.
- Modules: `win_feature` (its result has `reboot_required`), `win_package` (an MSI's
  product code is read from the file; an `.exe` needs `creates_path` or `product_id`, or
  it installs on every run), `win_service`, `win_regedit`, `win_file`, `win_get_url`,
  `community.windows.win_firewall_rule`. IIS is the `microsoft.iis` collection; the
  `community.windows.win_iis_*` modules are deprecated and go in community.windows 4.0.
  `win_shell` only where no module exists, and then `win_powershell` (section 2).

### An IIS host for Web Deploy

Apps reach IIS with msdeploy through the Web Management Service (WMSvc) on port 8172.
Ansible prepares the host; the deploy job sends the app. The order matters:

1. **IIS and WMSvc first**: `win_feature` with `Web-Server`, `Web-Mgmt-Service`, and
   `Web-Scripting-Tools` (the IIS modules import `WebAdministration`), then
   `win_reboot` when `reboot_required` is true.
2. **Web Deploy after WMSvc**: its IIS deployment handler installs only when the
   Management Service is already there. Without it, `msdeploy.axd` answers 404.
3. **The Hosting Bundle after IIS**: installed before IIS, it does not register the
   ASP.NET Core Module, and every app fails with HTTP 500.19. Then restart IIS.
4. **Open WMSvc**: `EnableRemoteManagement` = 1, the service on `auto` and started, and
   the firewall open on 8172 to the CI runners only. Web Deploy also installs its own
   agent service (`MsDepSvc`) on port 80; disable it.
5. **The sites**: a folder per site under `C:\inetpub` (it inherits read access for
   `IIS_IUSRS`), an application pool with No Managed Code, and the site.

```yaml
- name: Install Web Deploy
  ansible.windows.win_package:
    path: '{{ iis_host_installer_dir }}\webdeploy.msi'
    arguments: ADDLOCAL=ALL
    state: present
  register: iis_host_webdeploy_result

# Installed before IIS, the bundle would not register the ASP.NET Core Module with it.
- name: Install the ASP.NET Core Hosting Bundle
  ansible.windows.win_package:
    path: '{{ iis_host_installer_dir }}\dotnet-hosting-{{ iis_host_aspnetcore_version }}-win.exe'
    arguments: /install /quiet /norestart
    creates_path: 'C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\{{ iis_host_aspnetcore_version }}'
    state: present
  notify: Restart IIS

- name: Create each site's application pool
  microsoft.iis.web_app_pool:
    name: "{{ item.name }}"
    state: started
    attributes:
      # No Managed Code: ASP.NET Core does not load the .NET Framework.
      managedRuntimeVersion: ""
  loop: "{{ iis_host_sites }}"
  loop_control:
    label: "{{ item.name }}"

# The module compares bindings as ip:port:hostname text, and IIS stores "*" for every
# address: without ip "*" the binding never matches, so every run adds it again.
- name: Create each site
  microsoft.iis.website:
    name: "{{ item.name }}"
    physical_path: '{{ iis_host_sites_root }}\{{ item.name }}'
    application_pool: "{{ item.name }}"
    state: started
    bindings:
      set:
        - ip: "*"
          port: "{{ item.port }}"
          hostname: "{{ item.hostname | default('') }}"
  loop: "{{ iis_host_sites }}"
  loop_control:
    label: "{{ item.name }}"
```

The handler restarts `WAS` with `force_dependent_services: true`, which restarts `W3SVC`
too. `microsoft.iis.website` fails if `physical_path` does not exist yet, so create the
folder first. The `Default Web Site` holds `*:80`; remove it before a site takes port 80.

By default WMSvc accepts only Windows accounts that are local administrators. Letting a
non-administrator deploy needs IIS Manager permissions and Web Deploy delegation rules.
Decide which one the deploy account gets where the deploy job is written, and grant it
here.

## 5. Linux hosts

```yaml
# inventory/<env>/group_vars/linux.yml
# cloud-init creates this user with the CI key (the Terraform module's admin_user).
ansible_user: ansible
ansible_ssh_private_key_file: "{{ lookup('ansible.builtin.env', 'SSH_PRIVATE_KEY_FILE', default=undef()) }}"
```

- A new VM: `gather_facts: false` on the play, then in `pre_tasks`
  `ansible.builtin.wait_for_connection`, `cloud-init status --wait`
  (`changed_when: false`), and `ansible.builtin.setup` if the play needs facts. Without
  the wait, cloud-init's own apt run holds the lock when the first `apt` task starts.
- `become: true` on a play whose tasks all configure the system, otherwise on the block
  that needs it.
- A CI container starts with an empty `known_hosts`, and every rebuilt VM has new host
  keys. `ssh_args = -o StrictHostKeyChecking=accept-new` under `[ssh_connection]` trusts
  each host on first use, which means on every run. Say so in a comment.

**An nginx site.** `validate:` cannot check a site file alone, because `nginx -t` reads
the main config, which includes the file only once it is in place. So test before the
reload instead:

```yaml
# tasks
- name: Write the nginx site
  ansible.builtin.template:
    src: site.conf.j2
    dest: /etc/nginx/sites-available/{{ nginx_site_name }}.conf
    owner: root
    group: root
    mode: "0644"
  notify: Nginx config changed

- name: Enable the nginx site
  ansible.builtin.file:
    src: /etc/nginx/sites-available/{{ nginx_site_name }}.conf
    dest: /etc/nginx/sites-enabled/{{ nginx_site_name }}.conf
    state: link
  notify: Nginx config changed

# handlers: they run in this order, and a failed test stops the reload.
- name: Test the nginx config
  ansible.builtin.command: nginx -t
  changed_when: false
  listen: Nginx config changed

- name: Reload nginx
  ansible.builtin.systemd_service:
    name: nginx
    state: reloaded
  listen: Nginx config changed
```

A failed test leaves the broken file in place and nginx running the old config. The run
fails, and the next run must fix the file.

**A systemd unit for a Kestrel app.** Ansible installs the ASP.NET Core runtime and
creates the user, the folder, the env file, and the unit. The deploy job copies the build
and restarts the service. So Ansible enables the unit but does not start it: with an empty
folder it would fail and restart in a loop.

```ini
# templates/app.service.j2
[Unit]
Description={{ kestrel_app_name }}
Wants=network-online.target
After=network-online.target

[Service]
User={{ kestrel_app_name }}
WorkingDirectory={{ kestrel_app_dir }}
ExecStart=/usr/bin/dotnet {{ kestrel_app_dir }}/{{ kestrel_app_dll }}
Environment=ASPNETCORE_URLS=http://127.0.0.1:{{ kestrel_app_port }}
# Secrets, from a root-only file (mode 0600, written with no_log).
EnvironmentFile=/etc/{{ kestrel_app_name }}/{{ kestrel_app_name }}.env
Restart=always
RestartSec=5
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

Kestrel listens on loopback only; nginx in front of it is the only way in. The handler
for a changed unit uses `ansible.builtin.systemd_service` with `daemon_reload: true`.

**The Docker engine.** From Docker's own repository, for Debian or Ubuntu (it needs facts),
and update the apt cache only when the repository changed:

```yaml
- name: Add Docker's apt repository
  ansible.builtin.deb822_repository:
    name: docker
    types: deb
    uris: https://download.docker.com/linux/{{ ansible_facts['distribution'] | lower }}
    suites: "{{ ansible_facts['distribution_release'] }}"
    components: stable
    signed_by: https://download.docker.com/linux/{{ ansible_facts['distribution'] | lower }}/gpg
  register: docker_engine_repo

- name: Update the apt cache for the new repository
  ansible.builtin.apt:
    update_cache: true
  when: docker_engine_repo.changed

- name: Install the Docker engine
  ansible.builtin.apt:
    name: [docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin]
    state: present
```

Membership in the `docker` group is root on that host. Add only the deploy user, and say
so in a comment.

## 6. Running it from CI

- The job runs on the `docker` runner tag, in an image with ansible-core and ansible-lint
  at pinned versions, the collections from `requirements.yml`, `pywinrm[kerberos]`, and
  the Kerberos client with `/etc/krb5.conf`.
- The inventory comes from the Terraform apply job, as an artifact
  (`ansible/inventory/<env>/hosts.yml`).
- `export ANSIBLE_CONFIG="$PWD/ansible.cfg"`. GitLab's Docker executor checks out with a
  umask that leaves the folder world-writable, and Ansible then ignores `./ansible.cfg`
  with only a warning.
- `WINRM_USER` and `WINRM_PASSWORD` are masked, protected variables;
  `SSH_PRIVATE_KEY_FILE` is a file variable, so the environment holds its path.
- A merge request runs `--check --diff` against staging. `main` runs the playbook for
  real, staging first; prod is a manual job with `resource_group`, as for Terraform.

## Before calling it done

```
ansible-lint                                                      # from ansible/
ansible-playbook -i inventory/<env> playbooks/<name>.yml --syntax-check
ansible-playbook -i inventory/<env> playbooks/<name>.yml --check --diff
ansible-playbook -i inventory/<env> playbooks/<name>.yml          # then once more
```

The lint passes with `profile: production`. The syntax check also catches a misspelled
module or a collection missing from `requirements.yml`. The second real run must end
with `changed=0` on every host. Then run the `ansible-reviewer` agent on the change (in
Codex, the `ansible-review` skill).
