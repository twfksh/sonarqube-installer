#!/bin/bash
# Usage: sudo ./setup.sh 

set -e

SONARQUBE_VARSION=${1:-26.2.0.119303}
SONARQUBE_SRC_DIR="/opt/sonarqube"
SONARQUBE_BINARY_DIR="sonarqube-bin"
SONARQUBE_BINARY="$SONARQUBE_SRC_DIR/bin/sonar.sh"
SONARQUBE_BINARY_DOWNLINK="https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-$SONARQUBE_VARSION.zip"

POSTGRES_DB="sonarqube"
POSTGRES_USER="sonar"
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-"root"}

# Install PostgreSQL
echo "Installing PostgreSQL..."
apt-get update
apt-get install -y postgresql postgresql-contrib unzip wget

echo "Configuring PostgreSQL for SonarQube..."
sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';" || true
sudo -u postgres psql -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;" || true
sudo -u postgres psql -c "ALTER USER $POSTGRES_USER WITH SUPERUSER;" || true

# Ensure PostgreSQL listens on localhost
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf
echo "host    $POSTGRES_DB    $POSTGRES_USER    127.0.0.1/32    md5" >> /etc/postgresql/*/main/pg_hba.conf
systemctl restart postgresql

# Install SonarQube Community
echo "Installing SonarQube $SONARQUBE_VERSION..."
mkdir -p $SONARQUBE_SRC_DIR

# Download sonarqube binaries
wget -O "$SONARQUBE_SRC_DIR/$SONARQUBE_BINARY_DIR.zip" $SONARQUBE_BINARY_DOWNLINK

# Extract binaries
TEMP_DIR=$(unzip -Z1 "$SONARQUBE_SRC_DIR/$SONARQUBE_BINARY_DIR.zip" | head -1 | cut -d/ -f1) && \
unzip "$SONARQUBE_SRC_DIR/$SONARQUBE_BINARY_DIR.zip" -d $SONARQUBE_SRC_DIR && \
ln -s "$SONARQUBE_SRC_DIR/$TEMP_DIR/bin/linux-x86-64" "$SONARQUBE_SRC_DIR/bin"

# Add permissions and sonarqube user
sudo chmod +x $SONARQUBE_BINARY
getent group sonarqube || sudo groupadd --system sonarqube
id sonarqube >/dev/null 2>&1 || sudo useradd --system --gid sonarqube --home-dir $SONARQUBE_SRC_DIR --shell /bin/bash sonarqube
sudo chown -R sonarqube:sonarqube $SONARQUBE_SRC_DIR
sudo mkdir -p $SONARQUBE_SRC_DIR/temp $SONARQUBE_SRC_DIR/logs
sudo chown -R sonarqube:sonarqube $SONARQUBE_SRC_DIR/temp $SONARQUBE_SRC_DIR/logs

# Configure sonar.properties for PostgreSQL with public schema
SONAR_PROPERTIES="$SONARQUBE_SRC_DIR/$TEMP_DIR/conf/sonar.properties"

echo "Configuring SonarQube to use PostgreSQL (public schema)..."
sed -i "s|#sonar.jdbc.username=.*|sonar.jdbc.username=$POSTGRES_USER|" $SONAR_PROPERTIES
sed -i "s|#sonar.jdbc.password=.*|sonar.jdbc.password=$POSTGRES_PASSWORD|" $SONAR_PROPERTIES
sed -i "s|#sonar.jdbc.url=.*|sonar.jdbc.url=jdbc:postgresql://127.0.0.1:5432/$POSTGRES_DB?currentSchema=public|" $SONAR_PROPERTIES
sed -i 's/currentSchema=my_schema/currentSchema=public/' "$SONAR_PROPERTIES"

# Generate sonarqube.service unit file
cat <<EOF > /etc/systemd/system/sonarqube.service
[Unit] 
Description=SonarQube service 
After=network.service

[Service] 
Type=forking
User=sonarqube
Group=sonarqube
PIDFile=/opt/sonarqube/bin/SonarQube.pid

Environment=JAVA_HOME=/usr/lib/jvm/default
WorkingDirectory=/opt/sonarqube 
ExecStart=/opt/sonarqube/bin/sonar.sh start 
ExecStop=/opt/sonarqube/bin/sonar.sh stop 

[Install] 
WantedBy=default.target 
EOF

# Start the service
echo "Starting SonarQube..."
systemctl daemon-reload
systemctl enable sonarqube.service --now

echo "SonarQube setup completed!"
echo "Web UI should be available on port 9000."
echo "PostgreSQL DB: $POSTGRES_DB, User: $POSTGRES_USER"
