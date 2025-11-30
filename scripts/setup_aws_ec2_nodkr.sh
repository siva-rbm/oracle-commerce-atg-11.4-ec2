#!/bin/bash

#############################################################
# Oracle ATG 11.4 + JBoss EAP 7.4 + Oracle DB 12c           #
# AWS EC2 Setup Script (NO DOCKER)                          #
# Direct Oracle 12c Installation                            #
#############################################################

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT" || exit 1

echo "============================================="
echo " Oracle ATG + JBoss + Oracle DB 12c Setup   "
echo " AWS EC2 Edition (No Docker)                "
echo "============================================="
echo "Project Root: $PROJECT_ROOT"

# -----------------------------
# Configuration
# -----------------------------

# Installer paths
INSTALLERS_DIR="atg/installers"
JDK_INSTALLER="jdk-8u202-linux-x64.tar.gz"
JBOSS_INSTALLER="jboss-eap-7.4.0.zip"
ATG_PLATFORM_INSTALLER="OCPlatform11.4.bin"
ATG_ACC_INSTALLER="OCACC11.4.bin"
ATG_REFSTORE_INSTALLER="OCReferenceStore11_3_1.bin"
OJDBC_JAR="ojdbc8.jar"
ORACLE_DB_ZIP="linuxx64_12201_database.zip"

# Installation paths
JAVA_HOME="/opt/java/jdk1.8.0_202"
JBOSS_HOME="/opt/jboss/jboss-eap-7.4"
ATG_HOME="/opt/atg/ATG11.4"

# Oracle DB configuration
ORACLE_BASE="/opt/oracle"
ORACLE_HOME="/opt/oracle/product/12.2.0.1/dbhome_1"
ORACLE_SID="ATGDB"
ORACLE_PWD="ATG_Admin123"

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    else
        OS="unknown"
    fi
    echo "Detected OS: $OS"
}

# -----------------------------
# 1. Install Prerequisites
# -----------------------------
install_prerequisites() {
    echo ""
    echo "[1/6] Installing prerequisites..."
    
    detect_os
    
    case $OS in
        ubuntu|debian)
            sudo apt-get update -y
            sudo apt-get install -y git unzip curl ca-certificates gnupg lsb-release
            ;;
        amzn)
            sudo dnf install -y git unzip --allowerasing
            ;;
        rhel|centos|fedora)
            sudo dnf install -y git unzip curl
            ;;
        *)
            echo "⚠️ Unknown OS. Attempting to continue..."
            ;;
    esac
    
    echo "[OK] Prerequisites installed."
}

# -----------------------------
# 2. Check installer files
# -----------------------------
check_installers() {
    echo ""
    echo "[2/6] Checking installer files..."
    
    MISSING_FILES=0
    
    declare -a FILES=(
        "${INSTALLERS_DIR}/${JDK_INSTALLER}"
        "${INSTALLERS_DIR}/${JBOSS_INSTALLER}"
        "${INSTALLERS_DIR}/${ATG_PLATFORM_INSTALLER}"
        "${INSTALLERS_DIR}/${ATG_ACC_INSTALLER}"
        "${INSTALLERS_DIR}/${ATG_REFSTORE_INSTALLER}"
        "${INSTALLERS_DIR}/${OJDBC_JAR}"
        "oracle-db/${ORACLE_DB_ZIP}"
    )
    
    for file in "${FILES[@]}"; do
        if [ ! -f "$file" ]; then
            echo "❌ Missing: $file"
            MISSING_FILES=1
        else
            echo "✓ Found: $file"
        fi
    done
    
    if [ $MISSING_FILES -eq 1 ]; then
        echo ""
        echo "Please copy all required installer files before running this script."
        exit 1
    fi
    
    echo "[OK] All installer files found."
}

# -----------------------------
# 3. Install Oracle Database 12c
# -----------------------------
install_oracle_db() {
    echo ""
    echo "[3/6] Installing Oracle Database 12c..."
    
    if [ -f "$ORACLE_HOME/bin/sqlplus" ]; then
        echo "[SKIP] Oracle Database already installed."
        return 0
    fi
    
    # Run Oracle installation script
    sudo "${SCRIPT_DIR}/install_oracle12c.sh"
    
    echo "[OK] Oracle Database 12c installed."
}

# -----------------------------
# 4. Install Java JDK 8
# -----------------------------
install_java() {
    echo ""
    echo "[4/6] Installing Java JDK 8..."
    
    if [ -d "${JAVA_HOME}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
        echo "[SKIP] Java JDK 8 already installed."
    else
        echo "Installing Java JDK 8..."
        sudo mkdir -p /opt/java
        sudo tar -xzf "${INSTALLERS_DIR}/${JDK_INSTALLER}" -C /opt/java
        
        sudo bash -c "cat > /etc/profile.d/java.sh << EOF
export JAVA_HOME=${JAVA_HOME}
export PATH=\${JAVA_HOME}/bin:\${PATH}
EOF"
        echo "✓ Java JDK 8 installed."
    fi
    
    export JAVA_HOME="${JAVA_HOME}"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    
    echo "[OK] Java ready."
}

# -----------------------------
# 5. Install JBoss EAP 7.4
# -----------------------------
install_jboss() {
    echo ""
    echo "[5/6] Installing JBoss EAP 7.4..."
    
    if [ -d "${JBOSS_HOME}" ]; then
        echo "[SKIP] JBoss EAP 7.4 already extracted."
    else
        echo "Extracting JBoss EAP 7.4..."
        sudo mkdir -p /opt/jboss
        sudo unzip -q -o "${INSTALLERS_DIR}/${JBOSS_INSTALLER}" -d /opt/jboss
        
        sudo bash -c "cat > /etc/profile.d/jboss.sh << EOF
export JBOSS_HOME=${JBOSS_HOME}
EOF"
        echo "✓ JBoss EAP 7.4 extracted."
    fi
    
    export JBOSS_HOME="${JBOSS_HOME}"
    
    echo "[OK] JBoss ready."
}

# -----------------------------
# 6. Install ATG
# -----------------------------
install_atg() {
    echo ""
    echo "[6/6] Installing Oracle ATG 11.4..."
    
    if [ -d "${ATG_HOME}" ] && [ -d "${ATG_HOME}/home" ]; then
        echo "[SKIP] ATG 11.4 already installed."
    else
        echo "Installing Oracle ATG Platform 11.4..."
        sudo mkdir -p /opt/atg
        chmod +x "${INSTALLERS_DIR}/${ATG_PLATFORM_INSTALLER}"
        
        sudo "${INSTALLERS_DIR}/${ATG_PLATFORM_INSTALLER}" -i silent \
            -DUSER_INSTALL_DIR="${ATG_HOME}" || {
            echo "❌ ERROR: ATG Platform installation failed."
            exit 1
        }
        echo "✓ ATG Platform 11.4 installed."
        
        echo "Installing Oracle ATG ACC 11.4..."
        chmod +x "${INSTALLERS_DIR}/${ATG_ACC_INSTALLER}"
        
        sudo "${INSTALLERS_DIR}/${ATG_ACC_INSTALLER}" -i silent \
            -DUSER_INSTALL_DIR="${ATG_HOME}" || {
            echo "❌ ERROR: ATG ACC installation failed."
            exit 1
        }
        echo "✓ ATG ACC 11.4 installed."
        
        echo "Installing Oracle ATG Reference Store 11.3.1..."
        chmod +x "${INSTALLERS_DIR}/${ATG_REFSTORE_INSTALLER}"
        
        sudo "${INSTALLERS_DIR}/${ATG_REFSTORE_INSTALLER}" -i silent \
            -DUSER_INSTALL_DIR="${ATG_HOME}" || {
            echo "❌ ERROR: ATG Reference Store installation failed."
            exit 1
        }
        
        # Copy OJDBC driver
        sudo cp "${INSTALLERS_DIR}/${OJDBC_JAR}" "${ATG_HOME}/DAS/lib/"
        echo "✓ ATG Reference Store 11.3.1 installed."
    fi
    
    echo "[OK] ATG Stack installed."
}

# -----------------------------
# Print Summary
# -----------------------------
print_summary() {
    echo ""
    echo "============================================="
    echo " SETUP COMPLETE!                            "
    echo "============================================="
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│ Installation Summary                        │"
    echo "├─────────────────────────────────────────────┤"
    echo "│ Java JDK 8:     ${JAVA_HOME}"
    echo "│ JBoss EAP 7.4:  ${JBOSS_HOME}"
    echo "│ ATG 11.4:       ${ATG_HOME}"
    echo "│ Oracle DB 12c:  ${ORACLE_HOME}"
    echo "└─────────────────────────────────────────────┘"
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│ Oracle Database                             │"
    echo "├─────────────────────────────────────────────┤"
    echo "│ SID:       ${ORACLE_SID}"
    echo "│ Port:      1521"
    echo "│ Password:  ${ORACLE_PWD}"
    echo "│ JDBC URL:  jdbc:oracle:thin:@localhost:1521:${ORACLE_SID}"
    echo "└─────────────────────────────────────────────┘"
    echo ""
    echo "Quick Commands:"
    echo ""
    echo "  # Apply environment"
    echo "  source /etc/profile.d/java.sh"
    echo "  source /etc/profile.d/jboss.sh"
    echo "  source /etc/profile.d/oracle.sh"
    echo ""
    echo "  # Start Oracle DB"
    echo "  sudo -u oracle ${ORACLE_BASE}/scripts/start_db.sh"
    echo ""
    echo "  # Run ATG CIM"
    echo "  cd ${ATG_HOME}/home/bin && ./cim.sh"
    echo ""
    echo "  # Start JBoss"
    echo "  cd ${JBOSS_HOME}/bin && ./standalone.sh -b 0.0.0.0"
    echo ""
}

# -----------------------------
# Main Execution
# -----------------------------
main() {
    install_prerequisites
    check_installers
    install_oracle_db
    install_java
    install_jboss
    install_atg
    print_summary
}

# Run main function
main "$@"

