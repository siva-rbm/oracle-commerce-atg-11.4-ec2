#!/bin/bash

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT" || exit 1

echo "============================================="
echo " Oracle ATG + JBoss Local Setup              "
echo "============================================="
echo "Project Root: $PROJECT_ROOT"

# Installer paths (relative to project root)
INSTALLERS_DIR="atg/installers"
JDK_INSTALLER="jdk-8u202-linux-x64.tar.gz"
JBOSS_INSTALLER="jboss-eap-7.4.0.zip"
ATG_PLATFORM_INSTALLER="OCPlatform11.4.bin"
ATG_ACC_INSTALLER="OCACC11.4.bin"
ATG_REFSTORE_INSTALLER="OCReferenceStore11_3_1.bin"
OJDBC_JAR="ojdbc8.jar"

# Installation paths
JAVA_HOME="/opt/java/jdk1.8.0_202"
JBOSS_HOME="/opt/jboss/jboss-eap-7.4"
ATG_HOME="/opt/atg/ATG11.4"

# -----------------------------
# 1. Install required packages
# -----------------------------
echo "[1/5] Checking required packages..."

if ! command -v unzip &> /dev/null; then
    echo "Installing unzip..."
    sudo apt-get update -y
    sudo apt-get install -y unzip
fi

echo "[OK] Required packages ready."

# -----------------------------
# 2. Check installer files
# -----------------------------
echo "[2/5] Checking installer files..."

MISSING_FILES=0

if [ ! -f "${INSTALLERS_DIR}/${JDK_INSTALLER}" ]; then
    echo "❌ ERROR: Missing ${JDK_INSTALLER} in ${INSTALLERS_DIR}/"
    MISSING_FILES=1
fi

if [ ! -f "${INSTALLERS_DIR}/${JBOSS_INSTALLER}" ]; then
    echo "❌ ERROR: Missing ${JBOSS_INSTALLER} in ${INSTALLERS_DIR}/"
    MISSING_FILES=1
fi

if [ ! -f "${INSTALLERS_DIR}/${ATG_PLATFORM_INSTALLER}" ]; then
    echo "❌ ERROR: Missing ${ATG_PLATFORM_INSTALLER} in ${INSTALLERS_DIR}/"
    MISSING_FILES=1
fi

if [ ! -f "${INSTALLERS_DIR}/${ATG_ACC_INSTALLER}" ]; then
    echo "❌ ERROR: Missing ${ATG_ACC_INSTALLER} in ${INSTALLERS_DIR}/"
    MISSING_FILES=1
fi

if [ ! -f "${INSTALLERS_DIR}/${ATG_REFSTORE_INSTALLER}" ]; then
    echo "❌ ERROR: Missing ${ATG_REFSTORE_INSTALLER} in ${INSTALLERS_DIR}/"
    MISSING_FILES=1
fi

if [ ! -f "${INSTALLERS_DIR}/${OJDBC_JAR}" ]; then
    echo "❌ ERROR: Missing ${OJDBC_JAR} in ${INSTALLERS_DIR}/"
    MISSING_FILES=1
fi

if [ $MISSING_FILES -eq 1 ]; then
    echo ""
    echo "Required installer files:"
    echo "  ${INSTALLERS_DIR}/${JDK_INSTALLER}"
    echo "  ${INSTALLERS_DIR}/${JBOSS_INSTALLER}"
    echo "  ${INSTALLERS_DIR}/${ATG_PLATFORM_INSTALLER}"
    echo "  ${INSTALLERS_DIR}/${ATG_ACC_INSTALLER}"
    echo "  ${INSTALLERS_DIR}/${ATG_REFSTORE_INSTALLER}"
    echo "  ${INSTALLERS_DIR}/${OJDBC_JAR}"
    exit 1
fi

echo "[OK] All installer files found."

# -----------------------------
# 3. Install Java JDK 8
# -----------------------------
echo "[3/5] Checking Java JDK 8..."

if [ -d "${JAVA_HOME}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    echo "[SKIP] Java JDK 8 already installed at ${JAVA_HOME}"
else
    echo "Installing Java JDK 8..."
    sudo mkdir -p /opt/java
    sudo tar -xzf "${INSTALLERS_DIR}/${JDK_INSTALLER}" -C /opt/java

    # Add to profile for persistence
    sudo bash -c "cat > /etc/profile.d/java.sh << EOF
export JAVA_HOME=${JAVA_HOME}
export PATH=\${JAVA_HOME}/bin:\${PATH}
EOF"
    echo "[OK] Java JDK 8 installed at ${JAVA_HOME}"
fi

# Set JAVA_HOME for this session
export JAVA_HOME="${JAVA_HOME}"
export PATH="${JAVA_HOME}/bin:${PATH}"

# -----------------------------
# 4. Extract JBoss EAP 7.4
# -----------------------------
echo "[4/5] Checking JBoss EAP 7.4..."

if [ -d "${JBOSS_HOME}" ]; then
    echo "[SKIP] JBoss EAP 7.4 already extracted at ${JBOSS_HOME}"
else
    echo "Extracting JBoss EAP 7.4..."
    sudo mkdir -p /opt/jboss
    sudo unzip -q -o "${INSTALLERS_DIR}/${JBOSS_INSTALLER}" -d /opt/jboss

    # Add to profile for persistence
    sudo bash -c "cat > /etc/profile.d/jboss.sh << EOF
export JBOSS_HOME=${JBOSS_HOME}
EOF"
    echo "[OK] JBoss EAP 7.4 extracted to ${JBOSS_HOME}"
fi

export JBOSS_HOME="${JBOSS_HOME}"

# -----------------------------
# 5. Install Oracle ATG
# -----------------------------
echo "[5/5] Checking Oracle ATG 11.4..."

if [ -d "${ATG_HOME}" ] && [ -d "${ATG_HOME}/home" ]; then
    echo "[SKIP] ATG 11.4 already installed at ${ATG_HOME}"
else
    echo "Installing Oracle ATG Platform 11.4..."
    sudo mkdir -p /opt/atg
    chmod +x "${INSTALLERS_DIR}/${ATG_PLATFORM_INSTALLER}"

    sudo "${INSTALLERS_DIR}/${ATG_PLATFORM_INSTALLER}" -i silent \
        -DUSER_INSTALL_DIR="${ATG_HOME}" || {
        echo "❌ ERROR: ATG Platform installation failed."
        exit 1
    }
    echo "[OK] ATG Platform 11.4 installed."

    echo "Installing Oracle ATG ACC 11.4..."
    chmod +x "${INSTALLERS_DIR}/${ATG_ACC_INSTALLER}"

    sudo "${INSTALLERS_DIR}/${ATG_ACC_INSTALLER}" -i silent \
        -DUSER_INSTALL_DIR="${ATG_HOME}" || {
        echo "❌ ERROR: ATG ACC installation failed."
        exit 1
    }
    echo "[OK] ATG ACC 11.4 installed."

    echo "Installing Oracle ATG Reference Store 11.3.1..."
    chmod +x "${INSTALLERS_DIR}/${ATG_REFSTORE_INSTALLER}"

    sudo "${INSTALLERS_DIR}/${ATG_REFSTORE_INSTALLER}" -i silent \
        -DUSER_INSTALL_DIR="${ATG_HOME}" || {
        echo "❌ ERROR: ATG Reference Store installation failed."
        exit 1
    }

    # Copy OJDBC driver to ATG
    sudo cp "${INSTALLERS_DIR}/${OJDBC_JAR}" "${ATG_HOME}/DAS/lib/"
    echo "[OK] ATG Reference Store 11.3.1 installed."
fi

# -----------------------------
# Setup Complete
# -----------------------------
echo ""
echo "============================================="
echo " SETUP COMPLETE!"
echo "============================================="
echo ""
echo "Installation Summary:"
echo "  - Java JDK 8:    ${JAVA_HOME}"
echo "  - JBoss EAP 7.4: ${JBOSS_HOME}"
echo "  - ATG 11.4:      ${ATG_HOME}"
echo ""
echo "To apply environment variables, run:"
echo "    source /etc/profile.d/java.sh"
echo "    source /etc/profile.d/jboss.sh"
echo ""
echo "To run ATG CIM:"
echo "    cd ${ATG_HOME}/home/bin"
echo "    ./cim.sh"
echo ""
echo "To start JBoss:"
echo "    cd ${JBOSS_HOME}/bin"
echo "    ./standalone.sh"
echo ""
