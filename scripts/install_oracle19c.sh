#!/bin/bash
#
# install-oracle-19c.sh
# Simplified & hardened Oracle 19c installer (supports Amazon Linux / RHEL / CentOS / Ubuntu)
#
#  - Uses Oracle's canonical path: /u01/app/oracle/product/19.0.0/dbhome_1
#  - If you prefer /opt/oracle, script will create a symlink to /u01 location (non-destructive)
#  - Expects LINUX.X64_193000_db_home.zip in ./oracle-db/
#
set -euo pipefail

##########################
# Configuration
##########################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALLER_ZIP="${PROJECT_ROOT}/oracle-db/LINUX.X64_193000_db_home.zip"

# Use Oracle's expected default path (recommended)
ORACLE_BASE="/u01/app/oracle"
ORACLE_HOME="${ORACLE_BASE}/product/19.0.0/dbhome_1"
ORACLE_SID="ATGDB"
ORACLE_PDB="ATGPDB"
ORACLE_PWD="ATG_Admin123"
ORACLE_CHARACTERSET="AL32UTF8"
ORACLE_MEMORY="2048"

ORACLE_USER="oracle"
ORACLE_GROUP="oinstall"
DBA_GROUP="dba"

# Helper colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_status(){ echo -e "${GREEN}[OK]${NC} $1"; }
print_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err(){ echo -e "${RED}[ERROR]${NC} $1"; }

##########################
# Root check
##########################
if [ "$EUID" -ne 0 ]; then
  print_err "Please run as root: sudo $0"
  exit 1
fi

echo "Oracle 19c automated installer starting..."
echo "Installer ZIP expected at: $INSTALLER_ZIP"

##########################
# Check installer
##########################
if [ ! -f "$INSTALLER_ZIP" ]; then
  print_err "Installer not found: $INSTALLER_ZIP"
  echo "Download LINUX.X64_193000_db_home.zip from Oracle and place it in: ${PROJECT_ROOT}/oracle-db/"
  exit 1
fi
FILE_SIZE=$(stat -c%s "$INSTALLER_ZIP" 2>/dev/null || stat -f%z "$INSTALLER_ZIP" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 2500000000 ]; then
  print_warn "Installer size suspicious ($(numfmt --to=iec $FILE_SIZE)). Expected ~2.9GB"
fi
print_status "Installer present."

##########################
# OS detection + prerequisites
##########################
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="$ID"
else
  OS_ID="unknown"
fi

echo "Detected OS: $OS_ID"

install_packages_rhel() {
  dnf install -y bc binutils elfutils-libelf elfutils-libelf-devel fontconfig-devel \
    glibc glibc-devel glibc-headers gcc gcc-c++ ksh libaio libaio-devel libX11 \
    libXau libXi libXtst libXrender libXrender-devel libgcc libstdc++ libstdc++-devel \
    libnsl libnsl2 libxcrypt-compat make net-tools nfs-utils policycoreutils \
    policycoreutils-python-utils smartmontools sysstat unzip which tar gzip numactl-libs || true
}

install_packages_debian() {
  apt-get update -y
  apt-get install -y bc binutils libelf-dev build-essential ksh libaio1 libaio-dev \
    unzip sysstat net-tools which tar gzip numactl
}

case "$OS_ID" in
  rhel|centos|ol|amzn|fedora)
    echo "[Prereqs] Installing packages for RHEL-family..."
    install_packages_rhel
    ;;
  ubuntu|debian)
    echo "[Prereqs] Installing packages for Debian-family..."
    install_packages_debian
    ;;
  *)
    print_warn "Unknown OS ($OS_ID). Please manually install Oracle prerequisites (libaio, ksh, gcc, etc.)"
    ;;
esac
print_status "Prerequisites installed (or assumed present)."

##########################
# Create groups & user
##########################
getent group "$ORACLE_GROUP" >/dev/null 2>&1 || groupadd -g 54321 "$ORACLE_GROUP"
getent group "$DBA_GROUP" >/dev/null 2>&1 || groupadd -g 54322 "$DBA_GROUP"

# create other standard groups used by Oracle
for g in oper backupdba dgdba kmdba racdba; do
  getent group "$g" >/dev/null 2>&1 || groupadd -g $((54322 + ${RANDOM:0:2} )) "$g" || true
done

if ! id "$ORACLE_USER" >/dev/null 2>&1; then
  useradd -u 54321 -g "$ORACLE_GROUP" -G "$DBA_GROUP",oper,backupdba,dgdba,kmdba,racdba -d "/home/$ORACLE_USER" -m "$ORACLE_USER"
  echo "oracle:oracle123" | chpasswd || true
  print_status "Created user $ORACLE_USER (password oracle123). Change password after install!"
else
  print_status "User $ORACLE_USER already exists."
  usermod -a -G "$DBA_GROUP",oper,backupdba,dgdba,kmdba,racdba "$ORACLE_USER" || true
fi

##########################
# Create directory layout (canonical /u01)
##########################
echo "[Dirs] Creating $ORACLE_BASE and children..."
mkdir -p "$ORACLE_HOME"
mkdir -p "$ORACLE_BASE/oradata"
mkdir -p "$ORACLE_BASE/oraInventory"
mkdir -p "$ORACLE_BASE/scripts"
mkdir -p "$ORACLE_BASE/recovery_area"
chown -R "$ORACLE_USER:$ORACLE_GROUP" "$(dirname "$ORACLE_BASE")" || chown -R "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_BASE" || true
chmod -R 775 "$ORACLE_BASE" || true
print_status "Directories created."

##########################
# If you previously used /opt/oracle, create symlink to canonical path
##########################
if [ -d "/opt/oracle" ] && [ ! -L "/u01/app/oracle" ]; then
  print_warn "/opt/oracle exists. Creating symlink /u01/app/oracle -> /opt/oracle (non-destructive)."
  mkdir -p /u01/app
  ln -sfn /opt/oracle /u01/app/oracle
  chown -h "$ORACLE_USER:$ORACLE_GROUP" /u01/app/oracle || true
  print_status "Symlink created: /u01/app/oracle -> /opt/oracle"
fi

##########################
# Kernel / limits - append safely
##########################
echo "[Kernel] Applying safe kernel & limits (appending markers)"
SYSCTL_MARKER="# Oracle 19c - managed by install-oracle-19c.sh"
if ! grep -q "$SYSCTL_MARKER" /etc/sysctl.conf 2>/dev/null; then
  cat >> /etc/sysctl.conf <<EOF

$SYSCTL_MARKER
fs.aio-max-nr = 1048576
fs.file-max = 6815744
kernel.shmall = 2097152
kernel.shmmax = 8589934592
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
EOF
  sysctl -p >/dev/null 2>&1 || true
fi

LIMITS_MARKER="# Oracle 19c Limits - managed by install-oracle-19c.sh"
if ! grep -q "$LIMITS_MARKER" /etc/security/limits.conf 2>/dev/null; then
  cat >> /etc/security/limits.conf <<EOF

$LIMITS_MARKER
oracle soft nproc 2047
oracle hard nproc 16384
oracle soft nofile 1024
oracle hard nofile 65536
oracle soft stack 10240
oracle hard stack 32768
oracle soft memlock unlimited
oracle hard memlock unlimited
EOF
fi
print_status "Kernel parameters and limits updated (if not present)."

##########################
# Environment setup
##########################
cat > "/home/$ORACLE_USER/.bash_profile" <<EOF
# Oracle 19c Environment (auto-created)
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib:\$LD_LIBRARY_PATH
export CLASSPATH=\$ORACLE_HOME/jlib:\$ORACLE_HOME/rdbms/jlib
export NLS_LANG=AMERICAN_AMERICA.$ORACLE_CHARACTERSET
export TNS_ADMIN=\$ORACLE_HOME/network/admin
alias sqlplus='rlwrap sqlplus' 2>/dev/null || true
alias rman='rlwrap rman' 2>/dev/null || true
EOF
chown "$ORACLE_USER:$ORACLE_GROUP" "/home/$ORACLE_USER/.bash_profile" || true

cat > /etc/profile.d/oracle.sh <<EOF
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
EOF
chmod 644 /etc/profile.d/oracle.sh || true

cat > /etc/oraInst.loc <<EOF
inventory_loc=$ORACLE_BASE/oraInventory
inst_group=$ORACLE_GROUP
EOF
chmod 644 /etc/oraInst.loc || true

print_status "Environment and oraInst.loc configured."

##########################
# Extract installer to ORACLE_HOME
##########################
echo "[Install] Extracting installer to $ORACLE_HOME (this may take a while)..."
# ensure ownership and permissions
chown -R "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_HOME" || true
# Unzip into ORACLE_HOME
unzip -oq "$INSTALLER_ZIP" -d "$ORACLE_HOME"
chown -R "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_HOME"
print_status "Installer extracted."

##########################
# Create response file and installer runner
##########################
cat > "$ORACLE_BASE/db_install.rsp" <<EOF
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0
oracle.install.option=INSTALL_DB_SWONLY
UNIX_GROUP_NAME=$ORACLE_GROUP
INVENTORY_LOCATION=$ORACLE_BASE/oraInventory
ORACLE_HOME=$ORACLE_HOME
ORACLE_BASE=$ORACLE_BASE
oracle.install.db.InstallEdition=EE
oracle.install.db.OSDBA_GROUP=$DBA_GROUP
oracle.install.db.OSOPER_GROUP=oper
oracle.install.db.OSBACKUPDBA_GROUP=backupdba
oracle.install.db.OSDGDBA_GROUP=dgdba
oracle.install.db.OSKMDBA_GROUP=kmdba
oracle.install.db.OSRACDBA_GROUP=racdba
oracle.install.db.rootconfig.executeRootScript=false
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
DECLINE_SECURITY_UPDATES=true
EOF
chown "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_BASE/db_install.rsp" || true

cat > "$ORACLE_BASE/scripts/run_installer.sh" <<'INSTALLER_SCRIPT'
#!/bin/bash
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export CV_ASSUME_DISTID=OEL8.1
export PATH=$ORACLE_HOME/bin:$PATH

cd "$ORACLE_HOME"
# run the runInstaller in silent mode; ignore prereq failures if any
./runInstaller -silent \
    -responseFile /u01/app/oracle/db_install.rsp \
    -ignorePrereqFailure \
    -waitforcompletion || true
INSTALLER_SCRIPT
chmod +x "$ORACLE_BASE/scripts/run_installer.sh"
chown "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_BASE/scripts/run_installer.sh"

echo "[Install] Running Oracle installer as $ORACLE_USER (silent). This may take 10-40 minutes."
# run as oracle user
sudo -u "$ORACLE_USER" bash -lc "$ORACLE_BASE/scripts/run_installer.sh" || true

# After runInstaller completes, some root scripts need to be run. The installer usually indicates their paths.
# Common locations:
if [ -f "$ORACLE_BASE/oraInventory/orainstRoot.sh" ]; then
  echo "[Install] Running orainstRoot.sh"
  "$ORACLE_BASE/oraInventory/orainstRoot.sh" || true
fi
if [ -f "$ORACLE_HOME/root.sh" ]; then
  echo "[Install] Running $ORACLE_HOME/root.sh"
  "$ORACLE_HOME/root.sh" || true
fi
print_status "Oracle software installed (or runInstaller completed)."

##########################
# Create DBCA create script and run it as oracle user
##########################
cat > "$ORACLE_BASE/scripts/create_db.sh" <<'DBSCRIPT'
#!/bin/bash
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export ORACLE_SID=ATGDB
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

# Create a non-CDB (match your original intention). If you want a CDB, change -createAsContainerDatabase true and add PDB params.
dbca -silent -createDatabase \
    -templateName General_Purpose.dbc \
    -gdbName ATGDB \
    -sid ATGDB \
    -createAsContainerDatabase false \
    -emConfiguration NONE \
    -datafileDestination /u01/app/oracle/oradata \
    -recoveryAreaDestination /u01/app/oracle/recovery_area \
    -storageType FS \
    -characterSet AL32UTF8 \
    -totalMemory 2048 \
    -sysPassword ATG_Admin123 \
    -systemPassword ATG_Admin123 || exit 1
DBSCRIPT

chmod +x "$ORACLE_BASE/scripts/create_db.sh"
chown "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_BASE/scripts/create_db.sh"

echo "[DBCA] Creating database (dbca). This may take 10-30 minutes..."
sudo -u "$ORACLE_USER" bash -lc "$ORACLE_BASE/scripts/create_db.sh"
print_status "Database creation step finished."

##########################
# Listener (tns) setup
##########################
mkdir -p "$ORACLE_HOME/network/admin"
cat > "$ORACLE_HOME/network/admin/listener.ora" <<EOF
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    )
  )

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = $ORACLE_SID)
      (ORACLE_HOME = $ORACLE_HOME)
      (SID_NAME = $ORACLE_SID)
    )
  )

ADR_BASE_LISTENER = $ORACLE_BASE
EOF

cat > "$ORACLE_HOME/network/admin/tnsnames.ora" <<EOF
$ORACLE_SID =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $ORACLE_SID)
    )
  )

LISTENER_$ORACLE_SID =
  (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
EOF

chown -R "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_HOME/network/admin"
print_status "Listener and tnsnames configured."

# Listener start script
cat > "$ORACLE_BASE/scripts/start_listener.sh" <<'LSNR_SCRIPT'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
lsnrctl stop || true
lsnrctl start
LSNR_SCRIPT
chmod +x "$ORACLE_BASE/scripts/start_listener.sh"
chown "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_BASE/scripts/start_listener.sh"
sudo -u "$ORACLE_USER" bash -lc "$ORACLE_BASE/scripts/start_listener.sh" || true
print_status "Listener started (if possible)."

##########################
# Startup / Shutdown scripts
##########################
cat > "$ORACLE_BASE/scripts/start_db.sh" <<'STARTDB'
#!/bin/bash
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export ORACLE_SID=ATGDB
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

echo "Starting Listener..."
lsnrctl start || true

echo "Starting Database..."
sqlplus / as sysdba <<SQL
startup
exit
SQL
echo "Database start requested."
STARTDB

cat > "$ORACLE_BASE/scripts/stop_db.sh" <<'STOPDB'
#!/bin/bash
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export ORACLE_SID=ATGDB
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

echo "Stopping Database..."
sqlplus / as sysdba <<SQL
shutdown immediate
exit
SQL

echo "Stopping Listener..."
lsnrctl stop || true
STOPDB

chmod +x "$ORACLE_BASE/scripts/"*.sh
chown -R "$ORACLE_USER:$ORACLE_GROUP" "$ORACLE_BASE/scripts"

##########################
# systemd service
##########################
cat > /etc/systemd/system/oracle.service <<EOF
[Unit]
Description=Oracle Database 19c
After=network.target

[Service]
Type=forking
User=$ORACLE_USER
Group=$ORACLE_GROUP
Environment="ORACLE_BASE=$ORACLE_BASE"
Environment="ORACLE_HOME=$ORACLE_HOME"
Environment="ORACLE_SID=$ORACLE_SID"
ExecStart=$ORACLE_BASE/scripts/start_db.sh
ExecStop=$ORACLE_BASE/scripts/stop_db.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable oracle.service || true
print_status "systemd service created and enabled."

##########################
# Summary
##########################
cat <<EOF

=============================================
 ORACLE 19c INSTALL SCRIPT FINISHED (ATTEMPT)
=============================================
ORACLE_BASE: $ORACLE_BASE
ORACLE_HOME: $ORACLE_HOME
ORACLE_SID:  $ORACLE_SID
SYS Password: $ORACLE_PWD
JDBC URL: jdbc:oracle:thin:@localhost:1521:$ORACLE_SID

To start:
  sudo systemctl start oracle
  sudo journalctl -u oracle -f

Manual start:
  sudo -u $ORACLE_USER $ORACLE_BASE/scripts/start_db.sh

Notes:
 - You MUST place LINUX.X64_193000_db_home.zip into ${PROJECT_ROOT}/oracle-db/ before running.
 - If installer still references /u01 hard-coded paths, symlink /opt/oracle -> /u01/app/oracle or vice-versa as needed.
 - For RHEL/CentOS, consider installing oracle-database-preinstall-* RPM for groups/limits (optional).
 - Installer may still require manual root script execution; check runInstaller output for script paths.

EOF

exit 0
