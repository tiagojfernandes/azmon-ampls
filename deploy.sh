#!/bin/bash

# Azure Monitor AMPLS Lab Deployment Script
# This script helps deploy and validate the Azure Monitor AMPLS lab environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command_exists terraform; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    else
        terraform_version=$(terraform version -json | jq -r '.terraform_version')
        print_success "Terraform is installed (version: $terraform_version)"
    fi
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        print_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    else
        az_version=$(az version --output json | jq -r '.["azure-cli"]')
        print_success "Azure CLI is installed (version: $az_version)"
    fi
    
    # Check if jq is installed
    if ! command_exists jq; then
        print_warning "jq is not installed. Some features may not work properly."
    fi
    
    # Check Azure CLI login status
    if ! az account show >/dev/null 2>&1; then
        print_error "You are not logged in to Azure CLI. Please run 'az login' first."
        exit 1
    else
        subscription_name=$(az account show --query name -o tsv)
        print_success "Logged in to Azure (subscription: $subscription_name)"
    fi
}

# Function to initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    
    if terraform init; then
        print_success "Terraform initialized successfully"
    else
        print_error "Failed to initialize Terraform"
        exit 1
    fi
}

# Function to validate Terraform configuration
validate_terraform() {
    print_status "Validating Terraform configuration..."
    
    if terraform validate; then
        print_success "Terraform configuration is valid"
    else
        print_error "Terraform configuration validation failed"
        exit 1
    fi
}

# Function to plan Terraform deployment
plan_terraform() {
    print_status "Creating Terraform plan..."
    
    if terraform plan -out=tfplan; then
        print_success "Terraform plan created successfully"
        echo ""
        print_warning "Review the plan above. Press Enter to continue with deployment or Ctrl+C to cancel."
        read -r
    else
        print_error "Failed to create Terraform plan"
        exit 1
    fi
}

# Function to apply Terraform configuration
apply_terraform() {
    print_status "Applying Terraform configuration..."
    
    if terraform apply tfplan; then
        print_success "Terraform deployment completed successfully"
    else
        print_error "Terraform deployment failed"
        exit 1
    fi
}

# Function to get outputs
get_outputs() {
    print_status "Retrieving deployment outputs..."
    
    if terraform output -json > outputs.json; then
        print_success "Outputs saved to outputs.json"
        
        # Display key information
        echo ""
        print_status "Deployment Summary:"
        echo "Resource Group: $(terraform output -raw resource_group_name)"
        echo "Log Analytics Workspace: $(terraform output -raw log_analytics_workspace_name)"
        echo "AMPLS Name: $(terraform output -raw ampls_name)"
        echo "Windows VM Public IP: $(terraform output -raw windows_vm_public_ip)"
        echo "Ubuntu VM Public IP: $(terraform output -raw ubuntu_vm_public_ip)"
        echo "Admin Username: $(terraform output -raw vm_admin_username)"
        echo "Auto-shutdown: $(terraform output -raw autoshutdown_time)"
        echo ""
        print_warning "Admin Password (sensitive): Use 'terraform output vm_admin_password' to view"
    else
        print_error "Failed to retrieve outputs"
    fi
}

# Function to display connection information
display_connection_info() {
    echo ""
    print_status "Connection Information:"
    echo ""
    echo "Windows VM:"
    echo "  RDP: mstsc /v:$(terraform output -raw windows_vm_public_ip)"
    echo "  Username: $(terraform output -raw vm_admin_username)"
    echo ""
    echo "Ubuntu VM:"
    echo "  SSH: ssh $(terraform output -raw vm_admin_username)@$(terraform output -raw ubuntu_vm_public_ip)"
    echo "  Username: $(terraform output -raw vm_admin_username)"
    echo ""
    echo "Get password: terraform output vm_admin_password"
    echo ""
    print_status "Next Steps:"
    echo "1. Connect to the VMs using the information above"
    echo "2. Run validation scripts on the VMs:"
    echo "   - Windows: PowerShell ./scripts/validate-environment.ps1"
    echo "   - Linux: bash ./scripts/validate-environment.sh"
    echo "3. Wait 10-15 minutes for data collection to start"
    echo "4. Run KQL queries in Log Analytics Workspace to verify data ingestion"
    echo "5. Check the README.md for detailed testing procedures"
}

# Function to clean up
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -f tfplan outputs.json
}

# Main execution flow
main() {
    echo "=== Azure Monitor AMPLS Lab Deployment ==="
    echo ""
    
    # Check if we're in the right directory (should be in environments/prod)
    if [[ ! -f "main.tf" ]]; then
        if [[ -f "environments/prod/main.tf" ]]; then
            print_status "Changing to environments/prod directory..."
            cd environments/prod
        else
            print_error "main.tf not found. Please run this script from the project root or environments/prod directory."
            exit 1
        fi
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Initialize Terraform
    init_terraform
    
    # Validate configuration
    validate_terraform
    
    # Create plan
    plan_terraform
    
    # Apply configuration
    apply_terraform
    
    # Get outputs
    get_outputs
    
    # Display connection information
    display_connection_info
    
    # Cleanup
    cleanup
    
    print_success "Deployment completed successfully!"
}

# Function to destroy infrastructure
destroy() {
    print_warning "This will destroy all resources created by this Terraform configuration."
    echo -n "Are you sure? Type 'yes' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" == "yes" ]]; then
        print_status "Destroying infrastructure..."
        if terraform destroy; then
            print_success "Infrastructure destroyed successfully"
        else
            print_error "Failed to destroy infrastructure"
            exit 1
        fi
    else
        print_status "Destruction cancelled"
    fi
}

# Script arguments handling
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "destroy")
        destroy
        ;;
    "plan")
        # Check if we're in the right directory
        if [[ ! -f "main.tf" ]]; then
            if [[ -f "environments/prod/main.tf" ]]; then
                print_status "Changing to environments/prod directory..."
                cd environments/prod
            else
                print_error "main.tf not found. Please run this script from the project root or environments/prod directory."
                exit 1
            fi
        fi
        check_prerequisites
        init_terraform
        validate_terraform
        terraform plan
        ;;
    "output")
        get_outputs
        ;;
    *)
        echo "Usage: $0 [deploy|destroy|plan|output]"
        echo "  deploy  - Deploy the infrastructure (default)"
        echo "  destroy - Destroy the infrastructure"
        echo "  plan    - Show what would be deployed"
        echo "  output  - Show deployment outputs"
        exit 1
        ;;
esac
