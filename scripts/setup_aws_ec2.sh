#!/bin/bash

#############################################################
# Oracle ATG 11.4 + JBoss EAP 7.4 + Oracle DB 12c           #
# AWS EC2 Setup Script                                       #
# Tested on: Amazon Linux 2023, Ubuntu 20.04/22.04          #
#############################################################

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT" || exit 1

echo "============================================="
echo " Oracle ATG + JBoss + Oracle DB 12c Setup   "
echo " AWS EC2 Edition                            "
echo "============================================="
echo "Project Root: $PROJECT_ROOT"

# -----------------------------
# Configuration
# -----------------------------

# Installer paths (relative to project root)
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
ORACLE_DOCKER_REPO="/opt/oracle-docker-images"
ORACLE_DB_VERSION="12.2.0.1"
ORACLE_DB_EDITION="EE"
ORACLE_SID="ATGDB"
ORACLE_PDB="ATGPDB"
ORACLE_PWD="ATG_Admin123"
ORACLE_DB_PORT="1521"
ORACLE_EM_PORT="5500"

# Container name
ORACLE_CONTAINER="oracle-db-12c"

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
    echo "[1/8] Installing prerequisites..."
    
    detect_os
    
    case $OS in
        ubuntu|debian)
            sudo apt-get update -y
            sudo apt-get install -y \
                git \
                unzip \
                curl \
                ca-certificates \
                gnupg \
                lsb-release
            ;;
        amzn)
            # Amazon Linux 2023 uses dnf and has curl-minimal conflict
            sudo dnf install -y git unzip yum-utils --allowerasing
            ;;
        rhel|centos|fedora)
            sudo dnf install -y git unzip curl yum-utils
            ;;
        *)
            echo "⚠️ Unknown OS. Attempting to continue..."
            ;;
    esac
    
    echo "[OK] Prerequisites installed."
}

# -----------------------------
# 2. Install Docker
# -----------------------------
install_docker() {
    echo ""
    echo "[2/8] Checking Docker..."
    
    if command -v docker &> /dev/null; then
        echo "[SKIP] Docker already installed."
        sudo systemctl start docker 2>/dev/null || true
        sudo systemctl enable docker 2>/dev/null || true
        return
    fi
    
    echo "Installing Docker..."
    
    case $OS in
        ubuntu|debian)
            sudo mkdir -m 0755 -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
                sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            sudo apt-get update -y
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        amzn)
            # Amazon Linux 2023 uses dnf for Docker
            sudo dnf install -y docker
            ;;
        rhel|centos|fedora)
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
    esac
    
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    
    echo "[OK] Docker installed."
    echo "⚠️  You may need to log out and back in for Docker group to take effect."
}

# -----------------------------
# 3. Setup folder structure
# -----------------------------
setup_folders() {
    echo ""
    echo "[3/8] Setting up folder structure..."
    
    mkdir -p atg/installers
    mkdir -p oracle-db
    
    echo "[OK] Folder structure ready."
}

# -----------------------------
# 4. Check installer files
# -----------------------------
check_installers() {
    echo ""
    echo "[4/8] Checking installer files..."
    
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
# 5. Setup Oracle Docker Images
# -----------------------------
setup_oracle_docker() {
    echo ""
    echo "[5/8] Setting up Oracle Database 12c Docker..."
    
    # Check if image already exists
    if sudo docker images | grep -q "oracle/database.*${ORACLE_DB_VERSION}"; then
        echo "[SKIP] Oracle DB image already exists."
        return
    fi
    
    # Clone Oracle Docker Images repo
    if [ ! -d "${ORACLE_DOCKER_REPO}" ]; then
        echo "Cloning Oracle Docker Images repository..."
        sudo git clone https://github.com/oracle/docker-images.git ${ORACLE_DOCKER_REPO}
    else
        echo "Oracle Docker Images repo already exists."
    fi
    
    # Copy Oracle DB installer to the build context
    echo "Copying Oracle DB installer..."
    sudo cp oracle-db/${ORACLE_DB_ZIP} \
        ${ORACLE_DOCKER_REPO}/OracleDatabase/SingleInstance/dockerfiles/${ORACLE_DB_VERSION}/
    
    # Build Oracle DB Docker image
    echo "Building Oracle Database ${ORACLE_DB_VERSION} Docker image..."
    echo "This may take 15-30 minutes..."
    
    cd ${ORACLE_DOCKER_REPO}/OracleDatabase/SingleInstance/dockerfiles
    sudo ./buildContainerImage.sh -v ${ORACLE_DB_VERSION} -e
    cd - > /dev/null
    
    echo "[OK] Oracle DB Docker image built."
}

# -----------------------------
# 6. Start Oracle DB Container
# -----------------------------
start_oracle_container() {
    echo ""
    echo "[6/8] Starting Oracle Database container..."
    
    # Check if container already exists
    if sudo docker ps -a --format '{{.Names}}' | grep -q "^${ORACLE_CONTAINER}$"; then
        if sudo docker ps --format '{{.Names}}' | grep -q "^${ORACLE_CONTAINER}$"; then
            echo "[SKIP] Oracle DB container already running."
            return
        else
            echo "Starting existing Oracle DB container..."
            sudo docker start ${ORACLE_CONTAINER}
            echo "[OK] Oracle DB container started."
            return
        fi
    fi
    
    # Create data directory for persistence
    sudo mkdir -p /opt/oracle/oradata
    sudo chmod 777 /opt/oracle/oradata
    
    echo "Creating and starting Oracle DB container..."
    sudo docker run -d \
        --name ${ORACLE_CONTAINER} \
        -p ${ORACLE_DB_PORT}:1521 \
        -p ${ORACLE_EM_PORT}:5500 \
        -e ORACLE_SID=${ORACLE_SID} \
        -e ORACLE_PDB=${ORACLE_PDB} \
        -e ORACLE_PWD=${ORACLE_PWD} \
        -e ORACLE_CHARACTERSET=AL32UTF8 \
        -v /opt/oracle/oradata:/opt/oracle/oradata \
        oracle/database:${ORACLE_DB_VERSION}-${ORACLE_DB_EDITION} || {
        echo "❌ ERROR: Failed to start Oracle DB container."
        exit 1
    }
    
    echo "[OK] Oracle DB container started."
    echo ""
    echo "⏳ Oracle DB is initializing. This takes 10-15 minutes on first run."
    echo "   Check status: sudo docker logs -f ${ORACLE_CONTAINER}"
}

# -----------------------------
# 7. Install Java, JBoss, ATG
# -----------------------------
install_atg_stack() {
    echo ""
    echo "[7/8] Installing ATG Stack (Java, JBoss, ATG)..."
    
    # Install Java JDK 8
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
    
    # Extract JBoss EAP 7.4
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
    
    # Install ATG
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
# 8. Configure ATG for Oracle DB
# -----------------------------
configure_atg_db() {
    echo ""
    echo "[8/8] Configuring ATG database connection..."
    
    # Get EC2 private IP or localhost
    EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "localhost")
    
    # Create ATG datasource configuration
    ATG_LOCALCONFIG="${ATG_HOME}/home/localconfig"
    sudo mkdir -p "${ATG_LOCALCONFIG}/atg/dynamo/service/jdbc"
    
    sudo bash -c "cat > ${ATG_LOCALCONFIG}/atg/dynamo/service/jdbc/JTDataSource.properties << EOF
# Oracle DB Connection for ATG
\$class=atg.nucleus.JNDIDataSource
dataSource=java:jboss/datasources/ATGDataSource
EOF"
    
    echo "[OK] ATG database configuration created."
    echo ""
    echo "============================================="
    echo " SETUP COMPLETE!"
    echo "============================================="
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│ Installation Summary                        │"
    echo "├─────────────────────────────────────────────┤"
    echo "│ Java JDK 8:    ${JAVA_HOME}"
    echo "│ JBoss EAP 7.4: ${JBOSS_HOME}"
    echo "│ ATG 11.4:      ${ATG_HOME}"
    echo "│ Oracle DB 12c: Docker (port ${ORACLE_DB_PORT})"
    echo "└─────────────────────────────────────────────┘"
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│ Oracle Database Credentials                 │"
    echo "├─────────────────────────────────────────────┤"
    echo "│ SID:      ${ORACLE_SID}"
    echo "│ PDB:      ${ORACLE_PDB}"
    echo "│ Password: ${ORACLE_PWD}"
    echo "│ Port:     ${ORACLE_DB_PORT}"
    echo "│ EM Port:  ${ORACLE_EM_PORT}"
    echo "└─────────────────────────────────────────────┘"
    echo ""
    echo "JDBC URL: jdbc:oracle:thin:@localhost:${ORACLE_DB_PORT}/${ORACLE_PDB}"
    echo ""
    echo "Next Steps:"
    echo "  1. Wait for Oracle DB to initialize (10-15 min):"
    echo "     sudo docker logs -f ${ORACLE_CONTAINER}"
    echo ""
    echo "  2. Apply environment variables:"
    echo "     source /etc/profile.d/java.sh"
    echo "     source /etc/profile.d/jboss.sh"
    echo ""
    echo "  3. Run ATG CIM to configure:"
    echo "     cd ${ATG_HOME}/home/bin"
    echo "     ./cim.sh"
    echo ""
    echo "  4. Start JBoss:"
    echo "     cd ${JBOSS_HOME}/bin"
    echo "     ./standalone.sh -b 0.0.0.0"
    echo ""
}

# -----------------------------
# Main Execution
# -----------------------------
main() {
    install_prerequisites
    install_docker
    setup_folders
    check_installers
    setup_oracle_docker
    start_oracle_container
    install_atg_stack
    configure_atg_db
}

# Run main function
main "$@"