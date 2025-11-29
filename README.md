# Oracle ATG 11.4 + JBoss EAP 7.4 + Oracle DB 12c

Complete setup guide for deploying Oracle Commerce (ATG) 11.4 with JBoss EAP 7.4 and Oracle Database 12c on AWS EC2.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS EC2 Instance                        │
│                  (t3.xlarge or larger)                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Host System                             │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │    │
│  │  │  Java JDK 8 │  │ JBoss EAP   │  │  ATG 11.4   │  │    │
│  │  │   /opt/java │  │  7.4        │  │  /opt/atg   │  │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
│                              │                               │
│                              ▼                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           Docker Container                           │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │          Oracle Database 12c                 │    │    │
│  │  │          Port: 1521 | EM: 5500              │    │    │
│  │  └─────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### AWS EC2 Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Instance Type | t3.large | t3.xlarge or r5.xlarge |
| vCPUs | 2 | 4+ |
| Memory | 8 GB | 16 GB+ |
| Storage | 50 GB | 100 GB SSD (gp3) |
| OS | Amazon Linux 2 / Ubuntu 20.04+ | Amazon Linux 2023 / Ubuntu 22.04 |

### Security Group Rules

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| SSH | TCP | 22 | Your IP | SSH Access |
| HTTP | TCP | 8080 | 0.0.0.0/0 | JBoss HTTP |
| HTTPS | TCP | 8443 | 0.0.0.0/0 | JBoss HTTPS |
| Custom | TCP | 9990 | Your IP | JBoss Admin Console |
| Custom | TCP | 1521 | VPC CIDR | Oracle DB |
| Custom | TCP | 5500 | Your IP | Oracle EM Express |

### Required Installer Files

Download these files and place them in the specified directories:

#### ATG Installers (`atg/installers/`)

| File | Description | Source |
|------|-------------|--------|
| `jdk-8u202-linux-x64.tar.gz` | Java JDK 8u202 | [Oracle Java Archive](https://www.oracle.com/java/technologies/javase/javase8-archive-downloads.html) |
| `jboss-eap-7.4.0.zip` | JBoss EAP 7.4 | [Red Hat Customer Portal](https://access.redhat.com/jbossnetwork/restricted/listSoftware.html) |
| `OCPlatform11.4.bin` | ATG Platform 11.4 | Oracle Software Delivery Cloud |
| `OCACC11.4.bin` | ATG ACC 11.4 | Oracle Software Delivery Cloud |
| `OCReferenceStore11_3_1.bin` | ATG Reference Store | Oracle Software Delivery Cloud |
| `ojdbc8.jar` | Oracle JDBC Driver | [Oracle JDBC Downloads](https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html) |

#### Oracle Database (`oracle-db/`)

| File | Description | Source |
|------|-------------|--------|
| `linuxx64_12201_database.zip` | Oracle DB 12.2.0.1 | [Oracle Software Delivery Cloud](https://edelivery.oracle.com/) |

## Quick Start

### 1. Launch EC2 Instance

```bash
# Using AWS CLI
aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type t3.xlarge \
    --key-name your-key-pair \
    --security-group-ids sg-xxxxxxxx \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ATG-Server}]'
```

### 2. Connect to EC2

```bash
ssh -i your-key.pem ec2-user@<EC2-PUBLIC-IP>
# or for Ubuntu:
ssh -i your-key.pem ubuntu@<EC2-PUBLIC-IP>
```

### 3. Clone This Repository

```bash
cd ~
git clone <your-repo-url> oc-atg-11.4-docker
cd oc-atg-11.4-docker
```

### 4. Upload Installer Files

From your local machine:

```bash
# Upload ATG installers
scp -i your-key.pem atg/installers/* ec2-user@<EC2-IP>:~/oc-atg-11.4-docker/atg/installers/

# Upload Oracle DB installer
scp -i your-key.pem oracle-db/linuxx64_12201_database.zip ec2-user@<EC2-IP>:~/oc-atg-11.4-docker/oracle-db/
```

### 5. Run Setup Script

```bash
chmod +x scripts/setup_aws_ec2.sh
./scripts/setup_aws_ec2.sh
```

## Detailed Setup Steps

### Step 1: Prerequisites Installation

The script automatically installs:
- Git
- Unzip
- Docker CE
- Required system packages

### Step 2: Oracle Database Setup

Uses the official [Oracle Docker Images](https://github.com/oracle/docker-images/tree/main/OracleDatabase) repository:

1. Clones `oracle/docker-images` to `/opt/oracle-docker-images`
2. Copies your Oracle DB installer to the build context
3. Builds Oracle DB 12.2.0.1-EE Docker image
4. Starts Oracle DB container with persistence

**Oracle DB Configuration:**

| Setting | Value |
|---------|-------|
| Container Name | oracle-db-12c |
| SID | ATGDB |
| PDB | ATGPDB |
| Password | ATG_Admin123 |
| Port | 1521 |
| EM Express | 5500 |
| Character Set | AL32UTF8 |
| Data Directory | /opt/oracle/oradata |

### Step 3: ATG Stack Installation

Installs locally on the host:

- **Java JDK 8** → `/opt/java/jdk1.8.0_202`
- **JBoss EAP 7.4** → `/opt/jboss/jboss-eap-7.4`
- **ATG Platform 11.4** → `/opt/atg/ATG11.4`
- **ATG ACC 11.4** → `/opt/atg/ATG11.4`
- **ATG Reference Store 11.3.1** → `/opt/atg/ATG11.4`

## Post-Installation

### Wait for Oracle DB Initialization

Oracle DB takes 10-15 minutes to initialize on first run:

```bash
# Watch initialization progress
sudo docker logs -f oracle-db-12c

# Look for: "DATABASE IS READY TO USE!"
```

### Apply Environment Variables

```bash
source /etc/profile.d/java.sh
source /etc/profile.d/jboss.sh

# Verify
java -version
echo $JBOSS_HOME
```

### Run ATG CIM (Configuration Manager)

```bash
cd /opt/atg/ATG11.4/home/bin
./cim.sh
```

CIM Configuration for Oracle DB:

| Setting | Value |
|---------|-------|
| Database Type | Oracle |
| JDBC URL | `jdbc:oracle:thin:@localhost:1521/ATGPDB` |
| Username | system |
| Password | ATG_Admin123 |
| Driver | oracle.jdbc.OracleDriver |

### Start JBoss

```bash
cd /opt/jboss/jboss-eap-7.4/bin
./standalone.sh -b 0.0.0.0
```

Access JBoss:
- **Application**: `http://<EC2-IP>:8080`
- **Admin Console**: `http://<EC2-IP>:9990`

## Management Commands

### Oracle Database

```bash
# Container status
sudo docker ps -a | grep oracle

# Start container
sudo docker start oracle-db-12c

# Stop container
sudo docker stop oracle-db-12c

# View logs
sudo docker logs -f oracle-db-12c

# Connect to SQL*Plus
sudo docker exec -it oracle-db-12c sqlplus sys/ATG_Admin123@ATGPDB as sysdba

# Restart container
sudo docker restart oracle-db-12c
```

### JBoss EAP

```bash
# Start in foreground
$JBOSS_HOME/bin/standalone.sh -b 0.0.0.0

# Start in background
nohup $JBOSS_HOME/bin/standalone.sh -b 0.0.0.0 > /var/log/jboss.log 2>&1 &

# Stop JBoss
$JBOSS_HOME/bin/jboss-cli.sh --connect command=:shutdown

# Check status
curl http://localhost:8080
```

### ATG

```bash
# Run CIM
cd /opt/atg/ATG11.4/home/bin
./cim.sh

# Run startDynamo
cd /opt/atg/ATG11.4/home/bin
./startDynamo.sh

# Check ATG logs
tail -f /opt/atg/ATG11.4/home/servers/*/logs/*.log
```

## Troubleshooting

### Oracle DB Container Won't Start

```bash
# Check Docker daemon
sudo systemctl status docker

# Check container logs
sudo docker logs oracle-db-12c

# Check disk space (Oracle needs ~15GB)
df -h

# Remove and recreate container
sudo docker rm oracle-db-12c
sudo docker run -d --name oracle-db-12c ...
```

### Oracle DB Connection Issues

```bash
# Check if Oracle is listening
sudo docker exec oracle-db-12c lsnrctl status

# Test connection from host
nc -zv localhost 1521

# Check firewall
sudo iptables -L -n | grep 1521
```

### ATG Installation Fails

```bash
# Check installer permissions
ls -la atg/installers/

# Make installers executable
chmod +x atg/installers/*.bin

# Run installer manually with verbose output
sudo ./atg/installers/OCPlatform11.4.bin -i console

# Check ATG logs
cat /tmp/OracleATG*.log
```

### Memory Issues

```bash
# Check available memory
free -h

# Increase swap if needed
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## File Structure

```
oc-atg-11.4-docker/
├── README.md                    # This file
├── .gitignore                   # Excludes installer binaries
├── scripts/
│   ├── setup_prj.sh             # Local setup (no Oracle DB)
│   └── setup_aws_ec2.sh         # AWS EC2 setup (with Oracle DB)
├── atg/
│   └── installers/              # Place ATG installers here (git-ignored)
│       ├── .gitkeep
│       ├── jdk-8u202-linux-x64.tar.gz
│       ├── jboss-eap-7.4.0.zip
│       ├── OCPlatform11.4.bin
│       ├── OCACC11.4.bin
│       ├── OCReferenceStore11_3_1.bin
│       └── ojdbc8.jar
├── oracle-db/                   # Place Oracle DB installer here (git-ignored)
│   ├── .gitkeep
│   └── linuxx64_12201_database.zip
└── endeca/
    └── installers/              # Future Endeca setup (git-ignored)
        └── .gitkeep
```

## Scripts Overview

| Script | Description | Use Case |
|--------|-------------|----------|
| `scripts/setup_prj.sh` | Local setup without Oracle DB | Development with external DB |
| `scripts/setup_aws_ec2.sh` | Full AWS EC2 setup with Oracle DB | Complete production-like setup |

## References

- [Oracle Docker Images Repository](https://github.com/oracle/docker-images/tree/main/OracleDatabase)
- [Oracle ATG Documentation](https://docs.oracle.com/cd/E52191_03/index.html)
- [JBoss EAP Documentation](https://access.redhat.com/documentation/en-us/red_hat_jboss_enterprise_application_platform/)
- [AWS EC2 User Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/)

## License

This project is for internal use. Oracle software requires valid licenses.

