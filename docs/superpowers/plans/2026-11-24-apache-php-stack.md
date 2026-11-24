# Apache + PHP-FPM + PostgreSQL + Redis + Let's Encrypt — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Debian/Ubuntu Ansible project that installs Apache + PHP-FPM, PostgreSQL (database + role), Redis and issues an automatic Let's Encrypt certificate, with HTTP redirecting to HTTPS.

**Architecture:** One role per component (`php-fpm` → `apache` → `letsencrypt` → `postgresql` → `redis`), a `site.yml` that plays them in order, site-wide variables in `group_vars/all.yml`, `inventories/hosts` as the example inventory. Apache proxies `.php` requests to the php-fpm unix socket via `proxy_fcgi`; certbot (standalone) is issued only when the cert is missing and Apache is stopped.

**Tech Stack:** Ansible (core 2.14.18 on the control host), Debian/Ubuntu target, certbot (standalone), PostgreSQL & Redis from distro repos.

**Spec:** `docs/plans/2026-11-24-apache-php-stack-design.md`

## Global Constraints

- Target: Debian/Ubuntu only (packages from the distro repos; no external repos).
- Apache uses `proxy_fcgi` + `php-fpm` — NOT `libapache2-mod-php`.
- PostgreSQL and Redis bind to default localhost addresses.
- `domain` is a variable; an HTTPS vhost + 301 redirect only apply when `letsencrypt_enabled: true`.
- Certificate issuance is idempotent: skip if `/etc/letsencrypt/live/{{ domain }}/fullchain.pem` exists.
- Role creation in PostgreSQL is idempotent: check existence, create if missing.
- No external Ansible collections required (plain shell + apt tasks).
- `db_password` placeholder "changeme" must be overridden per environment; never commit a real password.
- All secrets stay out of task output; `.git-credentials` is never read.

## Review Focus

Failure modes the spec implies but the naive plan misses:
1. **DNS/port-80 not reachable** — certbot fails; the role must stop Apache and surface the failure loudly.
2. **PHP minor version drift** — the php-fpm socket path varies by distro; must be auto-detected, not hardcoded.
3. **Existing deployment** — the project writes vhosts only replacing Apache's default config; it must be idempotent (no destructive changes to files it doesn't own).
4. **`db_password` in logs** — never put the password on a command line; it stays in the environment of a single shell task.
5. **HTTP redirect loops** — when `letsencrypt_enabled: false` the HTTP vhost serves content and never redirects, so a bad/placeholder domain cannot trap the site.

---

### Task 1: Scaffold project + git init

**Files:**
- Create: `ansible.cfg`, `site.yml`, `group_vars/all.yml`, `inventories/hosts`, `.gitignore`
- Create + commit: `docs/plans/2026-11-24-apache-php-stack-design.md`
- Create + commit: this plan

**Interfaces:**
- Produces: project skeleton; `domain`, `docroot`, `db_name`, `db_user`, `db_password`, `letsencrypt_enabled`, `letsencrypt_email` variables.

- [ ] **Step 1:** Write `ansible.cfg` with `inventory = inventories/hosts`, `remote_user = root`, `host_key_checking = False`, `retry_files_enabled = False`.
- [ ] **Step 2:** Write `group_vars/all.yml` with the variables from the spec (with the listed defaults).
- [ ] **Step 3:** Write `site.yml` (skeleton — plays for `web` group; tasks filled in Tasks 2–6).
- [ ] **Step 4:** Write `inventories/hosts` — example with `localhost ansible_connection=local` and a `[web]` group; README explains.
- [ ] **Step 5:** Write `.gitignore` (`*.retry`, `.vault_pass`, `__pycache__/`, `.venv/`, `.DS_Store`).
- [ ] **Step 6:** `git init` in `/tmp/opencode/apache-php-stack`; commit the design doc and plan.

### Task 2: php-fpm role

**Files:**
- Create: `roles/php-fpm/tasks/main.yml`, `roles/php-fpm/handlers/main.yml`

**Interfaces:**
- Consumes: `docroot` (not required), nothing from earlier tasks.
- Produces: `php_fpm_socket` fact (e.g. `/run/php/php8.2-fpm.sock`) used by the apache role.

- [ ] **Step 1:** Install packages: `php-fpm`, `php-cli`, `php-pgsql`, `php-mbstring`, `php-xml`, `php-curl` (apt, `state: present`).
- [ ] **Step 2:** Enable + start `php{,}-fpm` — Debian/Ubuntu: service name is `php{X.Y}-fpm`; discover via `shell: systemctl list-units 'php*-fpm.service' --all` — fallback to `php-fpm`.
- [ ] **Step 3:** Detect socket: `shell: ls /run/php/*-fpm.sock`, set_fact `php_fpm_socket`; fail with a clear message if no match.
- [ ] **Step 4:** Handler `restart php-fpm`.

### Task 3: apache role

**Files:**
- Create: `roles/apache/tasks/main.yml`, `roles/apache/handlers/main.yml`, `roles/apache/templates/http-vhost.j2`, `roles/apache/templates/https-vhost.j2`

**Interfaces:**
- Consumes: `php_fpm_socket` (from php-fpm role), `docroot`, `domain`, `letsencrypt_enabled`.
- Produces: Apache running with HTTP redirect + HTTPS vhost (or HTTP-only when LE disabled).

- [ ] **Step 1:** Install packages `apache2`, `libapache2-mod-proxy`, `libapache2-mod-proxy-fcgi`; `a2enmod proxy proxy_fcgi headers rewrite`.
- [ ] **Step 2:** Disable Apache default site (`rm /etc/apache2/sites-enabled/000-default.conf` — via ansible `file: state=absent`), create `/var/www/html` with owner/group `www-data` and 755.
- [ ] **Step 3:** Write HTTP vhost template: if `letsencrypt_enabled` — 301 redirect to `https://{{ domain }}/` (path preserved via rewrite); else — serve `docroot` with index `index.php`.
- [ ] **Step 4:** Write HTTPS vhost template (only when `letsencrypt_enabled`): `SSLCertificateFile /etc/letsencrypt/live/{{ domain }}/fullchain.pem`, `SSLCertificateKeyFile /etc/letsencrypt/live/{{ domain }}/privkey.pem`, `proxy_fcgi` → `php_fpm_socket`; default index `index.php`.
- [ ] **Step 5:** Enable `sites-enabled/site.conf` symlink; disable default site.
- [ ] **Step 6:** Ensure Apache is **stopped** when `letsencrypt_enabled: true` (so certbot can bind :80); **started** otherwise. Handler: reload/restart as needed.

### Task 4: letsencrypt role

**Files:**
- Create: `roles/letsencrypt/tasks/main.yml`, `roles/letsencrypt/handlers/main.yml`

**Interfaces:**
- Consumes: `domain`, `letsencrypt_enabled`, `letsencrypt_email`, Apache (stopped).
- Produces: certificate at `/etc/letsencrypt/live/{{ domain }}/` + `certbot.timer` enabled; Apache running.

- [ ] **Step 1:** Install `certbot` + `python3-certbot-apache` (apt). Enable `certbot.timer`.
- [ ] **Step 2:** If `letsencrypt_enabled: true` AND `/etc/letsencrypt/live/{{ domain }}/fullchain.pem` does NOT exist: `certbot --standalone --non-interactive --agree-tos -m {{ letsencrypt_email }} -d {{ domain }}`. Fail loudly on non-zero exit (let the play fail).
- [ ] **Step 3:** Ensure Apache is **started**. Handler: none (restart-on-failure only).

### Task 5: postgresql role

**Files:**
- Create: `roles/postgresql/tasks/main.yml`, `roles/postgresql/handlers/main.yml`

**Interfaces:**
- Consumes: `db_name`, `db_user`, `db_password`.
- Produces: running PostgreSQL with `db_name` database + `db_user` role.

- [ ] **Step 1:** Install `postgresql` (apt); enable + start service.
- [ ] **Step 2:** Create role if missing: shell via `sudo -u postgres psql` — check `SELECT 1 FROM pg_roles WHERE rolname='$db_user'` with the password in `PGPASSWORD` env of that single shell, `CREATE ROLE {{ db_user }} LOGIN PASSWORD ...` otherwise. Do NOT interpolate the password into command arguments visible in logs; pass via env var.
- [ ] **Step 3:** Create database if missing: check `pg_database`; `createdb -O {{ db_user }} {{ db_name }}` otherwise.
- [ ] **Step 4:** Handler: none (no config changes).

### Task 6: redis role

**Files:**
- Create: `roles/redis/tasks/main.yml`, `roles/redis/handlers/main.yml`

**Interfaces:**
- Produces: running Redis (`127.0.0.1:6379`).

- [ ] **Step 1:** Install `redis-server` (apt); enable + start service.

### Task 7: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: everything from Tasks 1–6.

- [ ] **Step 1:** Document: prerequisites, project layout, how to configure `group_vars/all.yml` (domain/password), how to skip LE with `--extra-vars='{"letsencrypt_enabled": false}'` or override `domain`, how to run (`ansible-playbook site.yml`), workflow for first issuance vs. renewal, security notes (placeholder password, LE requires real domain), verification commands (`curl`), and the GitHub repo.

### Task 8: Verification pass

**Files:** none (read-only checks).

- [ ] **Step 1:** `ansible-galaxy collection list` — no collections needed (informational).
- [ ] **Step 2:** `ansible-playbook --syntax-check site.yml` — must exit 0.
- [ ] **Step 3:** `ansible-playbook --check --diff site.yml --limit localhost` — produces a diff; must not error on role resolution. **Do NOT run real installs** (`--check` only).
- [ ] **Step 4:** `git status` + `git log --oneline` — working tree clean except intended changes.

### Task 9: GitHub repository

**Files:**
- Update: `README.md` (add repo URL).

**Interfaces:**
- Produces: `github.com/tgarriz1977/apache-php-stack` (public — chosen by the author) — name/description adjustable.

- [ ] **Step 1:** Create the repo via GitHub API using the token in `~/.git-credentials` (never printed): `POST /user/repos` with `{name, description, private: true}`.
- [ ] **Step 2:** Add `remote origin`, push `main` (credential helper reads `~/.git-credentials` automatically via `git`).
- [ ] **Step 3:** Verify: `git ls-remote origin` exits 0.
- [ ] **Step 4:** `git log` — single commit per Task (design doc → plan → scaffold → roles → README → repo).

---

**Self-Review**

- Spec coverage: Apache (Task 3), PHP-FPM (Task 2), LE (Task 4), redirect (Task 3 Step 3/4), Postgres DB+role (Task 5), Redis (Task 6), variables (Task 1), README (Task 7), GitHub repo (Task 9). ✅
- Step scan: each step is one action. ✅
- Type consistency: `php_fpm_socket` used by php-fpm → apache; `domain`/`letsencrypt_enabled`/`letsencrypt_email` used by apache + letsencrypt; `db_*` used by postgresql. ✅
- Review focus: failures 1–5 have tasks: 1 (Task 4 Step 2), 2 (Task 2 Step 3), 3 (Task 3 Step 2 — default site removed only), 4 (Task 5 Step 2/3), 5 (Task 3 Step 3 vs. LE disabled). ✅
- Proportion: ~150 lines vs a ~10-file project — appropriate.
