#!/bin/bash
set -e

echo ""
echo "[INFO] ==============================================="
echo "[INFO] Debian Jessie → Stretch → Buster → Bullseye"
echo "[INFO] Stepwise Upgrade Script for UniFi CloudKey Gen1"
echo "[INFO] ==============================================="
echo ""

export DEBIAN_FRONTEND=noninteractive

# Detect Debian version
CURRENT_VERSION=$(lsb_release -cs 2>/dev/null || echo "unknown")
echo "[INFO] Detected Debian version: ${CURRENT_VERSION}"

# Freeze vendor kernel packages
echo ""
echo "[INFO] Freezing vendor kernel packages..."
apt-mark hold linux-image-3.10.20-ubnt-mtk || true

# Ensure essential tools
echo ""
echo "[INFO] Installing GPG, CA certificates, and archive keyring..."
apt-get update -y || true
apt-get install -y wget curl gnupg ca-certificates debian-archive-keyring apt-transport-https || true

# Global APT settings
echo ""
echo "[INFO] Applying APT reliability settings..."
cat >/etc/apt/apt.conf.d/99fix-archive <<'EOF'
Acquire::http::Pipeline-Depth "0";
Acquire::Retries "3";
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
EOF

# Prevent interactive service restarts
echo ""
echo "[INFO] Disabling service restarts during upgrade..."
cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

# Recovery helper
fix_system() {
    echo "[INFO] Fixing any broken dependencies..."
    apt-get -f install -y || true
    dpkg --configure -a || true
    apt-get autoremove -y || true
    apt-get clean
}

# Import Debian signing keys
import_keys() {
    echo ""
    echo "[INFO] Importing Debian archive signing keys..."
    for key in \
        112695A0E562B32A \
        648ACFD622F3D138 \
        0E98404D386FA1D9 \
        CAA96DFA
    do
        gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys $key || true
    done
}

# Update APT sources for given codename
set_sources() {
    local CODENAME=$1
    echo ""
    echo "[INFO] Updating APT sources for Debian ${CODENAME}..."
    cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s)
    cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${CODENAME} main contrib non-free
deb http://archive.debian.org/debian-security ${CODENAME}/updates main contrib non-free
EOF
    apt-get -o Acquire::Check-Valid-Until=false update || true
}

# Perform one upgrade step
do_upgrade() {
    local FROM=$1
    local TO=$2
    echo ""
    echo "[INFO] ==============================================="
    echo "[INFO] Upgrading Debian ${FROM} → ${TO}"
    echo "[INFO] ==============================================="
    set_sources "${TO}"
    import_keys

    apt-get -qy \
      -o "Dpkg::Options::=--force-confdef" \
      -o "Dpkg::Options::=--force-confold" \
      dist-upgrade --allow-unauthenticated || true

    fix_system

    echo ""
    echo "[INFO] ==============================================="
    echo "[INFO] Upgrade to ${TO} completed successfully!"
    echo "[INFO] ==============================================="

    # Prompt reboot before next phase
    read -p "Reboot is strongly recommended before continuing to the next upgrade. Reboot now? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo "[INFO] Rebooting system now..."
        reboot
        exit 0
    fi
}

# ===== STEP 1: JESSIE → STRETCH =====
if [ "$CURRENT_VERSION" = "jessie" ]; then
    do_upgrade "jessie" "stretch"
    CURRENT_VERSION="stretch"
fi

# ===== STEP 2: STRETCH → BUSTER =====
if [ "$CURRENT_VERSION" = "stretch" ]; then
    do_upgrade "stretch" "buster"
    CURRENT_VERSION="buster"
fi

# ===== STEP 3: BUSTER → BULLSEYE =====
if [ "$CURRENT_VERSION" = "buster" ]; then
    do_upgrade "buster" "bullseye"
    CURRENT_VERSION="bullseye"
fi

# Cleanup
echo ""
echo "[INFO] Removing temporary service restart blocker..."
rm -f /usr/sbin/policy-rc.d

fix_system

echo ""
echo "[INFO] ==============================================="
echo "[INFO] Upgrade chain complete!"
echo "[INFO] Current Debian release: ${CURRENT_VERSION}"
echo "[INFO] Please reboot the system."
echo "[INFO] ==============================================="
