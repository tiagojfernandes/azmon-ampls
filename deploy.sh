#!/bin/bash

# Azure Monitor AMPLS Lab Deployment Script
# Usage: ./deploy.sh [custom-prefix]
# Example: ./deploy.sh "mylab" (creates app-mylab-java, app-mylab-dotnet)
# If no prefix provided, uses azmon-MMDD-HHMM to avoid conflicts

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

# Allow user to specify a custom prefix to avoid naming conflicts
TIMESTAMP=$(date +%m%d-%H%M)
CUSTOM_PREFIX=${1:-"azmon-${TIMESTAMP}"}
echo -e "${CYAN}Using prefix: ${CUSTOM_PREFIX}${NC}"

echo -e "${CYAN}Initializing Terraform...${NC}"
terraform init

echo -e "${CYAN}Planning Terraform deployment...${NC}"
terraform plan -var="app_service_prefix=${CUSTOM_PREFIX}"

echo -e "${CYAN}Applying Terraform configuration...${NC}"
terraform apply -auto-approve -var="app_service_prefix=${CUSTOM_PREFIX}"

echo -e "${GREEN}Terraform deployment completed successfully!${NC}"

# Capture outputs into variables (while still in the terraform directory)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
APP_SERVICE=$(terraform output -raw app_service_plan_name)
JAVA_WEBAPP_NAME=$(terraform output -raw java_webapp_name)
DOTNET_WEBAPP_NAME=$(terraform output -raw dotnet_webapp_name)
NODE_WEBAPP_NAME=$(terraform output -raw node_webapp_name)

# Confirm values
echo "RG=$RESOURCE_GROUP, APP_SERV=$APP_SERVICE, Java=$JAVA_WEBAPP_NAME, Dotnet=$DOTNET_WEBAPP_NAME, Node=$NODE_WEBAPP_NAME"

# Wait for App Service to be fully ready for deployments
echo -e "${YELLOW}Waiting for App Services to be fully initialized...${NC}"
sleep 60

# Optionally, verify App Service is responding (wait up to 3 minutes)
echo -e "${CYAN}Checking if Java App Service is responding...${NC}"
for i in {1..18}; do
    if curl -s -o /dev/null -w "%{http_code}" "https://${JAVA_WEBAPP_NAME}.azurewebsites.net" | grep -q "200\|503\|404"; then
        echo -e "${GREEN}Java App Service is responding!${NC}"
        break
    fi
    echo "Attempt $i/18: App Service not ready yet, waiting 10 more seconds..."
    sleep 10
done

# Navigate back to the project root for the Java sample deployment
cd ../../

# Deploy Java Application
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


# Deploy Node.js Application
cd ../
echo -e "${CYAN}Deploying Node.js sample application...${NC}"

# Check if the repository already exists
if [ ! -d "node-ai-demo" ]; then
    git clone https://github.com/tiagojfernandes/node-ai-demo.git
fi

cd node-ai-demo

# Install dependencies locally first to ensure they're available
echo -e "${CYAN}Installing Node.js dependencies...${NC}"
npm install

# Fix security vulnerabilities  
npm audit fix --force

# Create a deployment package with node_modules included
echo -e "${CYAN}Creating deployment package...${NC}"
zip -r ../node-app.zip . -x "*.git*" "*.vscode*" "README.md"

# Deploy using az webapp deploy (which preserves node_modules)
echo -e "${CYAN}Deploying to Azure App Service...${NC}"
az webapp deploy \
  --resource-group $RESOURCE_GROUP \
  --name $NODE_WEBAPP_NAME \
  --src-path ../node-app.zip \
  --type zip

# Wait a moment for deployment to process
echo -e "${YELLOW}Waiting for Node.js deployment to complete...${NC}"
sleep 30

# Verify the deployment worked
echo -e "${CYAN}Checking Node.js app deployment status...${NC}"
for i in {1..12}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${NODE_WEBAPP_NAME}.azurewebsites.net/healthz" || echo "000")
    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "${GREEN}Node.js app is responding successfully!${NC}"
        break
    fi
    echo "Attempt $i/12: Node.js app not ready yet (HTTP $HTTP_CODE), waiting 10 more seconds..."
    sleep 10
done

echo -e "${GREEN}Node.js application deployed to $NODE_WEBAPP_NAME${NC}"
echo -e "${CYAN}Node.js app URL: https://$NODE_WEBAPP_NAME.azurewebsites.net${NC}"
echo -e "${CYAN}Health check: https://$NODE_WEBAPP_NAME.azurewebsites.net/healthz${NC}"

# Cleanup
rm -f ../node-app.zip

echo -e "${GREEN}All deployments completed successfully!${NC}"
