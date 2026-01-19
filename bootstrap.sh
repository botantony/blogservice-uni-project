#!/usr/bin/env bash

set -e

# Bash script that bootstraps the environment

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

SERVICE_USER="bloguser"
PROJECT_DIR="/home/$SERVICE_USER/service"
LOG_DIR="/var/log/blogservice"

echo "Creating new user..."
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /bin/bash -d /home/bloguser -m $SERVICE_USER
    echo "User $SERVICE_USER was created"
else
    echo "User $SERVICE_USER already exists"
fi

echo ""

echo "Setting up directories..."
mkdir -p $LOG_DIR
chown $SERVICE_USER:$SERVICE_USER $LOG_DIR
chmod 755 $LOG_DIR

echo ""

echo "Installing required dependencies..."
apt update
apt install -y \
    postgresql \
    postgresql-contrib \
    libpq-dev \
    iptables \
    iptables-persistent \
    tmux

echo ""

if ! command -v stack >/dev/null 2>&1; then
    echo "Installing Stack..."
    curl -sSL https://get.haskellstack.org/ | sh
fi

echo ""

echo "Configuring PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

echo ""

echo "Installing systemd service..."
if [ -f "$(dirname "$0")/blogservice.service" ]; then
    cp "$(dirname "$0")/blogservice.service" /etc/systemd/system/
    systemctl daemon-reload
    echo "systemd service installed"
    echo ""
else
    echo "WARNING: blogservice.service not found"
fi

echo ""

echo "Setting up file permissions..."
if [ -f "$PROJECT_DIR/.env" ]; then
    chmod 600 "$PROJECT_DIR/.env"
    chown $SERVICE_USER:$SERVICE_USER "$PROJECT_DIR/.env"
else
    echo ".env file not found, skipping setting up file permissions"
fi

echo "Done! Refer to README.md for the next step"
