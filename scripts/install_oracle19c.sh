#!/bin/bash

#############################################################
# Oracle Database 19c Installation Script                   #
# For Amazon Linux 2023 / RHEL 8+ / CentOS 8+              #
# Much better compatibility than 12c!                       #
#############################################################

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " Oracle Database 19c Installation           "
echo "============================================="

# -----------------------------
# Configuration
# -----------------------------
ORACLE_BASE="/opt/oracle"
ORACLE_HOME="/opt/oracle/product/19c/dbhome_1"
ORACLE_SID="ATGDB"
ORACLE_PDB="ATGPDB"
ORACLE_PWD="ATG_Admin123"
ORACLE_CHARACTERSET="AL32UTF8"
ORACLE_MEMORY="2048"

ORACLE_USER="oracle"
ORACLE_GROUP="oinstall"
DBA_GROUP="dba"

# Oracle 19c installer - download from Oracle website
# File: LINUX.X64_193000_db_home.zip (~2.9GB)
INSTALLER_ZIP="${PROJECT_ROOT}/oracle-db/LINUX.X64_193000_db_home.zip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------
# Check if running as root
# -----------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root: sudo $0"
        exit 1
    fi
}

# -----------------------------
# Check installer file
# -----------------------------
check_installer() {
    echo ""
    echo "[1/9] Checking Oracle 19c installer..."
    
    if [ ! -f "$INSTALLER_ZIP" ]; then
        print_error "Oracle 19c installer not found: $INSTALLER_ZIP"
        echo ""
        echo "Please download Oracle Database 19c from:"
        echo "  https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html"
        echo ""
        echo "Download: LINUX.X64_193000_db_home.zip (~2.9GB)"
        echo "Then copy it to: ${PROJECT_ROOT}/oracle-db/"
        exit 1
    fi
    
    FILE_SIZE=$(stat -c%s "$INSTALLER_ZIP" 2>/dev/null || stat -f%z "$INSTALLER_ZIP" 2>/dev/null)
    if [ "$FILE_SIZE" -lt 2500000000 ]; then
        print_warning "Installer file seems small ($(numfmt --to=iec $FILE_SIZE)). Expected ~2.9GB"
    fi
    
    print_status "Oracle 19c installer found: $(basename $INSTALLER_ZIP)"
}

# -----------------------------
# Install prerequisites
# -----------------------------
install_prerequisites() {
    echo ""
    echo "[2/9] Installing prerequisites..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi
    
    case $OS in
        amzn|rhel|centos|fedora|ol)
            dnf install -y \
                bc \
                binutils \
                elfutils-libelf \
                elfutils-libelf-devel \
                fontconfig-devel \
                glibc \
                glibc-devel \
                glibc-headers \
                gcc \
                gcc-c++ \
                ksh \
                libaio \
                libaio-devel \
                libX11 \
                libXau \
                libXi \
                libXtst \
                libXrender \
                libXrender-devel \
                libgcc \
                libstdc++ \
                libstdc++-devel \
                libnsl \
                libnsl2 \
                libxcrypt-compat \
                make \
                net-tools \
                nfs-utils \
                policycoreutils \
                policycoreutils-python-utils \
                smartmontools \
                sysstat \
                unzip \
                --allowerasing 2>/dev/null || true
            ;;
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                bc binutils elfutils libelf-dev build-essential \
                ksh libaio1 libaio-dev unzip sysstat net-tools
            ;;
    esac
    
    print_status "Prerequisites installed."
}

# -----------------------------
# Create Oracle user and groups
# -----------------------------
create_oracle_user() {
    echo ""
    echo "[3/9] Creating Oracle user and groups..."
    
    # Create groups if they don't exist
    getent group $ORACLE_GROUP > /dev/null 2>&1 || groupadd -g 54321 $ORACLE_GROUP
    getent group $DBA_GROUP > /dev/null 2>&1 || groupadd -g 54322 $DBA_GROUP
    getent group oper > /dev/null 2>&1 || groupadd -g 54323 oper
    getent group backupdba > /dev/null 2>&1 || groupadd -g 54324 backupdba
    getent group dgdba > /dev/null 2>&1 || groupadd -g 54325 dgdba
    getent group kmdba > /dev/null 2>&1 || groupadd -g 54326 kmdba
    getent group racdba > /dev/null 2>&1 || groupadd -g 54327 racdba
    
    # Create oracle user if doesn't exist
    if ! id "$ORACLE_USER" &>/dev/null; then
        useradd -u 54321 -g $ORACLE_GROUP \
            -G $DBA_GROUP,oper,backupdba,dgdba,kmdba,racdba \
            -d /home/$ORACLE_USER -m $ORACLE_USER
        echo "oracle:oracle123" | chpasswd
        print_status "Oracle user created (password: oracle123)"
    else
        print_status "Oracle user already exists."
        usermod -a -G $DBA_GROUP,oper,backupdba,dgdba,kmdba,racdba $ORACLE_USER 2>/dev/null || true
    fi
}

# -----------------------------
# Create directory structure
# -----------------------------
create_directories() {
    echo ""
    echo "[4/9] Creating Oracle directories..."
    
    mkdir -p $ORACLE_HOME
    mkdir -p $ORACLE_BASE/oradata
    mkdir -p $ORACLE_BASE/oraInventory
    mkdir -p $ORACLE_BASE/scripts
    mkdir -p $ORACLE_BASE/recovery_area
    
    chown -R $ORACLE_USER:$ORACLE_GROUP $ORACLE_BASE
    chmod -R 775 $ORACLE_BASE
    
    print_status "Directories created."
}

# -----------------------------
# Configure kernel parameters
# -----------------------------
configure_kernel() {
    echo ""
    echo "[5/9] Configuring kernel parameters..."
    
    # Backup existing sysctl.conf
    cp /etc/sysctl.conf /etc/sysctl.conf.bak 2>/dev/null || true
    
    # Add Oracle kernel parameters if not already present
    if ! grep -q "# Oracle 19c" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf << 'EOF'

# Oracle 19c Kernel Parameters
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
    fi
    
    # Apply kernel parameters
    sysctl -p 2>/dev/null || true
    
    # Configure limits for oracle user
    if ! grep -q "# Oracle 19c Limits" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf << 'EOF'

# Oracle 19c Limits
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
    
    print_status "Kernel parameters configured."
}

# -----------------------------
# Setup Oracle environment
# -----------------------------
setup_environment() {
    echo ""
    echo "[6/9] Setting up Oracle environment..."
    
    # Create oracle user profile
    cat > /home/$ORACLE_USER/.bash_profile << EOF
# Oracle 19c Environment
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib:\$LD_LIBRARY_PATH
export CLASSPATH=\$ORACLE_HOME/jlib:\$ORACLE_HOME/rdbms/jlib
export NLS_LANG=AMERICAN_AMERICA.${ORACLE_CHARACTERSET}
export TNS_ADMIN=\$ORACLE_HOME/network/admin

# Aliases
alias sqlplus='rlwrap sqlplus'
alias rman='rlwrap rman'
EOF

    chown $ORACLE_USER:$ORACLE_GROUP /home/$ORACLE_USER/.bash_profile
    
    # Create system-wide profile
    cat > /etc/profile.d/oracle.sh << EOF
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
EOF

    # Create oraInst.loc
    cat > /etc/oraInst.loc << EOF
inventory_loc=$ORACLE_BASE/oraInventory
inst_group=$ORACLE_GROUP
EOF
    chmod 644 /etc/oraInst.loc

    print_status "Oracle environment configured."
}

# -----------------------------
# Extract and install Oracle 19c
# -----------------------------
install_oracle() {
    echo ""
    echo "[7/9] Installing Oracle Database 19c..."
    echo "This may take 15-30 minutes..."
    
    # Check if already installed
    if [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        print_status "Oracle already installed at $ORACLE_HOME"
        return 0
    fi
    
    # Oracle 19c installs differently - extract directly to ORACLE_HOME
    echo "Extracting Oracle 19c installer to ORACLE_HOME..."
    cd $ORACLE_HOME
    unzip -oq "$INSTALLER_ZIP"
    chown -R $ORACLE_USER:$ORACLE_GROUP $ORACLE_HOME
    
    # Create response file for Oracle 19c
    cat > $ORACLE_BASE/db_install.rsp << EOF
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

    chown $ORACLE_USER:$ORACLE_GROUP $ORACLE_BASE/db_install.rsp
    
    # Create installer script
    cat > $ORACLE_BASE/scripts/run_installer.sh << 'INSTALLER_SCRIPT'
#!/bin/bash
export ORACLE_BASE=/opt/oracle
export ORACLE_HOME=/opt/oracle/product/19c/dbhome_1
export CV_ASSUME_DISTID=OEL8.1
export PATH=$ORACLE_HOME/bin:$PATH

cd $ORACLE_HOME
./runInstaller -silent \
    -responseFile /opt/oracle/db_install.rsp \
    -ignorePrereqFailure \
    -waitforcompletion
INSTALLER_SCRIPT

    chmod +x $ORACLE_BASE/scripts/run_installer.sh
    chown $ORACLE_USER:$ORACLE_GROUP $ORACLE_BASE/scripts/run_installer.sh
    
    # Run installer as oracle user
    echo "Running Oracle 19c installer (silent mode)..."
    sudo -u $ORACLE_USER $ORACLE_BASE/scripts/run_installer.sh || true
    
    # Run root scripts
    echo "Running root scripts..."
    if [ -f "$ORACLE_BASE/oraInventory/orainstRoot.sh" ]; then
        $ORACLE_BASE/oraInventory/orainstRoot.sh
    fi
    if [ -f "$ORACLE_HOME/root.sh" ]; then
        $ORACLE_HOME/root.sh
    fi
    
    print_status "Oracle Database 19c software installed."
}

# -----------------------------
# Create database
# -----------------------------
create_database() {
    echo ""
    echo "[8/9] Creating Oracle Database..."
    echo "This may take 15-30 minutes..."
    
    # Check if database already exists
    if [ -d "$ORACLE_BASE/oradata/$ORACLE_SID" ]; then
        print_status "Database $ORACLE_SID already exists."
        return 0
    fi
    
    # Create database script
    cat > $ORACLE_BASE/scripts/create_db.sh << 'DBSCRIPT'
#!/bin/bash
export ORACLE_BASE=/opt/oracle
export ORACLE_HOME=/opt/oracle/product/19c/dbhome_1
export ORACLE_SID=ATGDB
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

dbca -silent -createDatabase \
    -templateName General_Purpose.dbc \
    -gdbName ATGDB \
    -sid ATGDB \
    -createAsContainerDatabase false \
    -emConfiguration NONE \
    -datafileDestination /opt/oracle/oradata \
    -recoveryAreaDestination /opt/oracle/recovery_area \
    -storageType FS \
    -characterSet AL32UTF8 \
    -totalMemory 2048 \
    -sysPassword ATG_Admin123 \
    -systemPassword ATG_Admin123
DBSCRIPT

    chmod +x $ORACLE_BASE/scripts/create_db.sh
    chown $ORACLE_USER:$ORACLE_GROUP $ORACLE_BASE/scripts/create_db.sh
    
    # Run database creation as oracle user
    sudo -u $ORACLE_USER $ORACLE_BASE/scripts/create_db.sh
    
    print_status "Database $ORACLE_SID created."
}

# -----------------------------
# Configure and start listener
# -----------------------------
configure_listener() {
    echo ""
    echo "[9/9] Configuring Oracle Listener..."
    
    # Create listener.ora
    mkdir -p $ORACLE_HOME/network/admin
    cat > $ORACLE_HOME/network/admin/listener.ora << EOF
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

    # Create tnsnames.ora
    cat > $ORACLE_HOME/network/admin/tnsnames.ora << EOF
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

    chown -R $ORACLE_USER:$ORACLE_GROUP $ORACLE_HOME/network/admin/
    
    # Create listener start script
    cat > $ORACLE_BASE/scripts/start_listener.sh << 'LSNR_SCRIPT'
#!/bin/bash
export ORACLE_HOME=/opt/oracle/product/19c/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
lsnrctl stop 2>/dev/null || true
lsnrctl start
LSNR_SCRIPT

    chmod +x $ORACLE_BASE/scripts/start_listener.sh
    chown $ORACLE_USER:$ORACLE_GROUP $ORACLE_BASE/scripts/start_listener.sh
    
    # Start listener
    sudo -u $ORACLE_USER $ORACLE_BASE/scripts/start_listener.sh
    
    print_status "Listener configured and started."
}

# -----------------------------
# Create startup/shutdown scripts
# -----------------------------
create_service_scripts() {
    echo ""
    echo "Creating service scripts..."
    
    # Startup script
    cat > $ORACLE_BASE/scripts/start_db.sh << 'EOF'
#!/bin/bash
export ORACLE_BASE=/opt/oracle
export ORACLE_HOME=/opt/oracle/product/19c/dbhome_1
export ORACLE_SID=ATGDB
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

echo "Starting Oracle Listener..."
lsnrctl start

echo "Starting Oracle Database..."
sqlplus / as sysdba << SQL
startup
exit
SQL

echo "Oracle Database started."
EOF

    # Shutdown script
    cat > $ORACLE_BASE/scripts/stop_db.sh << 'EOF'
#!/bin/bash
export ORACLE_BASE=/opt/oracle
export ORACLE_HOME=/opt/oracle/product/19c/dbhome_1
export ORACLE_SID=ATGDB
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

echo "Stopping Oracle Database..."
sqlplus / as sysdba << SQL
shutdown immediate
exit
SQL

echo "Stopping Oracle Listener..."
lsnrctl stop

echo "Oracle Database stopped."
EOF

    chmod +x $ORACLE_BASE/scripts/*.sh
    chown -R $ORACLE_USER:$ORACLE_GROUP $ORACLE_BASE/scripts/
    
    print_status "Service scripts created."
}

# -----------------------------
# Create systemd service
# -----------------------------
create_systemd_service() {
    echo ""
    echo "Creating systemd service..."
    
    cat > /etc/systemd/system/oracle.service << 'EOF'
[Unit]
Description=Oracle Database 19c
After=network.target

[Service]
Type=forking
User=oracle
Group=oinstall
Environment="ORACLE_BASE=/opt/oracle"
Environment="ORACLE_HOME=/opt/oracle/product/19c/dbhome_1"
Environment="ORACLE_SID=ATGDB"

ExecStart=/opt/oracle/scripts/start_db.sh
ExecStop=/opt/oracle/scripts/stop_db.sh

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable oracle.service
    
    print_status "Systemd service created and enabled."
}

# -----------------------------
# Print summary
# -----------------------------
print_summary() {
    echo ""
    echo "============================================="
    echo " ORACLE 19c INSTALLATION COMPLETE!          "
    echo "============================================="
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│ Oracle Database Details                     │"
    echo "├─────────────────────────────────────────────┤"
    echo "│ ORACLE_BASE: $ORACLE_BASE"
    echo "│ ORACLE_HOME: $ORACLE_HOME"
    echo "│ ORACLE_SID:  $ORACLE_SID"
    echo "│ Port:        1521"
    echo "│ SYS Password: $ORACLE_PWD"
    echo "└─────────────────────────────────────────────┘"
    echo ""
    echo "JDBC URL: jdbc:oracle:thin:@localhost:1521:$ORACLE_SID"
    echo ""
    echo "Commands:"
    echo "  Start DB:    sudo systemctl start oracle"
    echo "  Stop DB:     sudo systemctl stop oracle"
    echo "  Status:      sudo systemctl status oracle"
    echo "  SQL*Plus:    sudo -u oracle -i sqlplus / as sysdba"
    echo ""
    echo "Manual start/stop:"
    echo "  Start DB:   sudo -u oracle $ORACLE_BASE/scripts/start_db.sh"
    echo "  Stop DB:    sudo -u oracle $ORACLE_BASE/scripts/stop_db.sh"
    echo ""
    echo "Test connection:"
    echo "  sudo -u oracle -i sqlplus sys/$ORACLE_PWD@localhost:1521/$ORACLE_SID as sysdba"
    echo ""
}

# -----------------------------
# Main Execution
# -----------------------------
main() {
    check_root
    check_installer
    install_prerequisites
    create_oracle_user
    create_directories
    configure_kernel
    setup_environment
    install_oracle
    create_database
    configure_listener
    create_service_scripts
    create_systemd_service
    print_summary
}

# Run main function
main "$@"

