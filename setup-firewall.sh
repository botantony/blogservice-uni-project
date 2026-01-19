#!/usr/bin/env bash

# Script that setups firewall rules

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi


BLOGSERVICE_PORT=5555
POSTGRESQL_PORT=6543

# Flush existing rules and set default policies
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Local traffic + established & related connection
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Protect private API
iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -m string \
  --string "GET /private-api" --algo bm \
  -s 127.0.0.1 -j ACCEPT

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -m string \
  --string "GET /private-api" --algo bm \
  -j DROP

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -m string \
  --string "POST /private-api" --algo bm \
  -s 127.0.0.1 -j ACCEPT

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -m string \
  --string "POST /private-api" --algo bm \
  -j DROP

# Rate limits on public API, RSS feed, and web pages
iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -m string \
  --string "GET /api/" --algo bm \
  -m hashlimit \
  --hashlimit-name api_limit \
  --hashlimit-above 1/min \
  --hashlimit-mode srcip \
  --hashlimit-burst 10 \
  --hashlimit-htable-expire 120000 \
  -j LOG --log-prefix "API_RATE_LIMIT: " --log-level 4

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -m string \
  --string "GET /api/" --algo bm \
  -m hashlimit \
  --hashlimit-name api_limit \
  --hashlimit-above 1/min \
  --hashlimit-mode srcip \
  --hashlimit-burst 10 \
  --hashlimit-htable-expire 120000 \
  -j DROP

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -m string \
  --string "GET /rss" --algo bm \
  -m hashlimit \
  --hashlimit-name rss_limit \
  --hashlimit-above 10/min \
  --hashlimit-mode srcip \
  --hashlimit-burst 5 \
  --hashlimit-htable-expire 120000 \
  -j LOG --log-prefix "RSS_RATE_LIMIT: " --log-level 4

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -m string \
  --string "GET /rss" --algo bm \
  -m hashlimit \
  --hashlimit-name rss_limit \
  --hashlimit-above 10/min \
  --hashlimit-mode srcip \
  --hashlimit-burst 5 \
  --hashlimit-htable-expire 120000 \
  -j DROP

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT \
  -m hashlimit \
  --hashlimit-name web_limit \
  --hashlimit-above 60/min \
  --hashlimit-mode srcip \
  --hashlimit-burst 20 \
  --hashlimit-htable-expire 120000 \
  -j LOG --log-prefix "WEB_RATE_LIMIT: " --log-level 4

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT \
  -m hashlimit \
  --hashlimit-name web_limit \
  --hashlimit-above 60/min \
  --hashlimit-mode srcip \
  --hashlimit-burst 20 \
  --hashlimit-htable-expire 120000 \
  -j DROP

iptables -A INPUT -p tcp --dport $BLOGSERVICE_PORT -j ACCEPT

# Block PostgreSQL traffic
iptables -A INPUT -p tcp --dport $POSTGRESQL_PORT -s 127.0.0.1 -j ACCEPT
iptables -A INPUT -p tcp --dport $POSTGRESQL_PORT -j DROP

# Save rules
netfilter-persistent save
