#!/usr/bin/env bash
#
# VPS Security Hardening for Hostinger Ubuntu 24.04
# Run as root on a fresh Hostinger VPS with OpenClaw deployed.
#
# This script:
#   1. Creates a non-root sudo user with SSH key auth
#   2. Hardens SSH (key-only, non-standard port, no root login)
#   3. Configures UFW firewall
#   4. Installs and configures fail2ban
#   5. Enables automatic security updates
#   6. Applies kernel-level security hardening
#   7. Sets timezone and swap (if needed)
#
# Usage: bash 01-harden-vps.sh
#
set -euo pipefail

# ──────────────────────────────────────────────
# Configuration — edit these before running
# ──────────────────────────────────────────────
NEW_USER="openclaw"
SSH_PORT=2222
TIMEZONE="UTC"
# Paste your local machine's public key here (from ~/.ssh/id_ed25519.pub)
SSH_PUBLIC_KEY=""

# ──────────────────────────────────────────────
# Preflight checks
# ──────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

if [[ -z "$SSH_PUBLIC_KEY" ]]; then
  echo "ERROR: Set SSH_PUBLIC_KEY at the top of this script before running."
  echo "       On your LOCAL machine, run: cat ~/.ssh/id_ed25519.pub"
  echo "       Paste the output into the SSH_PUBLIC_KEY variable."
  exit 1
fi

echo "╔══════════════════════════════════════════════╗"
echo "║  Hostinger VPS Security Hardening            ║"
echo "║  Ubuntu 24.04 · OpenClaw                     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────
# 1. System update
# ──────────────────────────────────────────────
echo "[1/8] Updating system packages..."
apt update && apt upgrade -y
apt install -y \
  curl wget git unzip htop net-tools \
  ufw fail2ban unattended-upgrades apt-listchanges \
  logrotate apparmor apparmor-utils

# ──────────────────────────────────────────────
# 2. Timezone and locale
# ──────────────────────────────────────────────
echo "[2/8] Setting timezone to $TIMEZONE..."
timedatectl set-timezone "$TIMEZONE"

# ──────────────────────────────────────────────
# 3. Create non-root user
# ──────────────────────────────────────────────
echo "[3/8] Creating user '$NEW_USER' with sudo privileges..."
if id "$NEW_USER" &>/dev/null; then
  echo "  User '$NEW_USER' already exists, skipping creation."
else
  adduser --disabled-password --gecos "OpenClaw Admin" "$NEW_USER"
  usermod -aG sudo "$NEW_USER"
  # Allow passwordless sudo for deployment convenience
  echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USER"
  chmod 440 "/etc/sudoers.d/$NEW_USER"
fi

# Set up SSH key for the new user
mkdir -p "/home/$NEW_USER/.ssh"
echo "$SSH_PUBLIC_KEY" > "/home/$NEW_USER/.ssh/authorized_keys"
chmod 700 "/home/$NEW_USER/.ssh"
chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"

# Add user to docker group so they can manage containers
if getent group docker &>/dev/null; then
  usermod -aG docker "$NEW_USER"
fi

# ──────────────────────────────────────────────
# 4. Harden SSH
# ──────────────────────────────────────────────
echo "[4/8] Hardening SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config.d/hardened.conf << 'SSHEOF'
Port ${SSH_PORT}
Protocol 2

PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no

MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30

ClientAliveInterval 300
ClientAliveCountMax 2

Banner none
DebianBanner no
SSHEOF

# Replace the variable placeholder with actual port
sed -i "s/\${SSH_PORT}/$SSH_PORT/" /etc/ssh/sshd_config.d/hardened.conf

# Validate config before restarting
sshd -t && echo "  SSH config validated OK."

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║  IMPORTANT: Before restarting SSH, test in a NEW        ║"
echo "  ║  terminal that you can connect:                         ║"
echo "  ║                                                         ║"
echo "  ║  ssh -p $SSH_PORT $NEW_USER@YOUR_VPS_IP                ║"
echo "  ║                                                         ║"
echo "  ║  SSH will NOT be restarted automatically.               ║"
echo "  ║  Run: sudo systemctl restart sshd                       ║"
echo "  ║  only after confirming key-based access works.          ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────
# 5. Configure UFW firewall
# ──────────────────────────────────────────────
echo "[5/8] Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing

# SSH on custom port
ufw allow "$SSH_PORT"/tcp comment "SSH"

# OpenClaw gateway — restrict to specific IPs if possible
# The Hostinger template assigns a random port; find it:
OPENCLAW_PORT=$(docker port openclaw 2>/dev/null | grep -oP '\d+$' | head -1 || echo "")
if [[ -n "$OPENCLAW_PORT" ]]; then
  ufw allow "$OPENCLAW_PORT"/tcp comment "OpenClaw Gateway"
  echo "  Detected OpenClaw on port $OPENCLAW_PORT"
else
  echo "  WARNING: Could not detect OpenClaw port. You may need to manually allow it:"
  echo "           sudo ufw allow <PORT>/tcp comment 'OpenClaw Gateway'"
fi

# HTTP/HTTPS for reverse proxy (enable when you add a domain)
# ufw allow 80/tcp comment "HTTP"
# ufw allow 443/tcp comment "HTTPS"

ufw --force enable
ufw status verbose

# ──────────────────────────────────────────────
# 6. Configure fail2ban
# ──────────────────────────────────────────────
echo "[6/8] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << JAILEOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd
banaction = ufw

[sshd]
enabled  = true
port     = $SSH_PORT
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 86400
JAILEOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "  fail2ban active. Banning after 3 failed SSH attempts for 24h."

# ──────────────────────────────────────────────
# 7. Automatic security updates
# ──────────────────────────────────────────────
echo "[7/8] Enabling unattended security upgrades..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UUEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UUEOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUTOEOF

systemctl enable unattended-upgrades
echo "  Automatic security updates enabled."

# ──────────────────────────────────────────────
# 8. Kernel hardening (sysctl)
# ──────────────────────────────────────────────
echo "[8/8] Applying kernel security parameters..."
cat > /etc/sysctl.d/99-hardening.conf << 'SYSEOF'
# Prevent IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IPv6 if not needed (uncomment if you don't use IPv6)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# Harden memory
kernel.randomize_va_space = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
SYSEOF

sysctl --system > /dev/null 2>&1
echo "  Kernel hardening applied."

# ──────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  VPS hardening complete!                     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  • User '$NEW_USER' created with sudo + SSH key"
echo "  • SSH moved to port $SSH_PORT (key-only, no root)"
echo "  • UFW firewall active (SSH + OpenClaw ports only)"
echo "  • fail2ban protecting SSH (24h ban after 3 attempts)"
echo "  • Automatic security updates enabled"
echo "  • Kernel-level hardening applied"
echo ""
echo "NEXT STEPS:"
echo "  1. Open a NEW terminal and verify SSH access:"
echo "     ssh -p $SSH_PORT $NEW_USER@YOUR_VPS_IP"
echo ""
echo "  2. Only after confirming access, restart SSH:"
echo "     sudo systemctl restart sshd"
echo ""
echo "  3. Run 02-harden-docker.sh"
echo "  4. Run 03-harden-openclaw.sh"
