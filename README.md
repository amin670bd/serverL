## serverL.sh - Ultimate Local Development Environment Manager for Ubuntu/Dabian/linux 

A comprehensive, interactive CLI tool for managing a full-stack local development environment on Ubuntu/Debian systems. This script automates project scaffolding, service management, virtual hosts, databases, and more.

---
### Script File : serverLv2.sh ###

## 🚨 **WARNING**

**This script performs system-level operations including:**
- Package installation/removal
- Editing `/etc/hosts`
- Creating systemd services
- Modifying web server configurations
- Creating SSL certificates
- Managing system users

**USE AT YOUR OWN RISK. Designed for local development environments only.**
- Always read through the script before running
- Use `--dry-run` to test commands first
- Backup important data before using
- Not recommended for production systems

---

## 📋 **Features**

- **Dashboard-first** interactive CLI with menus
-### **Project scaffolding**: Laravel, WordPress, PHP, Node.js, React, Vue, Svelte, SolidJS, .NET, static sites, Bootstrap5+jQuery ###
- **Web servers**: Apache & Nginx virtual hosts automation
- **SSL**: mkcert (preferred) or OpenSSL self-signed certificates
- **PHP management**: Version detection & switching
- **Node.js**: Version management via NVM
- **Process management**: PM2 for Node applications
- **Database management**: MySQL/MariaDB, PostgreSQL, MongoDB, SQLite, Redis
- **Admin tools**: Mongo Express & phpMyAdmin integration
- **Git & GitHub**: Repository creation via PAT
- **File transfer**: FTP/SFTP helpers (vsftpd + SFTP accounts)
- **Backup system**: Automated backups with logging
- **Dry-run mode**: Test commands without execution

---

## 🛠 **Installation & Usage**

```bash
# Download the script
wget https://github.com/amin670bd/serverL/blob/main/serverLv2.sh

# Git Clone
git clone https://github.com/amin670bd/serverL.git

# Make executable
chmod +x serverL.sh

# Run with sudo (required for system operations)
sudo ./serverL.sh

# Dry-run mode (test without making changes)
sudo ./serverL.sh --dry-run

# Non-interactive mode (assume yes to all confirmations)
sudo ./serverL.sh --yes
```

---

## 📊 **Menu Structure**

```
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
```

### **Dashboard View**
```
===== DASHBOARD =====
Projects root: /var/www/html

Services:
  apache2        : Running
  nginx          : Stopped
  mysql          : Running
  mongod         : Stopped
  mongo-express  : Stopped

Active Projects (sample):
  my-laravel-app
  react-project
  wordpress-site

System Versions:
 PHP: PHP 8.2.12
 Node: v18.17.1
 .NET: 6.0.400
 MySQL: 10.6.12
 Mongo: db version v5.0.10

Quick Actions:
  1) Create new project
  2) Open projects folder
  3) Manage services
  4) Show full menu
  0) Exit
```

### **Services Menu**
```
=== SERVICE MANAGEMENT ===
1) Start All Services
2) Stop All Services
3) Restart All Services
4) Start Apache
5) Stop Apache
6) Start Nginx
7) Stop Nginx
8) Start MySQL
9) Stop MySQL
10) Start MongoDB
11) Stop MongoDB
12) Start Node PM2 (resurrect)
13) Stop Node PM2 (stop all)
14) Back
```

### **Project Creation Wizard**
```
=== Create New Project Wizard ===
Project Name: my-project
Choose root folder:
1) /var/www/html
Enter index or path (enter to use default /var/www/html): 
Choose stack (1 Laravel,2 WP,3 PHP static,4 React,5 Vue,6 Svelte,7 SolidJS,8 Node Express,9 .NET webapi,10 Bootstrap+jQuery): 4
Port (blank = auto): 3000
Local domain (default my-project.local): 
Create SSL (mkcert/self-signed)? (y/N): y
```

---

## 🔧 **Configuration**

- **Config directory**: `/etc/devstack/`
- **Log file**: `/etc/devstack/devstack.log`
- **Projects root**: `/var/www/html` (configurable)
- **SSL certificates**: `/etc/ssl/devstack/`
- **Backups**: `/etc/devstack/backups/`

---

## 📁 **Project Types Supported**

1. **Laravel** - Full PHP framework
2. **WordPress** - Content management system
3. **PHP Static** - Basic HTML/PHP site
4. **React** - Vite-based React app
5. **Vue** - Vite-based Vue app
6. **Svelte** - Vite-based Svelte app
7. **SolidJS** - Vite-based SolidJS app
8. **Node Express** - Basic Node.js setup
9. **.NET WebAPI** - ASP.NET Core WebAPI
10. **Bootstrap + jQuery** - Static template with Bootstrap 5

---

## 🌐 **Virtual Hosts Automation**

Automatically creates:
- Apache sites-available configuration
- Nginx sites-available configuration
- /etc/hosts entry for local domain
- SSL certificates (if requested)
- Proper file permissions

Example generated domain: `my-project.local`

---

## 🗄️ **Database Support**

- **MySQL/MariaDB**: Automated database/user creation with credentials saved to `.env.db`
- **SQLite**: Database file creation in project directory
- **MongoDB**: Database creation and initialization
- **Backup/Restore**: Tools for MySQL and MongoDB

---

## 🔐 **Security Notes**

- Creates self-signed SSL certificates for local development
- SFTP users are chrooted to their project directories
- Database credentials are stored in project `.env.db` files
- GitHub integration requires `GITHUB_TOKEN` environment variable

---

## 📝 **Logging**

All operations are logged to `/etc/devstack/devstack.log` with timestamps:
```
2023-08-15 14:30:45 - [INFO] Starting project creation wizard
2023-08-15 14:31:02 - [OK] Laravel scaffolded at /var/www/html/my-project
2023-08-15 14:31:05 - [OK] Added hosts entry for my-project.local
```

---

## ⚠️ **Troubleshooting**

1. **Permission issues**: Ensure script is run with `sudo`
2. **Port conflicts**: Script automatically finds available ports
3. **Service failures**: Check logs in `/var/log/` for specific services
4. **Dry-run mode**: Use `--dry-run` to preview commands before execution

---

## 🗑️ **Uninstallation**

Use the built-in uninstall menu to remove components. The script provides confirmation prompts before removing any packages.

---

## 📄 **License**

This tool is provided as-is for local development purposes. Always review and understand any script before running it on your system.

---

**Note**: This tool is designed for Ubuntu/Debian-based systems and may require adjustments for other distributions.
