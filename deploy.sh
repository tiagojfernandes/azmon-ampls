#!/bin/bash

# Azure Monitor AMPLS Lab Deployment Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Clone the repo (skip if already cloned)
if [ ! -d "azmon-ampls" ]; then
  echo -e "${CYAN}Cloning azmon-ampls repository...${NC}"
  git clone https://github.com/damanue/azmon-ampls.git
fi

# Navigate to the project directory
cd azmon-ampls/environments/prod

echo -e "${CYAN}Initializing Terraform...${NC}"
terraform init

echo -e "${CYAN}Planning Terraform deployment...${NC}"
terraform plan

echo -e "${CYAN}Applying Terraform configuration...${NC}"
terraform apply -auto-approve

echo -e "${GREEN}Deployment completed successfully!${NC}"
