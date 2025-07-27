param(
  [Parameter(Mandatory=$true)]
  [string]$ConnectionString
)

# set working directory
$appDir = "C:\apps\dotnet-sample"
if (-not (Test-Path $appDir)) {
  New-Item -ItemType Directory -Path $appDir | Out-Null
}
Set-Location $appDir

# ensure git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Invoke-WebRequest "https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.1/Git-2.42.0-64-bit.exe" -OutFile git-installer.exe
  Start-Process .\git-installer.exe -ArgumentList "/VERYSILENT" -Wait
}
$env:PATH += ";C:\Program Files\Git\bin"

# clone only once
if (-not (Test-Path ".\samples")) {
  git clone https://github.com/dotnet/samples.git
}

# go to sample
$samplePath = "C:\apps\dotnet-sample\samples\azure\app-insights-aspnet-core-quickstart"
if (-not (Test-Path $samplePath)) {
  Write-Error "Sample path not found"
  exit 1
}
Set-Location $samplePath

# ensure dotnet
$dotnetDir = "$env:USERPROFILE\.dotnet"
$dotnetExe = "$dotnetDir\dotnet.exe"
if (-not (Test-Path $dotnetExe)) {
  Invoke-WebRequest "https://dot.net/v1/dotnet-install.ps1" -OutFile install-dotnet.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File install-dotnet.ps1 -Channel LTS -InstallDir $dotnetDir
}

# write appsettings.json
$json = '{ "Logging": { "LogLevel": { "Default": "Information", "Microsoft.AspNetCore": "Warning" } }, "AllowedHosts": "*", "ApplicationInsights": { "ConnectionString": "' + $ConnectionString + '" } }'
$json | Set-Content appsettings.json

# add AI package, build
& $dotnetExe add package Microsoft.ApplicationInsights.AspNetCore
& $dotnetExe build

# -------------- NEW: create launcher and scheduled task --------------

# 1) write a tiny PowerShell launcher
$launcher = Join-Path $appDir 'start-sample.ps1'
@"
Set-Location `"$samplePath`"
$dotnetExe = "C:\Users\azureuser\.dotnet\dotnet.exe"
& $dotnetExe run
"@ | Set-Content $launcher

# 2) register a Scheduled Task at logon (if not already registered)
$taskName = 'DotnetSampleApp'
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
  $action   = New-ScheduledTaskAction  -Execute 'Powershell.exe' `
                -Argument "-WindowStyle Hidden -File `"$launcher`""
  $trigger  = New-ScheduledTaskTrigger -AtStartup
  Register-ScheduledTask -TaskName   $taskName `
                         -Action     $action `
                         -Trigger    $trigger `
                         -Description "Start .NET sample app at system startup" `
                         -User       "NT AUTHORITY\SYSTEM" `
                         -RunLevel   Highest

  Write-Output "Registered scheduled task '$taskName' (SYSTEM, AtStartup)."
}


# 3) optionally start it now
Start-Process -FilePath 'Powershell.exe' -ArgumentList "-WindowStyle Hidden -File `"$launcher`"" 

Write-Output "Setup complete. App will run now and on each logon."
