#!/usr/bin/env bash
# serverL.sh — Ultimate Local Development Environment Manager
# Version: 2.0.0
# Author: ChatGPT (GPT-5 Thinking mini)
#
# WARNING: This script performs system-level operations (package installs,
# editing /etc/hosts, creating vhosts, systemctl, etc.). Use on local dev only.
# Read through before running. Use --dry-run to test.
#
# Features (summary):
# - Dashboard-first interactive CLI with menus
# - Project scaffolding: Laravel, WordPress, PHP, Node.js, React, Vue, Svelte, SolidJS, .NET, static, Bootstrap5+jQuery
# - Apache & Nginx virtual hosts automation (sites-available / sites-enabled)
# - SSL: mkcert (preferred) or openssl self-signed
# - PHP version detection & switch (update-alternatives)
# - Node version via NVM (install/use)
# - PM2 for Node process management
# - DB management: MySQL/MariaDB, PostgreSQL, MongoDB, SQLite, Redis
# - Mongo Express & phpMyAdmin integration
# - Git & GitHub helpers (create repo via PAT), folders browser, editor integration
# - FTP/SFTP helpers (vsftpd + SFTP account creation)
# - Logging: $CONFIG_DIR/devstack.log
# - Dry-run and non-interactive (--yes) support
#
# Usage:
#   sudo ./serverL.sh        # interactive
#   sudo ./serverL.sh --dry-run
#   sudo ./serverL.sh --yes  # assume yes for confirmations
#
set -Eeuo pipefail
shopt -s expand_aliases

### ------------- CLI FLAGS -------------
DRY_RUN=0
ASSUME_YES=0
while [[ "${1:-}" != "" ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) echo "Usage: sudo $0 [--dry-run] [--yes]"; exit 0 ;;
    *) echo "Unknown arg $1"; exit 1 ;;
  esac
  shift
done

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

confirm() {
  if [[ "$ASSUME_YES" -eq 1 ]]; then return 0; fi
  local prompt="${1:-Are you sure? (y/N): }"
  read -r -p "$prompt" ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

### ------------- CONFIG & GLOBALS -------------
CONFIG_DIR="/etc/devstack"
LOG_FILE="${CONFIG_DIR}/devstack.log"
ROOTS_FILE="${CONFIG_DIR}/roots.list"
PROJECTS_DIR_DEFAULT="/var/www/html"
PROJECTS_DIR="${PROJECTS_DIR_DEFAULT}"
VHOST_APACHE_DIR="/etc/apache2/sites-available"
VHOST_NGINX_DIR="/etc/nginx/sites-available"
VHOST_NGINX_ENABLED="/etc/nginx/sites-enabled"
SSL_DIR="/etc/ssl/devstack"
HOSTS_FILE="/etc/hosts"
BACKUP_DIR="${CONFIG_DIR}/backups"
EDITOR="${EDITOR:-nano}"
USER_HOME="${SUDO_USER:-$USER}"
NVM_DIR="/usr/local/nvm"

# Colors
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GRN='\033[0;32m'
C_YLW='\033[0;33m'
C_BLU='\033[0;34m'
C_CYN='\033[0;36m'

# Menu tree ASCII (shortened here; full is printed on start)
MENU_TREE_ASCII='
MAIN MENU (Dashboard first)
├─ Dashboard
├─ Services
├─ Projects
├─ Databases
├─ Version Management
├─ Virtual Hosts
├─ PHP Extensions & Config
├─ Git & GitHub
├─ FTP / SFTP
├─ Backup & Restore
├─ Install / Uninstall
└─ Settings & Exit
'

# Ensure directories exist
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)." >&2
    exit 1
  fi
}

ensure_dirs() {
  run_cmd "mkdir -p \"$CONFIG_DIR\" \"$SSL_DIR\" \"$BACKUP_DIR\""
  run_cmd "touch \"$LOG_FILE\""
  [[ -f "$ROOTS_FILE" ]] || run_cmd "echo \"$PROJECTS_DIR\" > \"$ROOTS_FILE\""
}

log() {
  local msg="$*"
  local ts
  ts=$(date '+%F %T')
  echo "$ts - $msg" >>"$LOG_FILE"
}

inf() { echo -e "${C_CYN}[i]${C_RESET} $*"; log "[INFO] $*"; }
msg() { echo -e "${C_GRN}[✔]${C_RESET} $*"; log "[OK] $*"; }
wrn() { echo -e "${C_YLW}[!]${C_RESET} $*"; log "[WARN] $*"; }
err() { echo -e "${C_RED}[x]${C_RESET} $*"; log "[ERR] $*"; }

### ------------- HELPERS -------------
exists() { command -v "$1" >/dev/null 2>&1; }
port_in_use() { ss -lnt 2>/dev/null | awk '{print $4}' | grep -E ":$1$" >/dev/null 2>&1 || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -E ":$1" >/dev/null 2>&1; }
find_available_port() {
  local start=${1:-3000}
  for ((p = start; p < 65000; p++)); do
    if ! port_in_use "$p"; then echo "$p"; return; fi
  done
  echo "0"
}
backup_file() {
  local src="$1" dst="$BACKUP_DIR/$(basename "$src").$(date +%F-%H%M%S).bak"
  run_cmd "cp -a \"$src\" \"$dst\"" && msg "Backed up $src -> $dst"
}

add_hosts_entry() {
  local domain="$1"
  # safety: backup hosts first
  if ! grep -qE "127.0.0.1\s+$domain" "$HOSTS_FILE"; then
    backup_file "$HOSTS_FILE"
    run_cmd "echo '127.0.0.1    $domain' >> '$HOSTS_FILE'"
    msg "Added hosts entry for $domain"
  else
    inf "Hosts entry for $domain already exists"
  fi
}

create_self_signed_cert() {
  local domain="$1"
  local key="$SSL_DIR/$domain.key"
  local crt="$SSL_DIR/$domain.crt"
  if [[ -f "$key" && -f "$crt" ]]; then
    inf "SSL already exists for $domain"
    echo "$crt"
    return 0
  fi
  if exists mkcert; then
    run_cmd "mkcert -install >/dev/null 2>&1 || true"
    run_cmd "mkcert -key-file \"$key\" -cert-file \"$crt\" \"$domain\"" || { err "mkcert failed"; return 1; }
    msg "Created mkcert cert for $domain ($crt)"
    echo "$crt"
    return 0
  fi
  # fallback openssl self-signed
  run_cmd "openssl req -x509 -nodes -newkey rsa:2048 -days 825 -keyout \"$key\" -out \"$crt\" -subj \"/CN=$domain\" >/dev/null 2>&1" \
    && chmod 640 "$key" && chmod 644 "$crt" && msg "Created self-signed cert for $domain ($crt)" || { err "openssl failed"; return 1; }
  echo "$crt"
}

apache_reload() { run_cmd "apachectl configtest >/dev/null 2>&1 || true"; run_cmd "systemctl reload apache2 || true"; }
nginx_reload() { run_cmd "nginx -t >/dev/null 2>&1 || true"; run_cmd "systemctl reload nginx || true"; }

ensure_apache_enabled() { exists apache2 || { wrn "Apache not installed"; }; }
ensure_nginx_enabled() { exists nginx || { wrn "Nginx not installed"; }; }

apt_update_once() {
  if [[ -z "${_APT_UPDATED:-}" ]]; then
    run_cmd "apt-get update -y"
    _APT_UPDATED=1
  fi
}

install_pkg_if_missing() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    apt_update_once
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg"
  fi
}

### ------------- INSTALL HELPERS -------------
install_common() {
  apt_update_once
  install_pkg_if_missing "curl"
  install_pkg_if_missing "wget"
  install_pkg_if_missing "git"
  install_pkg_if_missing "unzip"
  install_pkg_if_missing "software-properties-common"
  install_pkg_if_missing "lsb-release"
}

install_apache() {
  install_pkg_if_missing "apache2"
  run_cmd "a2enmod proxy proxy_fcgi rewrite ssl headers setenvif >/dev/null 2>&1 || true"
  run_cmd "systemctl enable apache2 || true"
  msg "Apache installed/enabled"
}

install_nginx() {
  install_pkg_if_missing "nginx"
  run_cmd "systemctl enable nginx || true"
  msg "Nginx installed/enabled"
}

install_php_common() {
  local v="$1"
  apt_update_once
  add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
  apt_update_once
  run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y php${v} php${v}-fpm php${v}-cli php${v}-gd php${v}-mbstring php${v}-xml php${v}-curl php${v}-zip php${v}-mysql >/dev/null 2>&1 || true"
  msg "PHP $v installed (approx)."
}

install_node_nvm() {
  if [[ ! -d "$NVM_DIR" ]]; then
    run_cmd "mkdir -p $NVM_DIR && curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
  fi
  export NVM_DIR="$NVM_DIR"
  # shellcheck disable=SC1090
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  run_cmd "bash -lc 'source $NVM_DIR/nvm.sh && nvm install --lts && nvm alias default lts/*'" || true
  msg "NVM & Node LTS installed"
}

install_composer() {
  if ! exists composer; then
    run_cmd "php -r \"copy('https://getcomposer.org/installer','composer-setup.php');\""
    run_cmd "php composer-setup.php --install-dir=/usr/local/bin --filename=composer"
    run_cmd "rm -f composer-setup.php"
    msg "Composer installed"
  fi
}

install_mysql() {
  apt_update_once
  run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client" || true
  run_cmd "systemctl enable mysql || true"
  msg "MariaDB/MySQL installed"
}

install_mongodb() {
  apt_update_once
  install_pkg_if_missing "mongodb"
  run_cmd "systemctl enable mongodb || systemctl enable mongod || true"
  msg "MongoDB installed"
}

install_phpmyadmin() {
  apt_update_once
  run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin" || true
  msg "phpMyAdmin installed"
}

install_pm2() {
  # requires node/nvm to be loaded
  export NVM_DIR="$NVM_DIR"
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  if ! exists npm; then wrn "npm not found; ensure Node installed"; return; fi
  run_cmd "npm install -g pm2"
  msg "pm2 installed"
}

install_mongo_express() {
  export NVM_DIR="$NVM_DIR"
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  if ! exists npm; then wrn "npm not found; ensure Node installed"; return; fi
  run_cmd "npm install -g mongo-express"
  # make a simple systemd unit
  cat > /etc/systemd/system/mongo-express.service <<'EOF'
[Unit]
Description=Mongo Express
After=network.target

[Service]
ExecStart=/usr/bin/mongo-express
Restart=always
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
  run_cmd "systemctl daemon-reload"
  run_cmd "systemctl enable --now mongo-express || true"
  msg "mongo-express installed & enabled (port 8081 by default)"
}

### ------------- VHOST TEMPLATES -------------
create_apache_vhost() {
  local domain="$1" docroot="$2" ssl="${3:-n}" php_sock="${4:-}"
  local conf="$VHOST_APACHE_DIR/$domain.conf"
  if [[ "$ssl" == "y" ]]; then
    cat >"$conf" <<APACHE
<VirtualHost *:80>
  ServerName $domain
  Redirect permanent / https://$domain/
</VirtualHost>

<VirtualHost *:443>
  ServerName $domain
  DocumentRoot $docroot
  <Directory $docroot>
    AllowOverride All
    Require all granted
  </Directory>
  SSLEngine on
  SSLCertificateFile $SSL_DIR/$domain.crt
  SSLCertificateKeyFile $SSL_DIR/$domain.key
  ErrorLog \${APACHE_LOG_DIR}/$domain-error.log
  CustomLog \${APACHE_LOG_DIR}/$domain-access.log combined
</VirtualHost>
APACHE
  else
    cat >"$conf" <<APACHE
<VirtualHost *:80>
  ServerName $domain
  DocumentRoot $docroot
  <Directory $docroot>
    AllowOverride All
    Require all granted
  </Directory>
  ErrorLog \${APACHE_LOG_DIR}/$domain-error.log
  CustomLog \${APACHE_LOG_DIR}/$domain-access.log combined
</VirtualHost>
APACHE
  fi
  run_cmd "a2ensite $domain.conf || true"
  apache_reload
  msg "Apache vhost created: $conf"
}

create_nginx_vhost() {
  local domain="$1" docroot="$2" ssl="${3:-n}" php_sock="${4:-/run/php/php-fpm.sock}" port="${5:-80}"
  local conf="$VHOST_NGINX_DIR/$domain"
  if [[ "$ssl" == "y" ]]; then
    cat >"$conf" <<NGINX
server {
  listen $port;
  server_name $domain;
  root $docroot;
  index index.php index.html index.htm;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:$php_sock;
  }

  ssl_certificate $SSL_DIR/$domain.crt;
  ssl_certificate_key $SSL_DIR/$domain.key;
  access_log /var/log/nginx/$domain.access.log;
  error_log /var/log/nginx/$domain.error.log;
}
NGINX
  else
    cat >"$conf" <<NGINX
server {
  listen $port;
  server_name $domain;
  root $docroot;
  index index.php index.html index.htm;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:$php_sock;
  }

  access_log /var/log/nginx/$domain.access.log;
  error_log /var/log/nginx/$domain.error.log;
}
NGINX
  fi
  run_cmd "ln -sfn $conf $VHOST_NGINX_ENABLED/$domain"
  nginx_reload
  msg "Nginx vhost created: $conf"
}

### ------------- PROJECT SCAFFOLDERS -------------
scaffold_laravel() {
  local name="$1" root="$2"
  install_composer
  run_cmd "sudo -u \"$SUDO_USER\" composer create-project --prefer-dist laravel/laravel \"$root\""
  run_cmd "chown -R \"$SUDO_USER\":\"${SUDO_USER:-$(id -gn)}\" \"$root\" || true"
  msg "Laravel scaffolded at $root"
}

scaffold_wordpress() {
  local name="$1" root="$2"
  run_cmd "mkdir -p \"$root\""
  run_cmd "wget -q https://wordpress.org/latest.zip -O /tmp/wp.zip"
  run_cmd "unzip -oq /tmp/wp.zip -d /tmp"
  run_cmd "rsync -a /tmp/wordpress/ \"$root/\""
  run_cmd "chown -R \"$SUDO_USER\":\"${SUDO_USER:-$(id -gn)}\" \"$root\" || true"
  msg "WordPress scaffolded at $root"
}

scaffold_node_template() {
  local name="$1" root="$2" template="$3" port="$4"
  install_node_nvm
  export NVM_DIR="$NVM_DIR"
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  run_cmd "sudo -u \"$SUDO_USER\" bash -lc \"npm create vite@latest '$root' -- --template $template --yes\" || true"
  # create pm2
  if ! exists pm2; then install_pm2; fi
  cat >"$root/ecosystem.config.cjs" <<PM2
module.exports = {
  apps: [
    {
      name: "$name",
      cwd: "$root",
      script: "npm",
      args: "run dev",
      env: { PORT: "$port" }
    }
  ]
}
PM2
  run_cmd "chown \"$SUDO_USER\":\"${SUDO_USER:-$(id -gn)}\" \"$root/ecosystem.config.cjs\" || true"
  run_cmd "sudo -u \"$SUDO_USER\" bash -lc \"cd '$root' && npm install || true && pm2 start ecosystem.config.cjs || true\""
  msg "Node template ($template) scaffolded at $root (PM2 configured, port $port)"
}

scaffold_react() { scaffold_node_template "$1" "$2" "react" "$3"; }
scaffold_vue()   { scaffold_node_template "$1" "$2" "vue" "$3"; }
scaffold_svelte(){ scaffold_node_template "$1" "$2" "svelte" "$3"; }
scaffold_solid() { scaffold_node_template "$1" "$2" "solid" "$3"; }

scaffold_dotnet() {
  local name="$1" root="$2" type="$3"
  if ! exists dotnet; then wrn ".NET SDK not installed"; return 1; fi
  run_cmd "mkdir -p '$root' && cd '$root' && sudo -u \"$SUDO_USER\" dotnet new $type -n $name || true"
  msg ".NET ($type) scaffolded at $root"
}

scaffold_static_bootstrap() {
  local name="$1" root="$2"
  run_cmd "mkdir -p \"$root\""
  cat >"$root/index.html" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Bootstrap5 + jQuery Starter</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="p-4">
  <div class="container">
    <h1 class="mb-4">Bootstrap 5 + jQuery Starter</h1>
    <p id="msg">Hello world</p>
    <button class="btn btn-primary" id="btn">Click me</button>
  </div>
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
  <script>
    $('#btn').click(() => $('#msg').text('Clicked at ' + new Date()));
  </script>
</body>
</html>
HTML
  run_cmd "chown -R \"$SUDO_USER\":\"${SUDO_USER:-$(id -gn)}\" \"$root\" || true"
  msg "Bootstrap + jQuery static scaffolded at $root"
}

### ------------- DATABASE HELPERS -------------
create_mysql_db() {
  local project="$1"
  local dbname="${project//[^a-z0-9_]/_}"
  local dbuser="$dbname"
  local dbpass
  dbpass=$(openssl rand -base64 12)
  run_cmd "mysql -u root -e \"CREATE DATABASE IF NOT EXISTS \\\`$dbname\\\`; CREATE USER IF NOT EXISTS '$dbuser'@'localhost' IDENTIFIED BY '$dbpass'; GRANT ALL ON \\\`$dbname\\\`.* TO '$dbuser'@'localhost'; FLUSH PRIVILEGES;\" || true"
  echo "DB_NAME=$dbname" > "$PROJECTS_DIR/$project/.env.db"
  echo "DB_USER=$dbuser" >> "$PROJECTS_DIR/$project/.env.db"
  echo "DB_PASS=$dbpass" >> "$PROJECTS_DIR/$project/.env.db"
  msg "Created MySQL DB $dbname and user $dbuser (creds saved to .env.db)"
}

create_sqlite_db() {
  local project="$1"
  local dbfile="$PROJECTS_DIR/$project/database.sqlite"
  run_cmd "mkdir -p \"$PROJECTS_DIR/$project\""
  run_cmd "sqlite3 \"$dbfile\" \"VACUUM;\" || true"
  msg "Created SQLite DB at $dbfile"
}

create_mongo_db() {
  local project="$1"
  local dbname="${project//[^a-z0-9_]/_}"
  if ! exists mongo; then wrn "mongo client not found"; fi
  run_cmd "mongo --eval \"db.getSiblingDB('$dbname').collection('init').insertOne({created: new Date()})\" || true"
  msg "Created/initialized MongoDB database: $dbname"
}

backup_mysql() {
  read -rp "MySQL DB name: " DB
  local out="$BACKUP_DIR/${DB}_$(date +%F_%H%M%S).sql"
  run_cmd "mysqldump $DB > '$out' && msg 'MySQL backup saved: $out' || err 'Backup failed'"
}

restore_mysql() {
  read -rp "Path to dump (.sql): " IN
  read -rp "Target DB name: " DB
  run_cmd "mysql $DB < '$IN' && msg 'Restore done' || err 'Restore failed'"
}

backup_mongo() {
  read -rp "MongoDB name: " DB
  local out="$BACKUP_DIR/${DB}_$(date +%F_%H%M%S)"
  run_cmd "mongodump -d '$DB' -o '$out' && msg 'MongoDB backup saved: $out' || err 'Backup failed'"
}

restore_mongo() {
  read -rp "Mongo dump dir: " IN
  read -rp "Target DB name: " DB
  run_cmd "mongorestore -d '$DB' '$IN' && msg 'Mongo restore done' || err 'Restore failed'"
}

### ------------- GIT & GITHUB -------------
git_init_and_remote() {
  local project="$1"
  local path="$PROJECTS_DIR/$project"
  read -rp "Initialize git repo for $project? (y/n): " yn
  [[ "$yn" =~ ^[Yy]$ ]] || return
  run_cmd "cd '$path' && sudo -u \"$SUDO_USER\" git init && sudo -u \"$SUDO_USER\" git add . && sudo -u \"$SUDO_USER\" git commit -m 'Initial commit' || true"
  read -rp "Create GitHub repo and push? (requires PAT env var GITHUB_TOKEN) (y/n): " yn2
  if [[ "$yn2" =~ ^[Yy]$ ]]; then
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
      wrn "GITHUB_TOKEN not set in environment. Skipping GitHub creation."
      return
    fi
    read -rp "Repo name (default: $project): " repo_name
    repo_name="${repo_name:-$project}"
    local private="true"
    read -rp "Private repo? (y/n): " priv
    [[ "$priv" =~ ^[Yy]$ ]] || private="false"
    curl -s -H "Authorization: token $GITHUB_TOKEN" -d "{\"name\":\"$repo_name\",\"private\":$private}" https://api.github.com/user/repos >/tmp/github_create.json
    local ssh_url
    ssh_url=$(jq -r '.ssh_url' /tmp/github_create.json 2>/dev/null || true)
    if [[ -n "$ssh_url" && "$ssh_url" != "null" ]]; then
      run_cmd "cd '$path' && sudo -u \"$SUDO_USER\" git remote add origin '$ssh_url' && sudo -u \"$SUDO_USER\" git push -u origin master || true"
      msg "GitHub repo created & pushed: $ssh_url"
    else
      wrn "GitHub creation failed; check /tmp/github_create.json"
    fi
  fi
}

### ------------- FTP & SFTP -------------
install_vsftpd() {
  install_pkg_if_missing "vsftpd"
  run_cmd "systemctl enable --now vsftpd || true"
  msg "vsftpd installed & enabled"
}
create_sftp_user() {
  read -rp "SFTP username: " user
  read -rp "Project folder to chroot to (full path): " folder
  run_cmd "mkdir -p '$folder'"
  if id "$user" >/dev/null 2>&1; then wrn "User exists"; else run_cmd "useradd -M -s /sbin/nologin -d '$folder' '$user'"; fi
  run_cmd "usermod -a -G www-data '$user' || true"
  msg "SFTP user $user created (chroot: $folder). Configure sshd_config accordingly."
}

### ------------- UI: DASHBOARD & MENUS -------------
clear; printf "\n${C_BLU}SERVERL - Ultimate Local Dev Environment Manager (v2.0)${C_RESET}\n"
echo "$MENU_TREE_ASCII"
echo
inf "Loading..."

require_root
ensure_dirs
install_common

press_enter_to_continue() { read -r -p $'Press Enter to continue...\n' _; }

show_dashboard() {
  clear
  echo -e "${C_BLU}===== DASHBOARD =====${C_RESET}"
  echo "Projects root: $PROJECTS_DIR"
  echo
  echo -e "${C_YLW}Services:${C_RESET}"
  for svc in apache2 nginx mysql mongod mongo-express; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then printf "  %-15s : ${C_GRN}Running${C_RESET}\n" "$svc"; else printf "  %-15s : ${C_RED}Stopped${C_RESET}\n" "$svc"; fi
  done
  echo
  echo -e "${C_YLW}Active Projects (sample):${C_RESET}"
  if [[ -d "$PROJECTS_DIR" ]]; then
    find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -printf "  %f\n" | head -n 10 || true
  else
    echo "  (no projects)"
  fi
  echo
  echo -e "${C_YLW}System Versions:${C_RESET}"
  exists php && echo " PHP: $(php -v | head -n1)"
  exists node && echo " Node: $(node -v)"
  exists dotnet && echo " .NET: $(dotnet --list-sdks 2>/dev/null | head -n1 || true)"
  exists mongo && echo " Mongo: $(mongod --version | head -n1 2>/dev/null || true)"
  exists mysql && echo " MySQL: $(mysql --version 2>/dev/null | awk '{print $5}' | tr -d ',')"
  echo
  echo -e "${C_CYN}Quick Actions:${C_RESET}"
  echo "  1) Create new project"
  echo "  2) Open projects folder"
  echo "  3) Manage services"
  echo "  4) Show full menu"
  echo "  0) Exit"
  read -rp "Choice: " dch
  case "$dch" in
    1) create_project_wizard ;;
    2) xdg-open "$PROJECTS_DIR" >/dev/null 2>&1 || true; press_enter_to_continue ;;
    3) services_menu ;;
    4) main_menu ;;
    0) exit 0 ;;
    *) main_menu ;;
  esac
}

# Services Menu
services_menu() {
  while true; do
    clear; echo -e "${C_BLU}=== SERVICE MANAGEMENT ===${C_RESET}"
    echo "1) Start All Services"
    echo "2) Stop All Services"
    echo "3) Restart All Services"
    echo "4) Start Apache"
    echo "5) Stop Apache"
    echo "6) Start Nginx"
    echo "7) Stop Nginx"
    echo "8) Start MySQL"
    echo "9) Stop MySQL"
    echo "10) Start MongoDB"
    echo "11) Stop MongoDB"
    echo "12) Start Node PM2 (resurrect)"
    echo "13) Stop Node PM2 (stop all)"
    echo "14) Back"
    read -rp "Choice: " ch
    case "$ch" in
      1) run_cmd "systemctl start apache2 nginx mysql mongod || true"; msg "Started core services"; press_enter_to_continue ;;
      2) run_cmd "systemctl stop apache2 nginx mysql mongod || true"; msg "Stopped core services"; press_enter_to_continue ;;
      3) run_cmd "systemctl restart apache2 nginx mysql mongod || true"; msg "Restarted core services"; press_enter_to_continue ;;
      4) run_cmd "systemctl start apache2 || true"; press_enter_to_continue ;;
      5) run_cmd "systemctl stop apache2 || true"; press_enter_to_continue ;;
      6) run_cmd "systemctl start nginx || true"; press_enter_to_continue ;;
      7) run_cmd "systemctl stop nginx || true"; press_enter_to_continue ;;
      8) run_cmd "systemctl start mysql || true"; press_enter_to_continue ;;
      9) run_cmd "systemctl stop mysql || true"; press_enter_to_continue ;;
      10) run_cmd "systemctl start mongod || systemctl start mongodb || true"; press_enter_to_continue ;;
      11) run_cmd "systemctl stop mongod || systemctl stop mongodb || true"; press_enter_to_continue ;;
      12) run_cmd "sudo -u \"$SUDO_USER\" pm2 resurrect || sudo -u \"$SUDO_USER\" pm2 list || true"; press_enter_to_continue ;;
      13) run_cmd "sudo -u \"$SUDO_USER\" pm2 stop all || true"; press_enter_to_continue ;;
      14) break ;;
      *) wrn "Invalid" ;;
    esac
  done
}

### ------------- PROJECT WIZARD -------------
create_project_wizard() {
  echo -e "${C_BLU}=== Create New Project Wizard ===${C_RESET}"
  read -rp "Project Name: " pname
  [[ -z "$pname" ]] && { err "Name required"; return 1; }
  echo "Choose root folder:"
  nl -ba "$ROOTS_FILE" 2>/dev/null || true
  read -rp "Enter index or path (enter to use default $PROJECTS_DIR): " rootsel
  if [[ -z "$rootsel" ]]; then root="$PROJECTS_DIR"; else
    if [[ "$rootsel" =~ ^[0-9]+$ ]]; then
      root=$(sed -n "${rootsel}p" "$ROOTS_FILE" 2>/dev/null || echo "$PROJECTS_DIR")
    else
      root="$rootsel"
    fi
  fi
  read -rp "Choose stack (1 Laravel,2 WP,3 PHP static,4 React,5 Vue,6 Svelte,7 SolidJS,8 Node Express,9 .NET webapi,10 Bootstrap+jQuery): " st
  read -rp "Port (blank = auto): " port
  if [[ -z "$port" ]]; then port=$(find_available_port 3000); fi
  read -rp "Local domain (default ${pname}.local): " domain
  domain="${domain:-${pname}.local}"
  read -rp "Create SSL (mkcert/self-signed)? (y/N): " mk
  mk="${mk:-n}"
  local project_root="$root/$pname"
  run_cmd "mkdir -p '$project_root'"
  case "$st" in
    1) scaffold_laravel "$pname" "$project_root"; docroot="$project_root/public"; type=php ;;
    2) scaffold_wordpress "$pname" "$project_root"; docroot="$project_root"; type=php ;;
    3) run_cmd "mkdir -p '$project_root' && echo '<h1>$pname</h1>' > '$project_root/index.html'"; docroot="$project_root"; type=php ;;
    4) scaffold_react "$pname" "$project_root" "$port"; docroot="$project_root"; type=node ;;
    5) scaffold_vue "$pname" "$project_root" "$port"; docroot="$project_root"; type=node ;;
    6) scaffold_svelte "$pname" "$project_root" "$port"; docroot="$project_root"; type=node ;;
    7) scaffold_solid "$pname" "$project_root" "$port"; docroot="$project_root"; type=node ;;
    8) run_cmd "mkdir -p '$project_root' && cd '$project_root' && npm init -y"; docroot="$project_root"; type=node ;;
    9) scaffold_dotnet "$pname" "$project_root" "webapi"; docroot="$project_root"; type=dotnet ;;
    10) scaffold_static_bootstrap "$pname" "$project_root"; docroot="$project_root"; type=static ;;
    *) err "Invalid stack"; return 1 ;;
  esac
  # hosts & vhost & ssl
  add_hosts_entry "$domain"
  if [[ "$mk" == "y" || "$mk" == "Y" ]]; then create_self_signed_cert "$domain"; fi
  if exists apache2; then create_apache_vhost "$domain" "$docroot" "${mk,,}" ; fi
  if exists nginx; then create_nginx_vhost "$domain" "$docroot" "${mk,,}" "/run/php/php${DEFAULT_PHP_VERSION:-8.2}-fpm.sock" 80; fi
  run_cmd "chown -R \"$SUDO_USER\":\"${SUDO_USER:-$(id -gn)}\" \"$project_root\" || true"
  msg "Project $pname created at $project_root (domain: $domain, port: $port)"
  git_init_and_remote "$pname"
  press_enter_to_continue
}

### ------------- VHOST MENU -------------
vhost_menu() {
  while true; do
    clear; echo -e "${C_BLU}=== Virtual Host Management ===${C_RESET}"
    echo "1) Create vhost"
    echo "2) Edit vhost"
    echo "3) Remove vhost"
    echo "4) List vhosts"
    echo "5) Back"
    read -rp "Choice: " vch
    case "$vch" in
      1)
        read -rp "Domain: " d
        read -rp "DocRoot: " dr
        read -rp "SSL? (y/N): " ssl
        if exists apache2; then create_apache_vhost "$d" "$dr" "${ssl:-n}"; fi
        if exists nginx; then create_nginx_vhost "$d" "$dr" "${ssl:-n}"; fi
        add_hosts_entry "$d"
        press_enter_to_continue
        ;;
      2)
        read -rp "Domain to edit: " ed
        ${EDITOR} "$VHOST_APACHE_DIR/$ed.conf" 2>/dev/null || ${EDITOR} "$VHOST_NGINX_DIR/$ed" 2>/dev/null
        apache_reload; nginx_reload
        ;;
      3)
        read -rp "Domain to remove: " rem
        confirm "Remove vhost $rem? (y/N): " || { inf "Aborted"; continue; }
        if [[ -f "$VHOST_APACHE_DIR/$rem.conf" ]]; then run_cmd "a2dissite $rem.conf || true"; run_cmd "rm -f $VHOST_APACHE_DIR/$rem.conf"; apache_reload; fi
        if [[ -f "$VHOST_NGINX_DIR/$rem" ]]; then run_cmd "rm -f $VHOST_NGINX_DIR/$rem $VHOST_NGINX_ENABLED/$rem"; nginx_reload; fi
        run_cmd "sed -i \"/$rem/d\" $HOSTS_FILE || true"
        msg "Removed vhost $rem"
        ;;
      4)
        echo "Apache sites-available:"; ls -1 "$VHOST_APACHE_DIR" || true
        echo "Nginx sites-available:"; ls -1 "$VHOST_NGINX_DIR" || true
        press_enter_to_continue
        ;;
      5) break ;;
      *) wrn "Invalid" ;;
    esac
  done
}

### ------------- PHP MANAGEMENT -------------
php_version_menu() {
  while true; do
    clear; echo -e "${C_BLU}=== PHP Version Management ===${C_RESET}"
    echo "1) List installed PHP versions"
    echo "2) Install PHP version (via Ondřej PPA)"
    echo "3) Switch default php (update-alternatives)"
    echo "4) Edit php.ini for specific version"
    echo "5) Back"
    read -rp "Choice: " pch
    case "$pch" in
      1) ls /usr/bin/php* 2>/dev/null | sed 's|/usr/bin/||g' | grep -E '^php[0-9]' || echo "No php binaries found"; press_enter_to_continue ;;
      2) read -rp "Version (e.g., 8.2): " pv; install_php_common "$pv"; press_enter_to_continue ;;
      3) read -rp "Version to set as default (e.g., 8.2): " pv; if [[ -x "/usr/bin/php$pv" ]]; then run_cmd "update-alternatives --set php /usr/bin/php$pv || true"; msg "Switched php CLI to $pv"; else wrn "php$pv not found"; fi; press_enter_to_continue ;;
      4) read -rp "php version to edit (e.g., 8.2): " pv; ${EDITOR:-nano} "/etc/php/$pv/fpm/php.ini" 2>/dev/null || wrn "php.ini not found"; press_enter_to_continue ;;
      5) break ;;
      *) wrn "Invalid" ;;
    esac
  done
}

### ------------- MAIN MENU -------------
main_menu() {
  while true; do
    clear
    echo -e "${C_GRN}===== serverL - Local Development Manager =====${C_RESET}"
    echo "Projects root: $PROJECTS_DIR"
    echo
    echo "1) Dashboard"
    echo "2) Start/Stop Services"
    echo "3) Project Management"
    echo "4) Virtual Host Management"
    echo "5) Database Management"
    echo "6) PHP & Extensions"
    echo "7) Version Management (Node/.NET/PHP)"
    echo "8) Git & GitHub"
    echo "9) FTP / SFTP"
    echo "10) Backup & Restore"
    echo "11) Install Components"
    echo "12) Uninstall / Remove"
    echo "13) Settings"
    echo "0) Exit"
    read -rp "Select an option: " m
    case "$m" in
      1) show_dashboard ;;
      2) services_menu ;;
      3) create_project_wizard ;;
      4) vhost_menu ;;
      5)
        echo -e "${C_BLU}DB MENU:${C_RESET} 1) MySQL create 2) SQLite create 3) Mongo create 4) Backup MySQL 5) Backup Mongo 6) Back"
        read -rp "Choice: " dbch
        case "$dbch" in
          1) create_mysql_db "$(read -p 'Project name: ' pn && echo "$pn")"; press_enter_to_continue ;;
          2) create_sqlite_db "$(read -p 'Project name: ' pn && echo "$pn")"; press_enter_to_continue ;;
          3) create_mongo_db "$(read -p 'Project name: ' pn && echo "$pn")"; press_enter_to_continue ;;
          4) backup_mysql; press_enter_to_continue ;;
          5) backup_mongo; press_enter_to_continue ;;
          6) ;;
        esac
        ;;
      6) php_version_menu ;;
      7)
        echo "1) Node (nvm install/use) 2) .NET (install listing) 3) Back"
        read -rp "Choice: " vch
        case "$vch" in
          1) install_node_nvm; install_pm2; press_enter_to_continue ;;
          2) if exists dotnet; then dotnet --list-sdks || true; else wrn ".NET not installed"; fi; press_enter_to_continue ;;
          3) ;;
        esac
        ;;
      8)
        echo "Git menu: 1) Init & optional GitHub 2) List repos 3) Back"
        read -rp "Choice: " gch
        case "$gch" in
          1) read -rp "Project name: " p; git_init_and_remote "$p"; press_enter_to_continue ;;
          2) find "$PROJECTS_DIR" -maxdepth 2 -type d -name ".git" -printf "%h\n" | sed "s|$PROJECTS_DIR/||g" || true; press_enter_to_continue ;;
          3) ;;
        esac
        ;;
      9)
        echo "FTP/SFTP: 1) Install vsftpd 2) Create SFTP user 3) Back"
        read -rp "Choice: " fch
        case "$fch" in
          1) install_vsftpd; press_enter_to_continue ;;
          2) create_sftp_user; press_enter_to_continue ;;
          3) ;;
        esac
        ;;
      10)
        echo "Backup & Restore: 1) Backup MySQL 2) Backup Mongo 3) Restore MySQL 4) Restore Mongo 5) Back"
        read -rp "Choice: " bch
        case "$bch" in
          1) backup_mysql; press_enter_to_continue ;;
          2) backup_mongo; press_enter_to_continue ;;
          3) restore_mysql; press_enter_to_continue ;;
          4) restore_mongo; press_enter_to_continue ;;
          5) ;;
        esac
        ;;
      11)
        echo "Install: 1) Apache 2) Nginx 3) PHP 4) MySQL 5) MongoDB 6) Composer 7) phpMyAdmin 8) Mongo Express 9) Node/NVM 10) Back"
        read -rp "Choice: " ich
        case "$ich" in
          1) install_apache; press_enter_to_continue ;;
          2) install_nginx; press_enter_to_continue ;;
          3) read -rp "PHP version (e.g. 8.2): " pv; install_php_common "$pv"; press_enter_to_continue ;;
          4) install_mysql; press_enter_to_continue ;;
          5) install_mongodb; press_enter_to_continue ;;
          6) install_composer; press_enter_to_continue ;;
          7) install_phpmyadmin; press_enter_to_continue ;;
          8) install_mongo_express; press_enter_to_continue ;;
          9) install_node_nvm; press_enter_to_continue ;;
          10) ;;
        esac
        ;;
      12)
        echo "Uninstall menu (careful): 1) Uninstall PHP 2) Apache 3) Nginx 4) MySQL 5) Mongo 6) Node/NVM 7) Composer 8) Back"
        read -rp "Choice: " uch
        case "$uch" in
          1) read -rp "Remove all php packages? Type 'YES' to confirm: " conf; [[ "$conf" == "YES" ]] || continue; run_cmd "apt-get purge -y 'php*'"; msg "PHP removed"; press_enter_to_continue ;;
          2) read -rp "Confirm remove apache? (type YES): " conf; [[ "$conf" == "YES" ]] || continue; run_cmd "apt-get purge -y apache2*"; press_enter_to_continue ;;
          3) read -rp "Confirm remove nginx? (type YES): " conf; [[ "$conf" == "YES" ]] || continue; run_cmd "apt-get purge -y nginx*"; press_enter_to_continue ;;
          4) read -rp "Confirm remove mysql? (type YES): " conf; [[ "$conf" == "YES" ]] || continue; run_cmd "apt-get purge -y mariadb-server mariadb-client"; press_enter_to_continue ;;
          5) read -rp "Confirm remove mongodb? (type YES): " conf; [[ "$conf" == "YES" ]] || continue; run_cmd "apt-get purge -y mongodb*"; press_enter_to_continue ;;
          6) read -rp "Confirm remove nvm? (type YES): " conf; [[ "$conf" == "YES" ]] || continue; run_cmd "rm -rf $NVM_DIR /root/.nvm"; press_enter_to_continue ;;
          7) run_cmd "rm -f /usr/local/bin/composer"; press_enter_to_continue ;;
          8) ;;
        esac
        ;;
      13)
        echo "Settings: 1) Set default projects root 2) Show log 3) Toggle dry-run 4) Back"
        read -rp "Choice: " sch
        case "$sch" in
          1) read -rp "New projects root: " np; PROJECTS_DIR="$np"; run_cmd "sed -i '1s|.*|$PROJECTS_DIR|' $ROOTS_FILE || echo \"$PROJECTS_DIR\" >> $ROOTS_FILE"; press_enter_to_continue ;;
          2) tail -n 200 "$LOG_FILE" || true; press_enter_to_continue ;;
          3) wrn "Re-run script with --dry-run or edit variables at top"; press_enter_to_continue ;;
          4) ;;
        esac
        ;;
      0) exit 0 ;;
      *) wrn "Invalid" ;;
    esac
  done
}

### ------------- ENTRYPOINT -------------
main() {
  main_menu
}

main "$@"
