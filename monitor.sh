#!/usr/bin/env bash

# Simple script for basic monitoring

echo "Service status:"
echo "-----------------------------------"
systemctl status blogservice --no-pager | head -n 10

echo ""

echo "Process information:"
echo "-----------------------------------"
if pgrep -f blogservice > /dev/null; then
    ps aux | grep blogservice | grep -v grep
    echo ""
    PID=$(pgrep -f blogservice)
    echo "Memory usage:"
    ps -p $PID -o pid,vsz,rss,pmem,comm
    echo ""
    echo "Open files:"
    lsof -p $PID 2>/dev/null | wc -l
    echo ""
else
    echo "Service not running!"
fi

echo "Network connections:"
echo "-----------------------------------"
ss -tlnp | grep :5555

echo ""

echo "Recent logs (last 20 lines):"
echo "-----------------------------------"
sudo journalctl -u blog-service -n 20 --no-pager

echo ""

echo "Logs disk usage:"
echo "-----------------------------------"
du -h /var/log/blogservice 2>/dev/null || du -h /var/log

echo ""

echo "Database status:"
echo "-----------------------------------"
systemctl status postgresql --no-pager | head -n 5
sudo -u postgres psql -c "SELECT count(*) as active_connections FROM pg_stat_activity WHERE datname='blogdb';" 2>/dev/null || echo "Cannot query database"

echo ""

echo "Uptime:"
echo "-----------------------------------"
uptime

echo ""

echo "You can get current firewall rules by running this command:"
echo "    sudo iptables -L -v -n --line-numbers"
