# Apache + PHP-FPM + PostgreSQL + Redis + Let's Encrypt

An Ansible project that installs and configures a complete web stack on
Debian/Ubuntu servers:

- **Apache** (via `proxy_fcgi`) + **PHP-FPM**
- **PostgreSQL** with a database and login role (created idempotently)
- **Redis** (default localhost bind)
- **Let's Encrypt** certificate via **certbot** (standalone plugin), with an
  HTTP→HTTPS 301 redirect

Made for servers managed by Ansible playbooks — one repository, one `site.yml`,
one role per component.

## Prerequisites

- An Ansible control host (tested with Ansible core 2.14) with `ansible-playbook`
  available in `PATH`.
- Debian/Ubuntu target hosts (the packages come from the distro repos — no
  third-party repos, no PPAs).
- Root privileges on the target (the playbook runs with `become: true`).
- For Let's Encrypt issuance: `domain` must be a **real, publicly-resolvable**
  hostname pointing at the target, and port 80 must be reachable from the
  internet.

## Project layout

```
apache-php-stack/
├── site.yml                 # the only playbook: plays all roles in order
├── group_vars/all.yml       # site-wide variables (edit this)
├── inventories/hosts        # example inventory (replace with yours)
├── roles/
│   ├── php-fpm/             # installs PHP-FPM + auto-detects service & socket
│   ├── apache/              # vhosts (HTTP redirect + HTTPS), docroot, modules
│   ├── letsencrypt/         # certbot install + issuance + renewal timer
│   ├── postgresql/          # install + idempotent DB/role creation
│   └── redis/               # install + enable (default localhost bind)
├── docker/                  # Docker Compose replica (Debian 13) for staging/dev
│   ├── compose.yml
│   ├── web/                 # Dockerfile (debian:trixie + apache2) + vhost + entrypoint
│   ├── site/                # site files, mounted to /var/www/html
│   └── .env.example         # copy to .env (git-ignored)
├── test-*.yml               # git-ignored syntax-check playbooks (local only)
└── docs/                    # design doc and implementation plan
```

## Configuration

Edit `group_vars/all.yml` (or pass `--extra-vars` / use a host_vars file for
per-environment values). The defaults are **placeholders** — override them for
real deployments:

| Variable             | Default              | Purpose                                                            |
|----------------------|----------------------|--------------------------------------------------------------------|
| `domain`             | `example.com`        | Public hostname the stack serves and certbot issues a cert for      |
| `letsencrypt_email`  | `admin@example.com`  | Email passed to certbot on `--agree-tos`                           |
| `letsencrypt_enabled`| `true`               | `false` skips issuance; the HTTP vhost then serves the docroot      |
| `docroot`            | `/var/www/html`      | Apache document root (owned `www-data:www-data`, mode 0755)        |
| `db_name`            | `app`                | PostgreSQL database to create                                      |
| `db_user`            | `app`                | PostgreSQL login role to create                                    |
| `db_password`        | `changeme`           | **Placeholder** — override per environment; never commit a real one |

`db_name` and `db_user` must match `^[a-zA-Z_][a-zA-Z0-9_]*$` (plain identifiers;
no quotes, spaces or special characters).

## Running

From the repository root, with your inventory configured:

```bash
ansible-playbook site.yml
```

To target a different inventory:

```bash
ansible-playbook -i inventories/hosts site.yml
```

### First issuance vs. renewal

- **First run** (Let's Encrypt enabled): certbot is installed, and if
  `/etc/letsencrypt/live/{{ domain }}/fullchain.pem` does not exist, the playbook
  briefly **stops Apache**, issues the certificate with the standalone plugin,
  then restarts Apache. Issuance failures abort the playbook loudly — check the
  DNS/port-80 reachability of `domain` if it fails.
- **Subsequent runs**: the certificate already exists, so issuance is skipped
  (idempotent). Renewals are handled by the `certbot.timer` service, which the
  playbook enables.

### Skipping Let's Encrypt

For local testing, staging, or a domain that is not yet publicly reachable:

```bash
ansible-playbook site.yml --extra-vars='{"letsencrypt_enabled": false}'
```

With Let's Encrypt disabled:

- no certificate is issued (`certbot` is still installed and enabled);
- the HTTP vhost serves the docroot instead of redirecting (no redirect loops);
- the HTTPS vhost is removed and Apache is started normally.

## Security notes

- `db_password` is a placeholder (`changeme`) and **must be overridden** for any
  real deployment. The playbook never puts it on a command line: it is supplied
  only through the `PGPASSWORD` environment variable of the create task. Use
  `--extra-vars`, an untracked `host_vars/` file, or Ansible Vault.
- Let's Encrypt requires a real, publicly-resolvable `domain` and port 80
  reachable from the internet; otherwise issuance fails and the playbook aborts.
- PostgreSQL and Redis keep the default localhost-only bindings from the distro
  packages. Do not expose them directly to the internet.
- Apache proxies PHP through a unix socket (`proxy_fcgi`), not `mod_php`.

## Verification

Syntax check (no changes):

```bash
ansible-playbook --syntax-check site.yml
```

Dry run (no real changes):

```bash
ansible-playbook site.yml --check --diff --limit localhost
```

After a real deployment, verify with:

```bash
curl -I https://<domain>/     # expect 2xx or a 3xx to the app
curl -s http://<domain>/      # expect a 301 to https://<domain>/ (when LE enabled)
```

## Docker (staging/dev)

The `docker/` directory contains a Docker Compose stack that **replicates** the
Ansible stack (Apache + PHP-FPM + PostgreSQL + Redis) on **Debian 13 (trixie)**
containers, for local staging/dev. It is not a deployment of the playbook —
the playbook still targets real Debian/Ubuntu hosts.

| Service | Image | Notes |
|---|---|---|
| `web` | `Dockerfile` (FROM `debian:trixie` + `apache2`, `a2enmod proxy_fcgi`) | Same packages the `apache` role installs (on trixie the proxy_fcgi module ships with `apache2`); HTTP-only vhost (no Let's Encrypt in Docker) |
| `php-fpm` | `php:8.4-fpm-trixie` | PHP 8.4 is the Debian 13 default; talked to over TCP 9000 (no unix socket between containers) |
| `db` | `postgres:17-trixie` | Persistent volume; credentials from `.env` |
| `redis` | `redis:8-trixie` | Default localhost-style bind; exposed only on `127.0.0.1:6379` |

**Site files mount:** `docker/site/` is mounted (read-only) to `/var/www/html`
in **both** the `web` and `php-fpm` containers. The `web` container needs the
files to serve them; `php-fpm` needs them at the same path because with TCP
FCGI it receives `SCRIPT_FILENAME=/var/www/html/...` and must open that file in
*its own* filesystem. Edit files in `docker/site/` and they are served
immediately, with no rebuild or restart (`index.php` is a `phpinfo()`
placeholder to verify the Apache → proxy_fcgi → PHP-FPM chain). To deploy your
own site, put its files in `docker/site/` (or override the mount in
`compose.yml`).

> **TCP vs unix socket:** the Ansible `apache` role uses
> `proxy:unix:/run/php/*.sock|fcgi://localhost` (same host, unix socket). The
> Docker web vhost instead uses `proxy:fcgi://php-fpm:9000` because there is no
> shared unix socket between containers — PHP-FPM is reached over TCP. The pipe
> form (`proxy:tcp://...|fcgi://localhost`) does **not** work here: Apache
> resolves the `fcgi://localhost` part, not the `proxy:tcp://` target.

```bash
cd docker
cp .env.example .env          # then set POSTGRES_PASSWORD (and DOMAIN)
docker compose up -d
curl http://localhost/        # expect phpinfo() output from PHP 8.4
```

PostgreSQL listens on `127.0.0.1:5432` and Redis on `127.0.0.1:6379` on the
host (not on the LAN).

Note: Let's Encrypt is intentionally **not** part of the Docker stack — a
`--standalone` certbot run needs a publicly reachable port 80 for the real
domain. For staging without TLS, the web container serves HTTP directly
(equivalent to the `letsencrypt_enabled: false` branch of the Ansible vhosts).

## GitHub repository

The canonical copy of this repository is
**[github.com/tgarriz1977/apache-php-stack](https://github.com/tgarriz1977/apache-php-stack)**.
Status: **live** — `main` is pushed to this URL
(`git ls-remote origin` confirms the remote HEAD). The repository is **public**
(chosen by the author), created manually rather than via the GitHub API.

## License

MIT
