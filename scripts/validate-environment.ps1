# Azure Monitor AMPLS Environment Validation Script
# This script validates the Azure Monitor Private Link configuration

Write-Host "=== Azure Monitor AMPLS Environment Validation ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: DNS Resolution for Azure Monitor Endpoints
Write-Host "1. Testing DNS Resolution for Azure Monitor Endpoints..." -ForegroundColor Yellow

$endpoints = @(
    "oms.opinsights.azure.com",
    "dc.services.visualstudio.com", 
    "agent.azurearcdata.microsoft.com",
    "global.handler.control.monitor.azure.com"
)

foreach ($endpoint in $endpoints) {
    try {
        $result = Resolve-DnsName -Name $endpoint -ErrorAction Stop
        $ip = $result | Where-Object { $_.Type -eq "A" } | Select-Object -First 1
        
        if ($ip.IPAddress -match "^10\.|^172\.|^192\.168\.") {
            Write-Host "  ✓ $endpoint resolves to private IP: $($ip.IPAddress)" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ $endpoint resolves to public IP: $($ip.IPAddress)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ✗ Failed to resolve $endpoint" -ForegroundColor Red
    }
}

Write-Host ""

# Test 2: Network Connectivity to Azure Monitor
Write-Host "2. Testing Network Connectivity to Azure Monitor..." -ForegroundColor Yellow

foreach ($endpoint in $endpoints) {
    try {
        $result = Test-NetConnection -ComputerName $endpoint -Port 443 -WarningAction SilentlyContinue
        if ($result.TcpTestSucceeded) {
            Write-Host "  ✓ HTTPS connectivity to $endpoint successful" -ForegroundColor Green
        } else {
            Write-Host "  ✗ HTTPS connectivity to $endpoint failed" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✗ Error testing connectivity to $endpoint" -ForegroundColor Red
    }
}

Write-Host ""

# Test 3: Azure Monitor Agent Status
Write-Host "3. Checking Azure Monitor Agent Status..." -ForegroundColor Yellow

$amaService = Get-Service -Name "AzureMonitorAgent" -ErrorAction SilentlyContinue
if ($amaService) {
    if ($amaService.Status -eq "Running") {
        Write-Host "  ✓ Azure Monitor Agent service is running" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Azure Monitor Agent service status: $($amaService.Status)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ✗ Azure Monitor Agent service not found" -ForegroundColor Red
}

# Check AMA extension
$amaExtension = Get-WindowsFeature -Name "AzureMonitorAgent" -ErrorAction SilentlyContinue
if ($amaExtension) {
    Write-Host "  ✓ Azure Monitor Agent extension is installed" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Azure Monitor Agent extension status unclear" -ForegroundColor Yellow
}

Write-Host ""

# Test 4: Performance Counter Collection
Write-Host "4. Testing Performance Counter Collection..." -ForegroundColor Yellow

$perfCounters = @(
    "\Processor Information(_Total)\% Processor Time",
    "\Memory\% Committed Bytes In Use",
    "\LogicalDisk(C:)\% Free Space"
)

foreach ($counter in $perfCounters) {
    try {
        $value = (Get-Counter -Counter $counter -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
        Write-Host "  ✓ $counter = $([math]::Round($value, 2))" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Failed to collect $counter" -ForegroundColor Red
    }
}

Write-Host ""

# Test 5: Event Log Access
Write-Host "5. Testing Event Log Access..." -ForegroundColor Yellow

$eventLogs = @("Application", "System", "Security")

foreach ($log in $eventLogs) {
    try {
        $events = Get-WinEvent -LogName $log -MaxEvents 1 -ErrorAction Stop
        Write-Host "  ✓ Can access $log event log (Latest event: $($events.TimeCreated))" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Cannot access $log event log" -ForegroundColor Red
    }
}

Write-Host ""

# Test 6: Network Configuration
Write-Host "6. Checking Network Configuration..." -ForegroundColor Yellow

$networkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $networkAdapters) {
    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipConfig) {
        Write-Host "  ✓ Network adapter '$($adapter.Name)': $($ipConfig.IPAddress)" -ForegroundColor Green
    }
}

# Check DNS servers
$dnsServers = Get-DnsClientServerAddress | Where-Object { $_.AddressFamily -eq 2 -and $_.ServerAddresses.Count -gt 0 }
foreach ($dns in $dnsServers) {
    Write-Host "  ✓ DNS servers for interface $($dns.InterfaceAlias): $($dns.ServerAddresses -join ', ')" -ForegroundColor Green
}

Write-Host ""

# Test 7: Route Table Check
Write-Host "7. Checking Route Table..." -ForegroundColor Yellow

$routes = Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }
foreach ($route in $routes) {
    Write-Host "  ✓ Default route via $($route.NextHop) on interface $($route.InterfaceAlias)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Validation Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Check Azure Monitor Agent logs in Event Viewer" -ForegroundColor White
Write-Host "2. Wait 5-10 minutes for initial data to appear in Log Analytics" -ForegroundColor White
Write-Host "3. Run queries in Log Analytics Workspace to verify data ingestion" -ForegroundColor White
Write-Host "4. Monitor private endpoint status in Azure Portal" -ForegroundColor White
