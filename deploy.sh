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

echo -e "${GREEN}Terraform deployment completed successfully!${NC}"

# Capture outputs into variables (while still in the terraform directory)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
JAVA_WEBAPP_NAME=$(terraform output -raw java_webapp_name)
DOTNET_WEBAPP_NAME=$(terraform output -raw dotnet_webapp_name)

# Confirm values
echo "RG=$RESOURCE_GROUP, Java=$JAVA_WEBAPP_NAME, Dotnet=$DOTNET_WEBAPP_NAME"

# Navigate back to the project root for the Java sample deployment
cd ../../


git clone https://github.com/Azure-Samples/ApplicationInsights-Java-Samples.git
cd ApplicationInsights-Java-Samples

echo -e "${CYAN}Building Java sample application...${NC}"

# Check if Java is available
if ! command -v java &> /dev/null; then
    echo -e "${YELLOW}Java is not installed or not in PATH. Skipping Java application build.${NC}"
    echo -e "${YELLOW}You can manually build and deploy the Java app later with:${NC}"
    echo -e "${YELLOW}  cd ApplicationInsights-Java-Samples${NC}"
    echo -e "${YELLOW}  ./mvnw package -DskipTests -pl maven${NC}"
    echo -e "${YELLOW}  az webapp deploy --resource-group $RESOURCE_GROUP --name $JAVA_WEBAPP_NAME --src-path maven/target/app.jar${NC}"
else
    # Build the maven project from the root directory using the appropriate wrapper
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows environment
        ./mvnw.cmd package -DskipTests -pl maven
    else
        # Unix/Linux environment
        ./mvnw package -DskipTests -pl maven
    fi

    # Check if build was successful
    if [ -f "maven/target/app.jar" ]; then
        echo -e "${GREEN}Java application built successfully!${NC}"
        
        # Check what we have in target directory
        echo -e "${CYAN}Contents of maven/target:${NC}"
        ls -la maven/target/
        
        # Prepare deployment directory with proper structure
        rm -rf deploy_temp  # Clean up any existing directory
        mkdir -p deploy_temp
        
        # Copy files and verify
        cp maven/target/app.jar deploy_temp/
        if [ -d "maven/target/agent" ]; then
            cp -r maven/target/agent deploy_temp/
            echo -e "${CYAN}Copied agent directory${NC}"
        else
            echo -e "${YELLOW}Warning: agent directory not found in maven/target/${NC}"
        fi
        
        # Show what we're deploying
        echo -e "${CYAN}Contents of deploy_temp:${NC}"
        ls -la deploy_temp/
        
        # Verify permissions
        chmod -R 755 deploy_temp
        
        # Deploy the Java application (directory structure)
        cd deploy_temp
        zip -r ../app_with_agent.zip .
        cd ..
        
        az webapp deploy \
          --resource-group $RESOURCE_GROUP \
          --name $JAVA_WEBAPP_NAME \
          --src-path app_with_agent.zip \
          --type zip
          
        echo -e "${GREEN}Java application deployed to $JAVA_WEBAPP_NAME${NC}"
        
        # Cleanup
        rm -rf deploy_temp
        rm -f app_with_agent.zip
    else
        echo -e "${RED}Build failed - app.jar not found${NC}"
    fi
fi

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${CYAN}Resources deployed:${NC}"
echo -e "  Resource Group: $RESOURCE_GROUP"
echo -e "  Java Web App: $JAVA_WEBAPP_NAME (https://$JAVA_WEBAPP_NAME.azurewebsites.net)"
echo -e "  .NET Web App: $DOTNET_WEBAPP_NAME (https://$DOTNET_WEBAPP_NAME.azurewebsites.net)"
echo -e "${CYAN}Note: Application Insights is configured for both web apps with private connectivity through AMPLS.${NC}"
