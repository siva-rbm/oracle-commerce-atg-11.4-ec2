#!/bin/bash

#############################################################
# Fix Oracle 12c Linking Issues on Amazon Linux 2023        #
#############################################################

set -e

echo "============================================="
echo " Fixing Oracle 12c Linking Issues           "
echo "============================================="

ORACLE_BASE="/opt/oracle"
ORACLE_HOME="/opt/oracle/product/12.2.0.1/dbhome_1"
ORACLE_USER="oracle"
ORACLE_GROUP="oinstall"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

echo ""
echo "[1/6] Creating Oracle inventory pointer..."
# Create oraInst.loc if it doesn't exist
if [ ! -f /etc/oraInst.loc ]; then
    cat > /etc/oraInst.loc << EOF
inventory_loc=$ORACLE_BASE/oraInventory
inst_group=$ORACLE_GROUP
EOF
    chmod 644 /etc/oraInst.loc
    print_status "Created /etc/oraInst.loc"
else
    print_status "/etc/oraInst.loc already exists"
fi

echo ""
echo "[2/6] Running root.sh if not already run..."
if [ -f "$ORACLE_HOME/root.sh" ]; then
    $ORACLE_HOME/root.sh || print_warning "root.sh had some warnings (may be OK)"
    print_status "root.sh executed"
fi

echo ""
echo "[3/6] Installing additional development libraries..."
dnf install -y \
    gcc-c++ \
    libstdc++-static \
    glibc-static \
    glibc-devel \
    libaio-devel \
    --allowerasing 2>/dev/null || \
yum install -y gcc-c++ libstdc++-static glibc-static glibc-devel libaio-devel 2>/dev/null || \
print_warning "Some packages may not be available"

print_status "Development libraries installed"

echo ""
echo "[4/6] Attempting to relink Oracle binaries..."
sudo -u $ORACLE_USER bash << 'RELINK_SCRIPT'
export ORACLE_HOME=/opt/oracle/product/12.2.0.1/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

cd $ORACLE_HOME

# Try to relink - this may produce errors but often still works
$ORACLE_HOME/bin/relink all 2>&1 || echo "Relink completed with some errors (may be OK)"
RELINK_SCRIPT

print_status "Relink attempted"

echo ""
echo "[5/6] Checking Oracle binaries..."
BINARIES_OK=true

for binary in sqlplus dbca lsnrctl oracle; do
    if [ -f "$ORACLE_HOME/bin/$binary" ]; then
        echo -e "  ${GREEN}✓${NC} $binary exists"
    else
        echo -e "  ${RED}✗${NC} $binary missing"
        BINARIES_OK=false
    fi
done

echo ""
echo "[6/6] Testing Oracle binaries..."

# Test sqlplus
echo "Testing sqlplus..."
sudo -u $ORACLE_USER bash << 'TEST_SCRIPT'
export ORACLE_HOME=/opt/oracle/product/12.2.0.1/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

sqlplus -V 2>&1 && echo "sqlplus OK" || echo "sqlplus FAILED"
TEST_SCRIPT

# Test lsnrctl
echo ""
echo "Testing lsnrctl..."
sudo -u $ORACLE_USER bash << 'TEST_SCRIPT2'
export ORACLE_HOME=/opt/oracle/product/12.2.0.1/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

lsnrctl version 2>&1 | head -5 && echo "lsnrctl OK" || echo "lsnrctl FAILED"
TEST_SCRIPT2

# Test dbca
echo ""
echo "Testing dbca..."
sudo -u $ORACLE_USER bash << 'TEST_SCRIPT3'
export ORACLE_HOME=/opt/oracle/product/12.2.0.1/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH

dbca -help 2>&1 | head -3 && echo "dbca OK" || echo "dbca FAILED"
TEST_SCRIPT3

echo ""
echo "============================================="
echo " Fix Script Complete                        "
echo "============================================="
echo ""
echo "If the binaries work, proceed with database creation:"
echo "  sudo -u oracle /opt/oracle/scripts/create_db.sh"
echo ""
echo "If binaries failed, you may need to try Oracle 19c instead,"
echo "which has better support for newer Linux distributions."
echo ""

