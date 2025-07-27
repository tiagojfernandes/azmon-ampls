#!/bin/bash

# Azure Monitor AMPLS Environment Validation Script
# This script validates the Azure Monitor Private Link configuration on Linux

echo "=== Azure Monitor AMPLS Environment Validation ==="
echo ""

# Test 1: DNS Resolution for Azure Monitor Endpoints
echo "1. Testing DNS Resolution for Azure Monitor Endpoints..."

endpoints=(
    "oms.opinsights.azure.com"
    "dc.services.visualstudio.com"
    "agent.azurearcdata.microsoft.com"
    "global.handler.control.monitor.azure.com"
)

for endpoint in "${endpoints[@]}"; do
    ip=$(dig +short $endpoint | tail -n1)
    if [[ -n "$ip" ]]; then
        # Check if IP is private (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
        if [[ $ip =~ ^10\. ]] || [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || [[ $ip =~ ^192\.168\. ]]; then
            echo "  ✓ $endpoint resolves to private IP: $ip"
        else
            echo "  ⚠ $endpoint resolves to public IP: $ip"
        fi
    else
        echo "  ✗ Failed to resolve $endpoint"
    fi
done

echo ""

# Test 2: Network Connectivity to Azure Monitor
echo "2. Testing Network Connectivity to Azure Monitor..."

for endpoint in "${endpoints[@]}"; do
    if timeout 5 bash -c "</dev/tcp/$endpoint/443" 2>/dev/null; then
        echo "  ✓ HTTPS connectivity to $endpoint successful"
    else
        echo "  ✗ HTTPS connectivity to $endpoint failed"
    fi
done

echo ""

# Test 3: Azure Monitor Agent Status
echo "3. Checking Azure Monitor Agent Status..."

if systemctl is-active --quiet azuremonitoragent; then
    echo "  ✓ Azure Monitor Agent service is running"
else
    echo "  ⚠ Azure Monitor Agent service is not running"
    systemctl status azuremonitoragent --no-pager -l
fi

# Check if AMA binary exists
if [[ -f "/opt/microsoft/azuremonitoragent/bin/azuremonitoragent" ]]; then
    echo "  ✓ Azure Monitor Agent binary found"
else
    echo "  ✗ Azure Monitor Agent binary not found"
fi

echo ""

# Test 4: System Metrics Collection
echo "4. Testing System Metrics Collection..."

# CPU usage
if command -v top >/dev/null 2>&1; then
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    echo "  ✓ CPU usage: ${cpu_usage}%"
fi

# Memory usage
if [[ -f /proc/meminfo ]]; then
    total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    free_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    used_mem=$((total_mem - free_mem))
    mem_usage=$((used_mem * 100 / total_mem))
    echo "  ✓ Memory usage: ${mem_usage}%"
fi

# Disk usage
if df -h / >/dev/null 2>&1; then
    disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    echo "  ✓ Disk usage (/): $disk_usage"
fi

echo ""

# Test 5: Syslog Configuration
echo "5. Testing Syslog Configuration..."

if systemctl is-active --quiet rsyslog; then
    echo "  ✓ rsyslog service is running"
elif systemctl is-active --quiet syslog-ng; then
    echo "  ✓ syslog-ng service is running"
else
    echo "  ⚠ No syslog service detected"
fi

# Check if syslog files exist
syslog_files=("/var/log/syslog" "/var/log/messages" "/var/log/auth.log")
for file in "${syslog_files[@]}"; do
    if [[ -f "$file" ]]; then
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        echo "  ✓ $file exists (size: $size bytes)"
        break
    fi
done

echo ""

# Test 6: Network Configuration
echo "6. Checking Network Configuration..."

# Network interfaces
interfaces=$(ip -4 addr show | grep -E "^[0-9]" | awk '{print $2}' | sed 's/://')
for interface in $interfaces; do
    if [[ "$interface" != "lo" ]]; then
        ip_addr=$(ip -4 addr show $interface | grep inet | awk '{print $2}' | head -n1)
        if [[ -n "$ip_addr" ]]; then
            echo "  ✓ Network interface '$interface': $ip_addr"
        fi
    fi
done

# DNS servers
if [[ -f /etc/resolv.conf ]]; then
    dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}')
    if [[ -n "$dns_servers" ]]; then
        echo "  ✓ DNS servers: $(echo $dns_servers | tr '\n' ' ')"
    fi
fi

echo ""

# Test 7: Route Table Check
echo "7. Checking Route Table..."

default_route=$(ip route | grep default)
if [[ -n "$default_route" ]]; then
    echo "  ✓ Default route: $default_route"
else
    echo "  ⚠ No default route found"
fi

echo ""

# Test 8: Azure Instance Metadata
echo "8. Testing Azure Instance Metadata..."

metadata_endpoint="169.254.169.254"
if timeout 5 bash -c "</dev/tcp/$metadata_endpoint/80" 2>/dev/null; then
    echo "  ✓ Azure Instance Metadata Service is accessible"
    
    # Try to get instance info
    if command -v curl >/dev/null 2>&1; then
        vm_name=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01" 2>/dev/null)
        if [[ -n "$vm_name" ]]; then
            echo "  ✓ VM Name: $vm_name"
        fi
        
        location=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01" 2>/dev/null)
        if [[ -n "$location" ]]; then
            echo "  ✓ VM Location: $location"
        fi
    fi
else
    echo "  ⚠ Azure Instance Metadata Service not accessible"
fi

echo ""

# Test 9: Azure Monitor Agent Logs
echo "9. Checking Azure Monitor Agent Logs..."

ama_log_dir="/var/opt/microsoft/azuremonitoragent/log"
if [[ -d "$ama_log_dir" ]]; then
    echo "  ✓ AMA log directory exists: $ama_log_dir"
    
    # Check for recent log files
    recent_logs=$(find "$ama_log_dir" -name "*.log" -mtime -1 2>/dev/null)
    if [[ -n "$recent_logs" ]]; then
        echo "  ✓ Recent log files found:"
        echo "$recent_logs" | head -5 | sed 's/^/    /'
    else
        echo "  ⚠ No recent log files found"
    fi
else
    echo "  ⚠ AMA log directory not found"
fi

echo ""
echo "=== Validation Complete ==="
echo ""
echo "Next Steps:"
echo "1. Check Azure Monitor Agent logs: sudo journalctl -u azuremonitoragent"
echo "2. Wait 5-10 minutes for initial data to appear in Log Analytics"
echo "3. Run queries in Log Analytics Workspace to verify data ingestion"
echo "4. Monitor private endpoint status in Azure Portal"
echo "5. Generate some syslog entries: logger 'Test message from Azure Monitor AMPLS lab'"
