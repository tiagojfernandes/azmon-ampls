# Azure Monitor AMPLS Lab - Quick Start

This project provides a modular Terraform configuration for deploying an Azure Monitor Private Link Service (AMPLS) lab environment.

## 🚀 Quick Start

### Option 1: Using Deployment Scripts (Recommended)

1. **Navigate to the production environment**:
   ```bash
   cd environments/prod
   ```

2. **Run the deployment script**:
   ```bash
   # Linux/Mac/WSL
   ../../deploy.sh deploy
   
   # Windows PowerShell  
   ../../deploy.ps1 deploy
   ```

### Option 2: Manual Terraform Commands

1. **Navigate to the production environment**:
   ```bash
   cd environments/prod
   ```

2. **Deploy with Terraform**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## 📁 Project Structure

```
azmon-ampls/
├── modules/              # Reusable Terraform modules
│   ├── network/         # VNets, subnets, NSGs
│   ├── monitor/         # Log Analytics, AMPLS, DNS
│   └── compute/         # VMs with Azure Monitor Agent
├── environments/
│   └── prod/           # Production environment
├── scripts/            # Validation scripts
└── README.md          # Full documentation
```

## 📖 Full Documentation

For complete documentation, architecture details, and advanced configuration options, see the main [README.md](README.md).

## 🔧 Quick Configuration

Copy and customize the example variables:
```bash
cd environments/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred settings
```

## 🧪 Testing

After deployment, use the validation scripts:
- **Windows VMs**: `.\scripts\validate-environment.ps1`
- **Linux VMs**: `./scripts/validate-environment.sh`
- **Log Analytics**: Use queries from `scripts/test-data-ingestion.kql`
