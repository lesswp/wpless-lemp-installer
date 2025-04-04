# WPLess LEMP Installer 🚀

A simple, modular shell script to install a full LEMP stack + WordPress with SSL — no fuss.  
Built with ❤️ for fast, repeatable WordPress deployments.

---

## 🎯 Features

- Installs **LEMP Stack** (Nginx, MySQL, PHP)
- Installs and configures **WordPress**
- Generates DB name, user, password automatically
- DNS check + server IP suggestion
- Configures **SSL via Let's Encrypt**
- Modular design for easy editing
- Logs setup at `/var/log/wpless-lemp-installer/sites.log`
- Clean terminal UI with a CLI ASCII logo
- Supports multiple domains and subdomains

---

## 🛠️ Installation

### ✅ One-liner Install

```bash
curl -sSL https://raw.githubusercontent.com/lesswp/wpless-lemp-installer/main/wpless-lemp-installer.sh | bash
