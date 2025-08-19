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
  git clone https://github.com/tiagojfernandes/azmon-ampls.git
fi

# Navigate to the project directory
cd azmon-ampls/environments/prod

echo -e "${CYAN}Initializing Terraform...${NC}"
terraform init

echo -e "${CYAN}Planning Terraform deployment...${NC}"
terraform plan

echo -e "${CYAN}Applying Terraform configuration...${NC}"
terraform apply -auto-approve

cd ~/azmon-ampls

# Capture outputs into variables
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
JAVA_WEBAPP_NAME=$(terraform output -raw java_webapp_name)
DOTNET_WEBAPP_NAME=$(terraform output -raw dotnet_webapp_name)

# Confirm values
echo "RG=$RESOURCE_GROUP, Java=$JAVA_WEBAPP_NAME, Dotnet=$DOTNET_WEBAPP_NAME"


git clone https://github.com/Azure-Samples/ApplicationInsights-Java-Samples.git
cd ApplicationInsights-Java-Samples/maven

# Build
./mvnw package -DskipTests

# Prepare deployment folder
mkdir -p artifacts/agent
cp target/app.jar artifacts/
cp target/agent/applicationinsights-agent.jar artifacts/agent/

az webapp deploy \
  --resource-group $RESOURCE_GROUP \
  --name $JAVA_WEBAPP_NAME \
  --src-path artifacts

echo -e "${GREEN}Deployment completed successfully!${NC}"
