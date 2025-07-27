# Azure Monitor AMPLS Lab Deployment Script (PowerShell)
# This script helps deploy and validate the Azure Monitor AMPLS lab environment

param(
    [Parameter(Position=0)]
    [ValidateSet("deploy", "destroy", "plan", "output")]
    [string]$Action = "deploy"
)

# Function to write colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Function to check if a command exists
function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    # Check if Terraform is installed
    if (-not (Test-Command "terraform")) {
        Write-Error "Terraform is not installed. Please install Terraform first."
        exit 1
    } else {
        $terraformVersion = (terraform version -json | ConvertFrom-Json).terraform_version
        Write-Success "Terraform is installed (version: $terraformVersion)"
    }
    
    # Check if Azure CLI is installed
    if (-not (Test-Command "az")) {
        Write-Error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    } else {
        $azVersion = (az version --output json | ConvertFrom-Json).'azure-cli'
        Write-Success "Azure CLI is installed (version: $azVersion)"
    }
    
    # Check Azure CLI login status
    try {
        $account = az account show --output json | ConvertFrom-Json
        Write-Success "Logged in to Azure (subscription: $($account.name))"
    }
    catch {
        Write-Error "You are not logged in to Azure CLI. Please run 'az login' first."
        exit 1
    }
}

# Function to initialize Terraform
function Initialize-Terraform {
    Write-Status "Initializing Terraform..."
    
    $result = terraform init
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform initialized successfully"
    } else {
        Write-Error "Failed to initialize Terraform"
        exit 1
    }
}

# Function to validate Terraform configuration
function Test-TerraformConfiguration {
    Write-Status "Validating Terraform configuration..."
    
    $result = terraform validate
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform configuration is valid"
    } else {
        Write-Error "Terraform configuration validation failed"
        exit 1
    }
}

# Function to plan Terraform deployment
function New-TerraformPlan {
    Write-Status "Creating Terraform plan..."
    
    $result = terraform plan -out=tfplan
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform plan created successfully"
        Write-Host ""
        Write-Warning "Review the plan above. Press Enter to continue with deployment or Ctrl+C to cancel."
        Read-Host
    } else {
        Write-Error "Failed to create Terraform plan"
        exit 1
    }
}

# Function to apply Terraform configuration
function Invoke-TerraformApply {
    Write-Status "Applying Terraform configuration..."
    
    $result = terraform apply tfplan
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform deployment completed successfully"
    } else {
        Write-Error "Terraform deployment failed"
        exit 1
    }
}

# Function to get outputs
function Get-TerraformOutputs {
    Write-Status "Retrieving deployment outputs..."
    
    $result = terraform output -json | Out-File -FilePath "outputs.json" -Encoding UTF8
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Outputs saved to outputs.json"
        
        # Display key information
        Write-Host ""
        Write-Status "Deployment Summary:"
        Write-Host "Resource Group: $(terraform output -raw resource_group_name)"
        Write-Host "Log Analytics Workspace: $(terraform output -raw log_analytics_workspace_name)"
        Write-Host "AMPLS Name: $(terraform output -raw ampls_name)"
        Write-Host "Windows VM Public IP: $(terraform output -raw windows_vm_public_ip)"
        Write-Host "Ubuntu VM Public IP: $(terraform output -raw ubuntu_vm_public_ip)"
        Write-Host "Admin Username: $(terraform output -raw vm_admin_username)"
        Write-Host "Auto-shutdown: $(terraform output -raw autoshutdown_time)"
        Write-Host ""
        Write-Warning "Admin Password (sensitive): Use 'terraform output vm_admin_password' to view"
    } else {
        Write-Error "Failed to retrieve outputs"
    }
}

# Function to display connection information
function Show-ConnectionInfo {
    Write-Host ""
    Write-Status "Connection Information:"
    Write-Host ""
    Write-Host "Windows VM:"
    Write-Host "  RDP: mstsc /v:$(terraform output -raw windows_vm_public_ip)"
    Write-Host "  Username: $(terraform output -raw vm_admin_username)"
    Write-Host ""
    Write-Host "Ubuntu VM:"
    Write-Host "  SSH: ssh $(terraform output -raw vm_admin_username)@$(terraform output -raw ubuntu_vm_public_ip)"
    Write-Host "  Username: $(terraform output -raw vm_admin_username)"
    Write-Host ""
    Write-Host "Get password: terraform output vm_admin_password"
    Write-Host ""
    Write-Status "Next Steps:"
    Write-Host "1. Connect to the VMs using the information above"
    Write-Host "2. Run validation scripts on the VMs:"
    Write-Host "   - Windows: PowerShell .\scripts\validate-environment.ps1"
    Write-Host "   - Linux: bash ./scripts/validate-environment.sh"
    Write-Host "3. Wait 10-15 minutes for data collection to start"
    Write-Host "4. Run KQL queries in Log Analytics Workspace to verify data ingestion"
    Write-Host "5. Check the README.md for detailed testing procedures"
}

# Function to clean up
function Remove-TemporaryFiles {
    Write-Status "Cleaning up temporary files..."
    if (Test-Path "tfplan") { Remove-Item "tfplan" -Force }
    if (Test-Path "outputs.json") { Remove-Item "outputs.json" -Force }
}

# Main deployment function
function Invoke-Deploy {
    Write-Host "=== Azure Monitor AMPLS Lab Deployment ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if we're in the right directory (should be in environments/prod)
    if (-not (Test-Path "main.tf")) {
        if (Test-Path "environments\prod\main.tf") {
            Write-Status "Changing to environments\prod directory..."
            Set-Location "environments\prod"
        } else {
            Write-Error "main.tf not found. Please run this script from the project root or environments\prod directory."
            exit 1
        }
    }
    
    # Check prerequisites
    Test-Prerequisites
    
    # Initialize Terraform
    Initialize-Terraform
    
    # Validate configuration
    Test-TerraformConfiguration
    
    # Create plan
    New-TerraformPlan
    
    # Apply configuration
    Invoke-TerraformApply
    
    # Get outputs
    Get-TerraformOutputs
    
    # Display connection information
    Show-ConnectionInfo
    
    # Cleanup
    Remove-TemporaryFiles
    
    Write-Success "Deployment completed successfully!"
}

# Function to destroy infrastructure
function Invoke-Destroy {
    Write-Warning "This will destroy all resources created by this Terraform configuration."
    $confirmation = Read-Host "Are you sure? Type 'yes' to confirm"
    
    if ($confirmation -eq "yes") {
        Write-Status "Destroying infrastructure..."
        $result = terraform destroy
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Infrastructure destroyed successfully"
        } else {
            Write-Error "Failed to destroy infrastructure"
            exit 1
        }
    } else {
        Write-Status "Destruction cancelled"
    }
}

# Function to show plan only
function Show-Plan {
    # Check if we're in the right directory (should be in environments/prod)
    if (-not (Test-Path "main.tf")) {
        if (Test-Path "environments\prod\main.tf") {
            Write-Status "Changing to environments\prod directory..."
            Set-Location "environments\prod"
        } else {
            Write-Error "main.tf not found. Please run this script from the project root or environments\prod directory."
            exit 1
        }
    }
    
    Test-Prerequisites
    Initialize-Terraform
    Test-TerraformConfiguration
    terraform plan
}

# Main script execution
switch ($Action) {
    "deploy" {
        Invoke-Deploy
    }
    "destroy" {
        Invoke-Destroy
    }
    "plan" {
        Show-Plan
    }
    "output" {
        Get-TerraformOutputs
    }
    default {
        Write-Host "Usage: .\deploy.ps1 [deploy|destroy|plan|output]"
        Write-Host "  deploy  - Deploy the infrastructure (default)"
        Write-Host "  destroy - Destroy the infrastructure"
        Write-Host "  plan    - Show what would be deployed"
        Write-Host "  output  - Show deployment outputs"
        exit 1
    }
}
