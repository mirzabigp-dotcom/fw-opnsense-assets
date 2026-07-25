#!/bin/sh

set -eu

# configureopnsense-v2.sh
# Improvements over v1:
#   - Named variables for all positional parameters (readability)
#   - Input validation with usage message and role check
#   - Timestamp-based logging via log() helper
#   - Dynamic Python binary detection (no hardcoded python3.11)
#   - python3 used for get_nic_gw.py before the symlink exists
#   - Shared fetch_gw_helper() eliminates duplicated code across branches
#   - All variables properly quoted to prevent word-splitting
#   - Heredocs use quoted delimiter ('EOL') to prevent unintended expansion
#   - Removed stale commented-out dead code
#   - tar without -v flag to reduce cloud-init log noise
#   - WebGUI hook written via heredoc instead of fragile echo chains
#   - Static ARP rc.conf entries written as a single block

# ── Parameters ────────────────────────────────────────────────────────────────
# $1 = OPNScriptURI      Base URI for fetching config/scripts
# $2 = OpnVersion        OPNsense version to install
# $3 = WALinuxVersion    WALinuxAgent version to install
# $4 = Role              VM role: Primary | Secondary | TwoNics
# $5 = TrustedSubnet     Trusted NIC subnet prefix (for GW resolution)
# $6 = WindowsVMSubnet   Windows Management VM subnet prefix (for routing)
# $7 = ELBVip            External Load Balancer VIP (Primary only)
# $8 = SecondaryIP       Private IP of Secondary OPNsense server (Primary only)

OPN_SCRIPT_URI="$1"
OPN_VERSION="$2"
WA_LINUX_VERSION="$3"
ROLE="$4"
TRUSTED_SUBNET="${5:-}"
WINDOWS_VM_SUBNET="${6:-}"
ELB_VIP="${7:-}"
SECONDARY_IP="${8:-}"

# OPNsense 26.7 uses FreeBSD 15 packages, while the supported bootstrap source
# image for Azure is stock FreeBSD 14.4. Bootstrap the matching 26.1 release
# first, then let OPNsense perform its supported major upgrade after reboot.
BOOTSTRAP_VERSION="$OPN_VERSION"
UPGRADE_VERSION=""
if [ "$OPN_VERSION" = "26.7" ]; then
    BOOTSTRAP_VERSION="26.1"
    UPGRADE_VERSION="$OPN_VERSION"
fi

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ── Input Validation ──────────────────────────────────────────────────────────
if [ -z "$OPN_SCRIPT_URI" ] || [ -z "$OPN_VERSION" ] || [ -z "$WA_LINUX_VERSION" ] || [ -z "$ROLE" ]; then
    echo "ERROR: Missing required parameters."
    echo "Usage: $0 <OPNScriptURI> <OpnVersion> <WALinuxVersion> <Primary|Secondary|TwoNics> <TrustedSubnet> <WindowsVMSubnet> [ELBVip] [SecondaryIP]"
    exit 1
fi

case "$ROLE" in
    Primary|Secondary|TwoNics) ;;
    *)
        echo "ERROR: Invalid role '${ROLE}'. Must be Primary, Secondary, or TwoNics."
        exit 1
        ;;
esac

# ── Helper: Resolve trusted NIC gateway IP ────────────────────────────────────
# Uses python3 directly since the python symlink is created later in this script
fetch_gw_ip() {
    fetch -q "${OPN_SCRIPT_URI}get_nic_gw.py"
    PYTHON_BIN=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
    if [ -z "$PYTHON_BIN" ]; then
        echo "ERROR: No Python interpreter found to run get_nic_gw.py." >&2
        exit 1
    fi
    "$PYTHON_BIN" get_nic_gw.py "$TRUSTED_SUBNET"
}

# ── Apply OPNsense Configuration XML ─────────────────────────────────────────
log "Configuring OPNsense role: ${ROLE}"

if [ "$ROLE" = "Primary" ]; then
    fetch -q "${OPN_SCRIPT_URI}config-active-active-primary.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" config-active-active-primary.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_${WINDOWS_VM_SUBNET}_" config-active-active-primary.xml
    sed -i "" "s/www.www.www.www/${ELB_VIP}/" config-active-active-primary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/${SECONDARY_IP}/" config-active-active-primary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Primary<\/hostname>/" config-active-active-primary.xml
    cp config-active-active-primary.xml /usr/local/etc/config.xml

elif [ "$ROLE" = "Secondary" ]; then
    fetch -q "${OPN_SCRIPT_URI}config-active-active-secondary.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" config-active-active-secondary.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_${WINDOWS_VM_SUBNET}_" config-active-active-secondary.xml
    sed -i "" "s/www.www.www.www/${ELB_VIP}/" config-active-active-secondary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Secondary<\/hostname>/" config-active-active-secondary.xml
    cp config-active-active-secondary.xml /usr/local/etc/config.xml

elif [ "$ROLE" = "TwoNics" ]; then
    fetch -q "${OPN_SCRIPT_URI}config.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" config.xml
    sed -i "" "s_zzz.zzz.zzz.zzz_${WINDOWS_VM_SUBNET}_" config.xml
    cp config.xml /usr/local/etc/config.xml
fi

# ── OPNsense Bootstrap ────────────────────────────────────────────────────────
log "Downloading OPNsense bootstrap script..."
fetch -q https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in

log "Enabling root SSH login..."
sed -i "" 's/#PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

# Defer the bootstrap reboot until every Azure integration and upgrade hook has
# been installed. Keep fail-fast behavior so Azure reports installation errors.
log "Patching bootstrap script..."
sed -i "" "s/^[[:space:]]*reboot$/true/" opnsense-bootstrap.sh.in

INSTALLED_OPNSENSE_VERSION=""
if [ -f /usr/local/opnsense/version/pkgs ]; then
    INSTALLED_OPNSENSE_VERSION=$(cat /usr/local/opnsense/version/pkgs)
fi

case "$INSTALLED_OPNSENSE_VERSION" in
"$OPN_VERSION"|"$OPN_VERSION".*)
    log "OPNsense ${OPN_VERSION} is already installed; continuing provisioning."
    UPGRADE_VERSION=""
    ;;
"$BOOTSTRAP_VERSION"|"$BOOTSTRAP_VERSION".*)
    log "OPNsense ${BOOTSTRAP_VERSION} bootstrap is already complete; continuing provisioning."
    ;;
*)
    log "Running OPNsense bootstrap (version: ${BOOTSTRAP_VERSION})..."
    sh ./opnsense-bootstrap.sh.in -y -r "$BOOTSTRAP_VERSION"
    ;;
esac

# ── Azure Integration Installer ───────────────────────────────────────────────
# A major OPNsense upgrade replaces the base system and removes packages from
# the stock FreeBSD image. Keep the installer outside pkg-managed paths so it
# survives that transition and can restore waagent and optional packages after
# the final reboot. VM provisioning itself uses cloud-init, not VM extensions.
cat > /usr/local/sbin/install-azure-integration.sh <<'EOL'
#!/bin/sh
set -eu

opn_script_uri="$1"
wa_linux_version="$2"
work_dir="/tmp/waagent-install"

rm -rf "$work_dir"
mkdir -p "$work_dir"
cd "$work_dir"

python_package_version=$(python3 -c 'import sys; print("%d%d" % sys.version_info[:2])')
pkg install -y "py${python_package_version}-setuptools" bash os-frr

fetch -q -o waagent.tar.gz "https://github.com/Azure/WALinuxAgent/archive/refs/tags/v${wa_linux_version}.tar.gz"
tar -xzf waagent.tar.gz
cd "WALinuxAgent-${wa_linux_version}"
python3 setup.py install --register-service --lnx-distro=freebsd --force

python3_bin=$(find /usr/local/bin -maxdepth 1 -type f -name 'python3.*' | sort -V | tail -1)
if [ -n "$python3_bin" ]; then
    ln -sf "$python3_bin" /usr/local/bin/python
fi

mkdir -p /usr/local/etc
cp /etc/waagent.conf /usr/local/etc/waagent.conf
sed -i "" 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/' /usr/local/etc/waagent.conf
sysrc waagent_enable=YES

fetch -q -o /tmp/actions_waagent.conf "${opn_script_uri}actions_waagent.conf"
cp /tmp/actions_waagent.conf /usr/local/opnsense/service/conf/actions.d/actions_waagent.conf

service waagent restart || service waagent start
rm -rf "$work_dir"
EOL
chmod +x /usr/local/sbin/install-azure-integration.sh

# ── Azure Route Fix ───────────────────────────────────────────────────────────
# Delete the 168.63.129.16 host route that Azure injects at boot; OPNsense
# uses a static ARP entry instead (see below) so the route is not needed and
# can interfere with traffic.
log "Adding startup hook to remove spurious Azure route..."
cat > /usr/local/etc/rc.syshook.d/start/22-remoteroute <<'EOL'
#!/bin/sh
route delete 168.63.129.16
EOL
chmod +x /usr/local/etc/rc.syshook.d/start/22-remoteroute

# ── Azure Load Balancer Probe / Internal VIP ──────────────────────────────────
# OPNsense must respond to ARP requests for 168.63.129.16 so that:
#   1. Azure health probes from the load balancer reach the VM
#   2. Azure platform services (IMDS, waagent) remain reachable
log "Configuring static ARP entry for Azure Internal VIP (168.63.129.16)..."
{
    echo "# Azure Internal VIP - required for LB health probes and platform services"
    echo 'static_arp_pairs="azvip"'
    echo 'static_arp_azvip="168.63.129.16 12:34:56:78:9a:bc"'
} >> /etc/rc.conf

service static_arp start
echo 'service static_arp start' >> /usr/local/etc/rc.syshook.d/start/20-freebsd

# ── WebGUI Certificate Renewal ────────────────────────────────────────────────
# One-time boot hook: renews the self-signed WebGUI certificate after OPNsense
# first boots, then removes itself so it does not run on subsequent reboots.
log "Setting up one-time WebGUI certificate renewal hook..."
cat > /usr/local/etc/rc.syshook.d/start/94-restartwebgui <<'EOL'
#!/bin/sh
configctl webgui restart renew
rm /usr/local/etc/rc.syshook.d/start/94-restartwebgui
EOL
chmod +x /usr/local/etc/rc.syshook.d/start/94-restartwebgui

if [ -n "$UPGRADE_VERSION" ]; then
    # The temporary Azure bootstrap extension is removed by the workflow before
    # this delayed reboot. Its legacy shim requires bash for clean uninstall.
    log "Installing bash for temporary extension cleanup..."
    pkg install -y bash

    log "Scheduling Azure integration repair after the major upgrade..."
    cat > /usr/local/etc/rc.syshook.d/start/99-azure-integration <<EOL
#!/bin/sh
installed_version=\$(cat /usr/local/opnsense/version/pkgs 2>/dev/null || true)
case "\$installed_version" in
"${UPGRADE_VERSION}"|"${UPGRADE_VERSION}".*)
    /usr/local/sbin/install-azure-integration.sh '${OPN_SCRIPT_URI}' '${WA_LINUX_VERSION}' >> /var/log/azure-integration.log 2>&1
    rm -f /usr/local/etc/rc.syshook.d/start/99-azure-integration
    ;;
esac
EOL
    chmod +x /usr/local/etc/rc.syshook.d/start/99-azure-integration

    log "Scheduling OPNsense major upgrade to ${UPGRADE_VERSION} after first boot..."
    cat > /usr/local/etc/rc.syshook.d/start/98-major-upgrade <<EOL
#!/bin/sh
rm -f /usr/local/etc/rc.syshook.d/start/98-major-upgrade
/usr/local/etc/rc.firmware upgrade ${UPGRADE_VERSION}
EOL
    chmod +x /usr/local/etc/rc.syshook.d/start/98-major-upgrade
    log "OPNsense ${BOOTSTRAP_VERSION} provisioning complete. The system will reboot, upgrade to ${UPGRADE_VERSION}, and reboot again."
else
    log "Installing Azure integration..."
    /usr/local/sbin/install-azure-integration.sh "$OPN_SCRIPT_URI" "$WA_LINUX_VERSION"
    log "OPNsense provisioning complete. System will reboot in approximately 1 minute."
fi

shutdown -r +5
