# PowerShell script to install .NET Core sample app with Application Insights
# Usage: install-dotnet-app.ps1 -ConnectionString "your_connection_string"

param(
    [Parameter(Mandatory=$true)]
    [string]$ConnectionString
)

try {
    Write-Output "Starting .NET Core app installation process..."
    Write-Output "Application Insights Connection String: $($ConnectionString.Substring(0, 50))..."
    
    # Create application directory
    $appDir = 'C:\apps\dotnet-sample'
    New-Item -ItemType Directory -Path $appDir -Force
    Set-Location $appDir
    
    # Install Git
    Write-Output 'Installing Git...'
    $gitUrl = 'https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.1/Git-2.42.0-64-bit.exe'
    Invoke-WebRequest -Uri $gitUrl -OutFile 'git-installer.exe'
    Start-Process '.\git-installer.exe' -ArgumentList '/VERYSILENT' -Wait
    
    # Add Git to PATH for current session
    $env:PATH += ';C:\Program Files\Git\bin'
    
    # Clone the sample repository
    Write-Output 'Cloning .NET samples repository...'
    & 'C:\Program Files\Git\bin\git.exe' clone https://github.com/dotnet/samples.git
    
    # Install .NET SDK
    Write-Output 'Installing .NET SDK...'
    Invoke-WebRequest -Uri 'https://dotnet.microsoft.com/download/dotnet/scripts/v1/dotnet-install.ps1' -OutFile 'dotnet-install.ps1'
    & powershell -ExecutionPolicy Bypass -File '.\dotnet-install.ps1' -Channel LTS
    
    # Add .NET to PATH
    $dotnetPath = "$env:USERPROFILE\.dotnet"
    $env:PATH += ";$dotnetPath"
    $env:DOTNET_ROOT = $dotnetPath
    
    # Navigate to the App Insights sample
    $samplePath = 'samples\core\getting-started\AspNetCore\AspNetCore.ExistingApp'
    if (Test-Path $samplePath) {
        Set-Location $samplePath
        
        # Create appsettings.json with Application Insights
        $appSettings = @{
            "Logging" = @{
                "LogLevel" = @{
                    "Default" = "Information"
                    "Microsoft.AspNetCore" = "Warning"
                }
            }
            "AllowedHosts" = "*"
            "ApplicationInsights" = @{
                "ConnectionString" = $ConnectionString
            }
        }
        
        $appSettings | ConvertTo-Json -Depth 10 | Set-Content 'appsettings.json'
        Write-Output 'Created appsettings.json with Application Insights connection string'
        
        # Add Application Insights NuGet package
        Write-Output 'Adding Application Insights package...'
        & "$env:USERPROFILE\.dotnet\dotnet.exe" add package Microsoft.ApplicationInsights.AspNetCore
        
        # Update Program.cs to include Application Insights
        $programCs = @'
using Microsoft.ApplicationInsights.AspNetCore.Extensions;

var builder = WebApplication.CreateBuilder(args);

// Add Application Insights telemetry
builder.Services.AddApplicationInsightsTelemetry();

// Add services to the container.
builder.Services.AddControllersWithViews();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
'@
        
        $programCs | Set-Content 'Program.cs'
        Write-Output 'Updated Program.cs with Application Insights'
        
        # Build the application
        Write-Output 'Building the application...'
        & "$env:USERPROFILE\.dotnet\dotnet.exe" build
        
        # Create a startup script for the application
        $startupScript = @"
@echo off
cd /d "$((Get-Location).Path)"
"$env:USERPROFILE\.dotnet\dotnet.exe" run --urls http://0.0.0.0:5000
"@
        
        $startupScript | Set-Content 'start-app.bat'
        Write-Output 'Created startup script at start-app.bat'
        
        # Start the application in background
        Write-Output 'Starting the application on port 5000...'
        Start-Process -FilePath 'start-app.bat' -WindowStyle Hidden
        
        Write-Output 'Application should be accessible at http://localhost:5000'
        
    } else {
        # If the specific sample doesn't exist, create a simple ASP.NET Core app
        Write-Output 'Creating new ASP.NET Core app with Application Insights...'
        
        & "$env:USERPROFILE\.dotnet\dotnet.exe" new webapp -n AspNetCoreAppInsights
        Set-Location AspNetCoreAppInsights
        
        # Add Application Insights package
        & "$env:USERPROFILE\.dotnet\dotnet.exe" add package Microsoft.ApplicationInsights.AspNetCore
        
        # Update appsettings.json
        $appSettings = @{
            "Logging" = @{
                "LogLevel" = @{
                    "Default" = "Information"
                    "Microsoft.AspNetCore" = "Warning"
                }
            }
            "AllowedHosts" = "*"
            "ApplicationInsights" = @{
                "ConnectionString" = $ConnectionString
            }
        }
        
        $appSettings | ConvertTo-Json -Depth 10 | Set-Content 'appsettings.json'
        
        # Update Program.cs
        $programContent = Get-Content 'Program.cs' -Raw
        $updatedProgram = $programContent -replace 'var builder = WebApplication.CreateBuilder\(args\);', @'
var builder = WebApplication.CreateBuilder(args);

// Add Application Insights telemetry
builder.Services.AddApplicationInsightsTelemetry();
'@
        
        $updatedProgram | Set-Content 'Program.cs'
        
        # Build and start
        & "$env:USERPROFILE\.dotnet\dotnet.exe" build
        
        $startupScript = @"
@echo off
cd /d "$((Get-Location).Path)"
"$env:USERPROFILE\.dotnet\dotnet.exe" run --urls http://0.0.0.0:5000
"@
        
        $startupScript | Set-Content 'start-app.bat'
        Start-Process -FilePath 'start-app.bat' -WindowStyle Hidden
        
        Write-Output 'New ASP.NET Core app with Application Insights created and started'
    }
    
    Write-Output '.NET Core app installation completed successfully!'
    Write-Output 'Application Insights telemetry will be sent to the configured workspace'
    
} catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}
