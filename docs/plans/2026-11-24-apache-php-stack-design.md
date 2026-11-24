# Design: Apache + PHP-FPM + PostgreSQL + Redis + Let's Encrypt

**Date:** 2026-11-24
**Status:** Approved (user said "si")

## Goal

An Ansible project that provisions on Debian/Ubuntu a web stack:
Apache + PHP-FPM, PostgreSQL (database + role), Redis, with automatic
Let's Encrypt certificates and HTTP→HTTPS redirect.

## Target

- Debian / Ubuntu (default versions from the distro repos — no external
  repos). Executed locally (`become: true`) or via SSH (`remote_user`).
- No Docker, no external roles.

## Architecture

Project layout under `/tmp/opencode/apache-php-stack/`:

```
.
├── README.md
├── ansible.cfg
├── site.yml
├── inventories/hosts
├── group_vars/all.yml          # site-wide variables (domain, docroot, db_*, …)
├── docs/plans/2026-11-24-apache-php-stack-design.md   # this file
├── docs/superpowers/plans/2026-11-24-apache-php-stack.md
└── roles/
    ├── php-fpm/       # php-fpm + extensiones + servicio
    ├── apache/        # apache2 + proxy_fcgi + vhosts (HTTP + HTTPS)
    ├── letsencrypt/   # certbot standalone + timer + Apache stop/start
    ├── postgresql/    # install + create DB/role (idempotent)
    └── redis/         # redis-server install + enable
```

## Component decisions

- **PHP**: default version from the Debian/Ubuntu repos; installed with
  `php-fpm`, `php-cli`, `php-pgsql`, `php-mbstring`, `php-xml`, `php-curl`.
  Socket auto-detected (`/run/php/*-fpm.sock`) and stored in a host fact.
- **Apache**: `apache2` + `libapache2-mod-proxy` + `libapache2-mod-proxy-fcgi`.
  No `libapache2-mod-php`. HTTP vhost redirects 301 → HTTPS when Let's
  Encrypt is enabled (HTTP has no cert); when disabled, HTTP vhost serves
  the docroot instead. HTTPS vhost proxies `.php` files to the php-fpm socket.
  Default-vhost file replaced.
- **Let's Encrypt**: `certbot` via the **standalone** plugin (no vhost
  requirement). Issued only if missing (idempotent; never re-issues while a
  fullchain.pem exists). `certbot.timer` enabled for auto-renewal. Apache is
  stopped before issuance and started after. `letsencrypt_enabled` variable
  (default `true`) skips issuance for staging/local work. HTTP redirect
  only applies when certificates exist.
- **PostgreSQL**: `postgresql` from the distro; service enabled and started;
  DB and role created via `sudo -u postgres psql`, idempotently
  (check existence before creating). Listener stays at default (local).
- **Redis**: `redis-server` from the distro; service enabled and started.
  Default bind (127.0.0.1) left as shipped by the Debian/Ubuntu package.

## Variables (group_vars/all.yml)

| Variable | Default | Notes |
|---|---|---|
| `domain` | `"example.com"` | Real public DNS name the LE cert is issued for |
| `letsencrypt_enabled` | `true` | Set `false` for staging / local testing |
| `letsencrypt_email` | `"admin@example.com"` | Email passed to certbot `--agree-tos` |
| `docroot` | `/var/www/html` | Document root |
| `db_name` | `"app"` | Database name |
| `db_user` | `"app"` | Role / login user |
| `db_password` | `"changeme"` | **Placeholder — override via --extra-vars or Vault** |
| `php_fpm_socket` | auto-detected | Set in the php-fpm role |

## Security notes

- All services bind to localhost/default; no public ports for PostgreSQL or
  Redis. Apache is the only internet-facing service, via HTTP→HTTPS.
- `db_password` is a default placeholder committed to the repo. Production
  deployments MUST inject a real secret (Ansible Vault or `--extra-vars`).
- Certbot needs the domain to resolve to this machine and port 80 to be
  reachable — the playbook fails loudly if the issuance attempt fails.
- The `.git-credentials` file is never read into prompts/output; secrets stay
  in files, never in logs.

## Out of scope

- SSL termination for PostgreSQL or Redis.
- Multiple sites / vhosts per machine (one vhost per machine via `domain`).
- TLS via `ssl-cert`/self-signed (only LE when enabled).
- App-level code, application deploys, CI pipelines.
