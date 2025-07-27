# Azure Monitor AMPLS Lab - Quick Start

## ⚠️ UNDER DEVELOPMENT ⚠️

**This project is currently under active development and is not ready for production use.**

Please check back later for the complete quick start guide and implementation.

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
