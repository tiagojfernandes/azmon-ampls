# Azure Monitor AMPLS Lab Deployment Script

# Set error action preference to stop on errors
$ErrorActionPreference = "Stop"

# Define colors for output
function Write-ColorText {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

# Clone the repo (skip if already cloned)
if (-not (Test-Path "azmon-ampls")) {
    Write-ColorText "Cloning azmon-ampls repository..." -Color Cyan
    git clone https://github.com/damanue/azmon-ampls.git
}

# Navigate to the project directory
Set-Location azmon-ampls\environments\prod

Write-ColorText "Initializing Terraform..." -Color Cyan
terraform init

Write-ColorText "Planning Terraform deployment..." -Color Cyan
terraform plan

Write-ColorText "Applying Terraform configuration..." -Color Cyan
terraform apply -auto-approve

Write-ColorText "Deployment completed successfully!" -Color Green
