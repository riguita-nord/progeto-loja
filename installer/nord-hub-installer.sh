#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly APP_NAME="nord-hub"
readonly SERVICE_NAME="nord-hub"
readonly DB_NAME="nordhub"
readonly DB_USER="nordhub"
readonly SYSTEM_USER="nordhub"
readonly INSTALL_ROOT="/opt/nord-hub"
readonly CONFIG_DIR="/etc/nord-hub"
readonly CONFIG_FILE="${CONFIG_DIR}/nord-hub.env"
readonly STATE_DIR="/var/lib/nord-hub"
readonly BACKUP_DIR="${STATE_DIR}/backups"
readonly LOG_DIR="/var/log/nord-hub"
readonly NGINX_SITE="/etc/nginx/sites-available/nord-hub"
readonly NGINX_ENABLED="/etc/nginx/sites-enabled/nord-hub"
readonly NGINX_DEFAULT_SITE="/etc/nginx/sites-available/default"
readonly NGINX_DEFAULT_ENABLED="/etc/nginx/sites-enabled/default"
readonly SYSTEMD_UNIT="/etc/systemd/system/nord-hub.service"
readonly EXPECTED_ORIGIN="https://github.com/riguita-nord/progeto-loja.git"
readonly SOURCE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly LOCK_FILE="/var/lock/nord-hub-installer.lock"
readonly HEALTH_ATTEMPTS=30

WORK_DIR=""
DB_SQL_TEMP=""
UPDATE_SOURCE=""
CONFIG_CREATED=0
DOMAIN="${NORDHUB_DOMAIN:-_}"
APP_PORT="${NORDHUB_PORT:-8080}"
ADMIN_EMAIL="${NORDHUB_ADMIN_EMAIL:-}"
APP_BASE_URL="${NORDHUB_BASE_URL:-}"
ORIGINAL_TARGET=""

log() { printf '[nord-hub] %s\n' "$*"; }
warn() { printf '[nord-hub] WARN: %s\n' "$*" >&2; }
fail() { printf '[nord-hub] ERROR: %s\n' "$*" >&2; exit 1; }
write_environment_value() {
    local encoded
    printf -v encoded '%q' "$2"
    printf '%s=%s\n' "$1" "${encoded}"
}

cleanup() {
    if [[ -n "${DB_SQL_TEMP}" && -f "${DB_SQL_TEMP}" ]]; then
        rm -f -- "${DB_SQL_TEMP}"
    fi
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        rm -rf -- "${WORK_DIR}"
    fi
}
trap cleanup EXIT

require_root() {
    [[ "${EUID}" -eq 0 ]] || fail "Run this command as root, for example: sudo ./installer/nord-hub-installer.sh install"
}

acquire_lock() {
    mkdir -p -- "$(dirname -- "${LOCK_FILE}")"
    exec 9>"${LOCK_FILE}"
    flock -n 9 || fail "Another Nord Hub install/update/restore operation is already running."
}

check_platform() {
    [[ -r /etc/os-release ]] || fail "Cannot identify Linux distribution: /etc/os-release is missing."
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || fail "Only Ubuntu Server 24.04 LTS and 26.04 LTS are supported."
    [[ "${VERSION_ID:-}" == "24.04" || "${VERSION_ID:-}" == "26.04" ]] \
        || fail "Detected Ubuntu ${VERSION_ID:-unknown}; supported releases are 24.04 and 26.04."
    case "$(dpkg --print-architecture)" in
        amd64|arm64) ;;
        *) fail "Unsupported Ubuntu architecture: $(dpkg --print-architecture). Supported: amd64, arm64." ;;
    esac
}

check_resources() {
    local memory_kib available_kib available_gib
    memory_kib="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
    available_kib="$(df -Pk /opt | awk 'NR == 2 {print $4}')"
    available_gib=$((available_kib / 1024 / 1024))
    (( memory_kib >= 1048576 )) || warn "Less than 1 GiB RAM detected; Java builds and runtime may be unstable."
    (( available_gib >= 2 )) || fail "At least 2 GiB free on the /opt filesystem is required."
}

check_source_origin() {
    local origin
    origin="$(git -C "${SOURCE_ROOT}" remote get-url origin 2>/dev/null)" \
        || fail "The source directory is not a Git checkout with an origin remote."
    case "${origin}" in
        "${EXPECTED_ORIGIN}"|"https://github.com/riguita-nord/progeto-loja"|git@github.com:riguita-nord/progeto-loja.git) ;;
        *) fail "Unexpected Git origin '${origin}'. Expected the Nord Hub repository." ;;
    esac
}

validate_settings() {
    [[ "${APP_PORT}" =~ ^[0-9]{1,5}$ ]] && (( APP_PORT >= 1024 && APP_PORT <= 65535 )) \
        || fail "The internal port must be a number from 1024 to 65535."
    [[ "${DOMAIN}" == "_" || "${DOMAIN}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] \
        || fail "The domain contains unsupported characters."
    if [[ -n "${ADMIN_EMAIL}" && ! "${ADMIN_EMAIL}" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
        fail "The administrator email address is not valid."
    fi
}

collect_settings() {
    # Preserve an existing administrator during repair/reinstall without
    # requiring the operator to re-enter an email on every run.
    if [[ -f "${CONFIG_FILE}" ]]; then
        [[ "$(stat -c '%a' "${CONFIG_FILE}")" == "600" ]] \
            || fail "${CONFIG_FILE} exists with unsafe permissions. Set it to mode 600 before continuing."
        local configured_admin
        configured_admin="$( (source "${CONFIG_FILE}"; printf '%s' "${ADMIN_EMAIL:-}") )"
        ADMIN_EMAIL="${ADMIN_EMAIL:-${configured_admin}}"
    fi
    if [[ -t 0 ]]; then
        local answer
        if [[ -z "${NORDHUB_DOMAIN:-}" ]]; then
            read -r -p "Domain (blank for local HTTP only): " answer
            DOMAIN="${answer:-_}"
        fi
        if [[ -z "${NORDHUB_PORT:-}" ]]; then
            read -r -p "Internal application port [${APP_PORT}]: " answer
            APP_PORT="${answer:-${APP_PORT}}"
        fi
        if [[ -z "${ADMIN_EMAIL}" ]]; then
            while [[ -z "${ADMIN_EMAIL}" ]]; do
                read -r -p "Initial administrator email (required; bootstrap token will be printed once): " ADMIN_EMAIL \
                    || fail "No administrator email provided. Set NORDHUB_ADMIN_EMAIL and retry."
                [[ -n "${ADMIN_EMAIL}" ]] || warn "Administrator email cannot be blank."
            done
        fi
    fi
    validate_settings
    [[ -n "${ADMIN_EMAIL}" ]] || fail "An initial administrator email is required. Set NORDHUB_ADMIN_EMAIL for non-interactive installation."
    if [[ "${DOMAIN}" == "_" ]]; then
        APP_BASE_URL="${NORDHUB_BASE_URL:-http://localhost}"
        warn "No domain configured. This HTTP installation is for local/private use, not safe public access."
    else
        APP_BASE_URL="${NORDHUB_BASE_URL:-http://${DOMAIN}}"
        warn "HTTP is configured. Set up HTTPS before exposing this server publicly."
    fi
}

install_packages() {
    local java_package
    apt-get update
    java_package="$(apt-cache show openjdk-21-jdk-headless 2>/dev/null | awk '/^Package:/ {print $2; exit}')"
    [[ -n "${java_package}" ]] || java_package="$(apt-cache show openjdk-21-jdk 2>/dev/null | awk '/^Package:/ {print $2; exit}')"
    [[ -n "${java_package}" ]] || fail "Java 21 is unavailable in the configured Ubuntu repositories. Configure a trusted signed Java 21 repository, then retry."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        "${java_package}" postgresql postgresql-client nginx git curl ca-certificates \
        openssl rsync tar gzip util-linux
    java -version 2>&1 | grep -q '21\.' || fail "The installed Java runtime is not Java 21."
}

ensure_system_account() {
    if ! getent group "${SYSTEM_USER}" >/dev/null; then
        groupadd --system "${SYSTEM_USER}"
    fi
    if ! id -u "${SYSTEM_USER}" >/dev/null 2>&1; then
        useradd --system --gid "${SYSTEM_USER}" --home-dir "${INSTALL_ROOT}/shared" \
            --shell /usr/sbin/nologin --no-create-home "${SYSTEM_USER}"
    fi
    install -d -o root -g root -m 0755 "${INSTALL_ROOT}" "${INSTALL_ROOT}/releases"
    install -d -o "${SYSTEM_USER}" -g "${SYSTEM_USER}" -m 0750 \
        "${INSTALL_ROOT}/shared" "${INSTALL_ROOT}/shared/storage" "${LOG_DIR}"
    install -d -o root -g "${SYSTEM_USER}" -m 0750 \
        "${CONFIG_DIR}" "${STATE_DIR}" "${BACKUP_DIR}" "${STATE_DIR}/state"
}

ensure_environment() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        [[ "$(stat -c '%a' "${CONFIG_FILE}")" == "600" ]] \
            || fail "${CONFIG_FILE} exists with unsafe permissions. Set it to mode 600 before continuing."
        # shellcheck disable=SC1090
        source "${CONFIG_FILE}"
        APP_PORT="${SERVER_PORT:-${APP_PORT}}"
        APP_BASE_URL="${APP_BASE_URL:-${NORDHUB_BASE_URL:-http://localhost}}"
        return
    fi

    local db_password bootstrap_token
    db_password="$(openssl rand -hex 32)"
    bootstrap_token="$(openssl rand -hex 32)"
    {
        write_environment_value SERVER_ADDRESS "0.0.0.0"
        write_environment_value SERVER_PORT "${APP_PORT}"
        write_environment_value DATABASE_URL "jdbc:postgresql://127.0.0.1:5432/${DB_NAME}"
        write_environment_value DATABASE_USERNAME "${DB_USER}"
        write_environment_value DATABASE_PASSWORD "${db_password}"
        write_environment_value BOOTSTRAP_TOKEN "${bootstrap_token}"
        write_environment_value ALLOWED_ORIGINS ""
        write_environment_value SESSION_COOKIE_SECURE "false"
        write_environment_value APP_BASE_URL "${APP_BASE_URL}"
        write_environment_value ADMIN_EMAIL "${ADMIN_EMAIL}"
    } >"${CONFIG_FILE}"
    chown root:"${SYSTEM_USER}" "${CONFIG_FILE}"
    chmod 0600 "${CONFIG_FILE}"
    CONFIG_CREATED=1
    printf '%s' "${bootstrap_token}" >"${STATE_DIR}/state/bootstrap-token-once"
    chown root:root "${STATE_DIR}/state/bootstrap-token-once"
    chmod 0600 "${STATE_DIR}/state/bootstrap-token-once"
}

ensure_database() {
    DB_SQL_TEMP="$(mktemp "${STATE_DIR}/state/db-setup.XXXXXX")"
    chmod 0600 "${DB_SQL_TEMP}"
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
    if runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
        [[ "${CONFIG_CREATED}" == "0" ]] \
            || fail "The PostgreSQL role already exists but its protected Nord Hub configuration is missing. Restore the existing configuration; no database credentials were changed."
        rm -f -- "${DB_SQL_TEMP}"
        DB_SQL_TEMP=""
        runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 \
            || fail "The Nord Hub database role exists but its database does not. No existing database was changed."
        runuser -u postgres -- psql -tAc "SELECT pg_get_userbyid(datdba) = '${DB_USER}' FROM pg_database WHERE datname='${DB_NAME}'" | grep -qx t \
            || fail "The existing Nord Hub database is not owned by its service role; it was left untouched."
        return
    fi
    if runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
        rm -f -- "${DB_SQL_TEMP}"
        DB_SQL_TEMP=""
        fail "The Nord Hub database name is already used by a database without its service role; it was left untouched."
    fi
    cat >"${DB_SQL_TEMP}" <<SQL
DO \$setup\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DATABASE_PASSWORD}';
    END IF;
END
\$setup\$;
SQL
    runuser -u postgres -- psql --set ON_ERROR_STOP=1 --file="${DB_SQL_TEMP}"
    rm -f -- "${DB_SQL_TEMP}"
    DB_SQL_TEMP=""
    if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
        runuser -u postgres -- createdb --owner="${DB_USER}" "${DB_NAME}"
    fi
}

make_release_from_source() {
    local source="$1" release_id="$2" release_dir="$3"
    [[ -f "${source}/backend/pom.xml" && -d "${source}/frontend/public" ]] \
        || fail "The checkout is missing backend/pom.xml or frontend/public."
    sh "${source}/backend/mvnw" --batch-mode --no-transfer-progress -f "${source}/backend/pom.xml" clean verify
    install -d -o root -g root -m 0755 "${release_dir}"
    install -d -o root -g root -m 0755 "${release_dir}/backend" "${release_dir}/frontend"
    install -o root -g "${SYSTEM_USER}" -m 0640 \
        "${source}/backend/target/nord-hub.jar" "${release_dir}/backend/nord-hub.jar"
    rsync -a --chmod=D755,F644 --delete "${source}/frontend/public/" "${release_dir}/frontend/public/"
    rsync -a --chmod=D755,F644 --delete "${source}/frontend/src/" "${release_dir}/frontend/src/"
    printf '%s\n' "${release_id}" >"${release_dir}/VERSION"
    chown root:"${SYSTEM_USER}" "${release_dir}/VERSION"
    chmod 0640 "${release_dir}/VERSION"
}

install_service() {
    if [[ -e "${SYSTEMD_UNIT}" ]]; then
        grep -Fq '# Managed by the Nord Hub installer.' "${SYSTEMD_UNIT}" \
            || fail "An unrelated systemd unit already exists at ${SYSTEMD_UNIT}; it was left untouched."
        systemctl daemon-reload
        systemctl enable "${SERVICE_NAME}.service"
        return
    fi
    cat >"${SYSTEMD_UNIT}" <<UNIT
# Managed by the Nord Hub installer. Preserve this marker and file during manual edits.
[Unit]
Description=Nord Hub modular collaboration platform
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=${SYSTEM_USER}
Group=${SYSTEM_USER}
WorkingDirectory=${INSTALL_ROOT}/current
EnvironmentFile=${CONFIG_FILE}
ExecStart=/usr/bin/java -XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError -jar ${INSTALL_ROOT}/current/backend/nord-hub.jar
Restart=on-failure
RestartSec=5
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${INSTALL_ROOT}/shared/storage ${LOG_DIR}
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNIT
    chmod 0644 "${SYSTEMD_UNIT}"
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"
}

ensure_nginx_setup_route() {
    local updated_site
    grep -Fq 'location = /setup {' "${NGINX_SITE}" && return 0

    updated_site="$(mktemp)"
    if ! awk '
        !inserted && index($0, "location = / {") {
            print "    location = /setup {"
            print "        try_files /setup.html =404;"
            print "    }"
            print ""
            inserted = 1
        }
        { print }
        END { if (!inserted) exit 1 }
    ' "${NGINX_SITE}" >"${updated_site}"; then
        rm -f -- "${updated_site}"
        return 1
    fi
    cat "${updated_site}" >"${NGINX_SITE}"
    rm -f -- "${updated_site}"
}

install_nginx() {
    local nginx_backup="" default_site_disabled=0
    if [[ -e "${NGINX_SITE}" ]]; then
        grep -Fq '# Managed by the Nord Hub installer.' "${NGINX_SITE}" \
            || fail "${NGINX_SITE} already exists and is not managed by Nord Hub; it was left untouched."
        if [[ ! -L "${NGINX_ENABLED}" ]]; then
            ln -s "${NGINX_SITE}" "${NGINX_ENABLED}"
        elif [[ "$(readlink -f "${NGINX_ENABLED}")" != "${NGINX_SITE}" ]]; then
            fail "The Nginx site enable link conflicts with Nord Hub; it was left untouched."
        fi
        nginx_backup="$(mktemp)"
        cp -a -- "${NGINX_SITE}" "${nginx_backup}"
        sed -i -E \
            -e 's/^([[:space:]]*listen[[:space:]]+80);$/\1 default_server;/' \
            -e 's/^([[:space:]]*listen[[:space:]]+\[::\]:80);$/\1 default_server;/' \
            "${NGINX_SITE}"
        if ! grep -Fq 'listen 80 default_server;' "${NGINX_SITE}"; then
            cp -a -- "${nginx_backup}" "${NGINX_SITE}"
            rm -f -- "${nginx_backup}"
            fail "Could not configure the Nord Hub site as the default HTTP server."
        fi
        if ! ensure_nginx_setup_route; then
            cp -a -- "${nginx_backup}" "${NGINX_SITE}"
            rm -f -- "${nginx_backup}"
            fail "Could not add the Nord Hub /setup route to Nginx."
        fi
    else
        cat >"${NGINX_SITE}" <<NGINX
# Managed by the Nord Hub installer. Preserve this marker and file during manual edits.
limit_req_zone \$binary_remote_addr zone=nordhub_auth:10m rate=10r/m;

    server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${DOMAIN} localhost 127.0.0.1;
    server_tokens off;

    client_max_body_size 26m;
    client_body_timeout 30s;
    root ${INSTALL_ROOT}/current/frontend/public;
    index index.html;

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header X-Frame-Options DENY always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    limit_req_status 429;
    error_page 429 = @nordhub_rate_limited;

    location @nordhub_rate_limited {
        default_type application/json;
        return 429 '{"timestamp":"\$time_iso8601","status":429,"code":"RATE_LIMITED","message":"Too many authentication requests.","fields":{}}';
    }

    location ~ ^/api/v1/auth/(login|register|bootstrap)$ {
        limit_req zone=nordhub_auth burst=5 nodelay;
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:${APP_PORT}/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
    }

    location /src/ {
        alias ${INSTALL_ROOT}/current/frontend/src/;
        expires 1h;
        add_header Cache-Control "public";
    }

    location /components/ {
        alias ${INSTALL_ROOT}/current/frontend/public/components/;
    }

    location /pages/ {
        alias ${INSTALL_ROOT}/current/frontend/public/pages/;
    }

    location /assets/ {
        alias ${INSTALL_ROOT}/current/frontend/public/assets/;
        expires 1d;
        add_header Cache-Control "public";
    }

    location = / {
        try_files /index.html =404;
    }

    location = /setup {
        try_files /setup.html =404;
    }

    location / {
        try_files \$uri \$uri/ /app.html;
    }
}
NGINX
        ln -s "${NGINX_SITE}" "${NGINX_ENABLED}"
    fi

    if [[ -L "${NGINX_DEFAULT_ENABLED}" ]] \
        && [[ "$(readlink -f "${NGINX_DEFAULT_ENABLED}")" == "${NGINX_DEFAULT_SITE}" ]]; then
        rm -- "${NGINX_DEFAULT_ENABLED}"
        default_site_disabled=1
    fi

    if ! nginx -t; then
        if [[ -n "${nginx_backup}" ]]; then
            cp -a -- "${nginx_backup}" "${NGINX_SITE}"
            rm -f -- "${nginx_backup}"
        else
            rm -f -- "${NGINX_ENABLED}" "${NGINX_SITE}"
        fi
        if (( default_site_disabled )); then
            ln -s "${NGINX_DEFAULT_SITE}" "${NGINX_DEFAULT_ENABLED}"
        fi
        fail "Generated Nginx configuration did not pass nginx -t."
    fi
    [[ -z "${nginx_backup}" ]] || rm -f -- "${nginx_backup}"
    systemctl enable nginx
    systemctl reload nginx
}

atomic_activate_release() {
    local release_dir="$1" link_tmp="${INSTALL_ROOT}/current.next"
    ln -sfn "${release_dir}" "${link_tmp}"
    mv -Tf "${link_tmp}" "${INSTALL_ROOT}/current"
}

wait_for_health() {
    local attempt
    for ((attempt = 1; attempt <= HEALTH_ATTEMPTS; attempt++)); do
        if curl --fail --silent --show-error --max-time 2 \
            "http://127.0.0.1:${APP_PORT}/actuator/health" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

verify_homepage() {
    curl --fail --silent --show-error --max-time 5 http://127.0.0.1/ \
        | grep -Fq '<title>Nord-Lab Hub</title>'
}

backup_database_and_files() {
    local backup_id="${1:-$(date -u +%Y%m%dT%H%M%SZ)}" temp
    local backup_path="${BACKUP_DIR}/nord-hub-${backup_id}.tar.gz"
    temp="$(mktemp -d "${STATE_DIR}/state/backup.XXXXXX")"
    if find "${INSTALL_ROOT}/shared/storage" -type l -print -quit | grep -q .; then
        rm -rf -- "${temp}"
        fail "Refusing to back up storage containing symlinks; move them outside shared storage first."
    fi
    if find "${INSTALL_ROOT}/shared/storage" ! -type d ! -type f -print -quit | grep -q .; then
        rm -rf -- "${temp}"
        fail "Refusing to back up special files in shared storage."
    fi
    install -d -m 0700 "${temp}/backup/storage"
    runuser -u postgres -- pg_dump --format=custom --no-owner --no-acl "${DB_NAME}" >"${temp}/backup/database.dump"
    rsync -a "${INSTALL_ROOT}/shared/storage/" "${temp}/backup/storage/"
    install -m 0600 "${CONFIG_FILE}" "${temp}/backup/nord-hub.env"
    {
        printf 'created_at=%s\n' "$(date -u +%FT%TZ)"
        printf 'release=%s\n' "$(readlink -f "${INSTALL_ROOT}/current" 2>/dev/null || printf 'unavailable')"
        printf 'database=%s\n' "${DB_NAME}"
    } >"${temp}/backup/manifest.txt"
    tar -czf "${backup_path}" -C "${temp}" backup
    chmod 0600 "${backup_path}"
    rm -rf -- "${temp}"
    log "Backup created: ${backup_path}"
}

run_install() {
    require_root
    acquire_lock
    check_platform
    check_resources
    check_source_origin
    collect_settings
    if [[ -e "${NGINX_SITE}" ]] && ! grep -q '^# Managed by the Nord Hub installer\.' "${NGINX_SITE}"; then
        fail "An existing Nginx site conflicts with Nord Hub; it was left untouched."
    fi
    if [[ -e "${SYSTEMD_UNIT}" ]] && ! grep -Fq '# Managed by the Nord Hub installer.' "${SYSTEMD_UNIT}"; then
        fail "An existing systemd unit conflicts with Nord Hub; it was left untouched."
    fi
    if [[ -L "${NGINX_ENABLED}" ]] && [[ "$(readlink -f "${NGINX_ENABLED}")" != "${NGINX_SITE}" ]]; then
        fail "The Nord Hub Nginx site name is already linked elsewhere; it was left untouched."
    fi
    install_packages
    ensure_system_account
    ensure_environment
    ensure_database
    WORK_DIR="$(mktemp -d "${STATE_DIR}/state/install.XXXXXX")"
    local commit release_id release_dir
    commit="$(git -C "${SOURCE_ROOT}" rev-parse --short HEAD)"
    release_id="$(date -u +%Y%m%dT%H%M%SZ)-${commit}"
    release_dir="${INSTALL_ROOT}/releases/${release_id}"
    make_release_from_source "${SOURCE_ROOT}" "${release_id}" "${release_dir}"
    ORIGINAL_TARGET="$(readlink -f "${INSTALL_ROOT}/current" 2>/dev/null || true)"
    atomic_activate_release "${release_dir}"
    install_service
    install_nginx
    systemctl restart "${SERVICE_NAME}.service"
    if ! wait_for_health; then
        if [[ -n "${ORIGINAL_TARGET}" ]]; then atomic_activate_release "${ORIGINAL_TARGET}"; fi
        systemctl restart "${SERVICE_NAME}.service" || true
        fail "The application failed its health check. The previous release was restored; inspect journalctl -u nord-hub."
    fi
    if ! verify_homepage; then
        if [[ -n "${ORIGINAL_TARGET}" ]]; then atomic_activate_release "${ORIGINAL_TARGET}"; fi
        systemctl restart "${SERVICE_NAME}.service" || true
        fail "The Nord Hub homepage is not being served by Nginx on HTTP port 80. The previous release was restored; inspect the Nginx configuration."
    fi
    if [[ -f "${STATE_DIR}/state/bootstrap-token-once" ]]; then
        printf '\nInitial account bootstrap token (shown once; keep it private):\n'
        cat "${STATE_DIR}/state/bootstrap-token-once"
        printf '\nOpen http://<server-LAN-IP>/setup and enter this token to create the administrator account.\n'
        rm -f -- "${STATE_DIR}/state/bootstrap-token-once"
    fi
    if [[ "${DOMAIN}" == "_" && -z "${NORDHUB_BASE_URL:-}" ]]; then
        log "Nord Hub installed and healthy (release ${release_id}). Open http://<server-LAN-IP>/ from the test network; HTTP port 80 serves the homepage."
    else
        log "Nord Hub installed and healthy at ${APP_BASE_URL} (release ${release_id})."
    fi
    if [[ "${DOMAIN}" != "_" ]]; then
        warn "HTTPS has not been enabled. Do not expose this HTTP endpoint publicly until TLS is configured."
    fi
}

select_update_source() {
    local origin branch clone_dir
    origin="$(git -C "${SOURCE_ROOT}" remote get-url origin 2>/dev/null)" || fail "Cannot read the Git origin."
    case "${origin}" in
        "${EXPECTED_ORIGIN}"|"https://github.com/riguita-nord/progeto-loja"|git@github.com:riguita-nord/progeto-loja.git) ;;
        *) fail "Refusing to update from untrusted Git origin '${origin}'." ;;
    esac
    branch="$(git -C "${SOURCE_ROOT}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
    branch="${branch:-main}"
    WORK_DIR="$(mktemp -d "${STATE_DIR}/state/update.XXXXXX")"
    clone_dir="${WORK_DIR}/source"
    git clone --depth 1 --branch "${branch}" -- "${EXPECTED_ORIGIN}" "${clone_dir}"
    [[ "$(git -C "${clone_dir}" remote get-url origin)" == "${EXPECTED_ORIGIN}" ]] \
        || fail "The cloned source origin did not match the trusted repository."
    UPDATE_SOURCE="${clone_dir}"
}

run_update() {
    require_root
    acquire_lock
    check_platform
    check_source_origin
    [[ -L "${INSTALL_ROOT}/current" ]] || fail "Nord Hub is not installed; use install first."
    ORIGINAL_TARGET="$(readlink -f "${INSTALL_ROOT}/current")"
    backup_database_and_files
    local source commit release_id release_dir
    select_update_source
    source="${UPDATE_SOURCE}"
    commit="$(git -C "${source}" rev-parse --short HEAD)"
    release_id="$(date -u +%Y%m%dT%H%M%SZ)-${commit}"
    release_dir="${INSTALL_ROOT}/releases/${release_id}"
    make_release_from_source "${source}" "${release_id}" "${release_dir}"
    atomic_activate_release "${release_dir}"
    systemctl restart "${SERVICE_NAME}.service"
    if ! wait_for_health; then
        warn "Update health check failed. Reverting application files to ${ORIGINAL_TARGET}."
        atomic_activate_release "${ORIGINAL_TARGET}"
        systemctl restart "${SERVICE_NAME}.service" || true
        fail "Application release rollback completed. Database migrations are not automatically reversed; a pre-update backup is available in ${BACKUP_DIR}."
    fi
    log "Updated successfully to ${release_id}."
}

run_status() {
    require_root
    systemctl --no-pager --full status "${SERVICE_NAME}.service" || true
    printf '\nActive release: '
    readlink -f "${INSTALL_ROOT}/current" 2>/dev/null || printf 'not installed\n'
    printf '\nHealth check: '
    if [[ -f "${CONFIG_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${CONFIG_FILE}"
        curl --fail --silent --max-time 3 "http://127.0.0.1:${SERVER_PORT:-8080}/actuator/health" || printf 'unavailable\n'
    else
        printf 'not configured\n'
    fi
}

run_doctor() {
    require_root
    local failed=0
    check_result() {
        local label="$1"
        shift
        if "$@" >/dev/null 2>&1; then
            log "OK: ${label}"
        else
            warn "FAIL: ${label}"
            failed=1
        fi
    }
    check_result "Java executable" command -v java
    if command -v java >/dev/null && java -version 2>&1 | grep -q '21\.'; then
        log "OK: Java 21 runtime"
    else
        warn "FAIL: Java 21 runtime"
        failed=1
    fi
    check_result "Nord Hub service (${SERVICE_NAME}.service)" systemctl is-active --quiet "${SERVICE_NAME}.service"
    check_result "PostgreSQL service" systemctl is-active --quiet postgresql
    check_result "Nginx service" systemctl is-active --quiet nginx
    if [[ -f "${CONFIG_FILE}" ]]; then
        [[ "$(stat -c '%a' "${CONFIG_FILE}")" == "600" ]] && log "OK: restricted environment file" \
            || { warn "FAIL: environment file permissions"; failed=1; }
        # shellcheck disable=SC1090
        source "${CONFIG_FILE}"
        check_result "Nord Hub API health on port ${SERVER_PORT:-8080}" curl --fail --silent --max-time 3 "http://127.0.0.1:${SERVER_PORT:-8080}/actuator/health"
    else
        warn "FAIL: ${CONFIG_FILE} is missing"
        failed=1
    fi
    check_result "storage directory" test -d "${INSTALL_ROOT}/shared/storage"
    check_result "backup directory" test -d "${BACKUP_DIR}"
    check_result "writable storage directory" test -w "${INSTALL_ROOT}/shared/storage"
    df -h /opt /var/lib/nord-hub
    (( failed == 0 )) || return 1
}

run_backup() {
    require_root
    acquire_lock
    [[ -f "${CONFIG_FILE}" ]] || fail "Nord Hub is not installed."
    backup_database_and_files
}

run_restore() {
    require_root
    acquire_lock
    local archive="${2:-}"
    [[ -n "${archive}" && -f "${archive}" ]] || fail "Usage: sudo $0 restore /absolute/path/to/nord-hub-backup.tar.gz"
    [[ -f "${CONFIG_FILE}" ]] || fail "Nord Hub is not installed."
    tar -tzf "${archive}" | awk '
        /^\// || /(^|\/)\.\.(\/|$)/ || ($0 != "backup/" && $0 !~ /^backup\/(database\.dump|nord-hub\.env|manifest\.txt|storage(\/.*)?)$/) { exit 1 }
    ' || fail "The archive has an invalid or unsafe file listing."
    tar -tvzf "${archive}" | awk 'substr($0, 1, 1) != "d" && substr($0, 1, 1) != "-" { exit 1 }' \
        || fail "The archive contains links or special files and cannot be restored safely."
    printf 'This replaces the current Nord Hub database and stored files. Type RESTORE to continue: '
    local confirmation
    read -r confirmation
    [[ "${confirmation}" == "RESTORE" ]] || fail "Restore cancelled."
    backup_database_and_files
    WORK_DIR="$(mktemp -d "${STATE_DIR}/state/restore.XXXXXX")"
    tar -xzf "${archive}" --no-same-owner -C "${WORK_DIR}"
    [[ -s "${WORK_DIR}/backup/database.dump" && -f "${WORK_DIR}/backup/nord-hub.env" ]] \
        || fail "The backup is missing its database dump or service configuration."
    pg_restore --list "${WORK_DIR}/backup/database.dump" >/dev/null || fail "The database dump is corrupt."
    systemctl stop "${SERVICE_NAME}.service"
    runuser -u postgres -- dropdb --if-exists "${DB_NAME}"
    runuser -u postgres -- createdb --owner="${DB_USER}" "${DB_NAME}"
    runuser -u postgres -- pg_restore --exit-on-error --no-owner --no-acl --dbname="${DB_NAME}" \
        "${WORK_DIR}/backup/database.dump"
    rsync -a --delete "${WORK_DIR}/backup/storage/" "${INSTALL_ROOT}/shared/storage/"
    if [[ -f "${WORK_DIR}/backup/nord-hub.env" ]]; then
        install -o root -g "${SYSTEM_USER}" -m 0600 "${WORK_DIR}/backup/nord-hub.env" "${CONFIG_FILE}"
    fi
    systemctl start "${SERVICE_NAME}.service"
    wait_for_health || fail "Restore completed, but health checks failed. The restored database was retained for diagnosis."
    log "Restore completed and health check passed."
}

run_uninstall() {
    require_root
    acquire_lock
    if [[ -e "${NGINX_SITE}" ]] && ! grep -Fq '# Managed by the Nord Hub installer.' "${NGINX_SITE}"; then
        fail "The Nginx site no longer carries the Nord Hub managed marker; it was left untouched."
    fi
    if [[ -e "${SYSTEMD_UNIT}" ]] && ! grep -Fq '# Managed by the Nord Hub installer.' "${SYSTEMD_UNIT}"; then
        fail "The systemd unit no longer carries the Nord Hub managed marker; it was left untouched."
    fi
    printf 'This removes Nord Hub services and application releases but preserves the database, configuration, storage and backups. Type REMOVE NORD HUB to continue: '
    local confirmation
    read -r confirmation
    [[ "${confirmation}" == "REMOVE NORD HUB" ]] || fail "Uninstall cancelled."
    systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f -- "${SYSTEMD_UNIT}" "${NGINX_ENABLED}" "${NGINX_SITE}"
    systemctl daemon-reload
    nginx -t && systemctl reload nginx || warn "Nginx configuration requires manual review."
    rm -f -- "${INSTALL_ROOT}/current"
    rm -rf -- "${INSTALL_ROOT}/releases"
    log "Application removed. Database, configuration, storage and backups were retained at their existing locations."
}

usage() {
    cat <<USAGE
Usage: sudo $0 <command> [argument]

Commands:
  install    Install or repair the Nord Hub service (idempotent)
  update     Build a trusted upstream release, back up data and activate with file rollback
  status     Show service, release and health status
  restart    Restart the application service
  stop       Stop the application service
  start      Start the application service
  logs       Follow application service logs
  backup     Create a protected database, storage, configuration and release backup
  restore    Restore an explicit backup (requires typing RESTORE)
  doctor     Check Java, services, API health and filesystem permissions
  uninstall  Remove application/releases while retaining data (requires confirmation)
USAGE
}

main() {
    local command="${1:-}"
    case "${command}" in
        install) run_install ;;
        update) run_update ;;
        status) run_status ;;
        restart) require_root; systemctl restart "${SERVICE_NAME}.service" ;;
        stop) require_root; systemctl stop "${SERVICE_NAME}.service" ;;
        start) require_root; systemctl start "${SERVICE_NAME}.service" ;;
        logs) require_root; journalctl --no-pager --unit "${SERVICE_NAME}.service" --follow ;;
        backup) run_backup ;;
        restore) run_restore "$@" ;;
        doctor) run_doctor ;;
        uninstall) run_uninstall ;;
        -h|--help|help) usage ;;
        *) usage >&2; exit 2 ;;
    esac
}

main "$@"
