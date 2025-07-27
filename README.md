# Azure Monitor AMPLS Lab Environment

This Terraform configuration creates a comprehensive Azure Monitor Private Link Service (AMPLS) lab environment that demonstrates how to configure Azure Monitor to accept data only from private networks. The project uses a modular structure following Terraform best practices.

## Project Structure

```
azmon-ampls/
├── modules/
│   ├── network/          # VNets, subnets, NSGs, peering
│   ├── monitor/          # Log Analytics, AMPLS, private endpoints, DNS
│   └── compute/          # Windows & Ubuntu VMs with Azure Monitor Agent
├── environments/
│   └── prod/             # Production environment configuration
├── scripts/              # Validation and testing scripts
└── README.md
```

## Architecture Overview

The lab environment consists of:

- **Hub-Spoke Network Architecture**: Two VNets connected via peering to simulate real-world scenarios
- **Azure Monitor Private Link Service (AMPLS)**: Configured to only accept private traffic
- **Log Analytics Workspace**: Connected to AMPLS with private-only ingestion and query access
- **Virtual Machines**: Windows Server 2022 and Ubuntu 22.04 LTS with Azure Monitor Agent
- **Private DNS Zones**: For proper Azure Monitor service resolution
- **Data Collection Rules**: Configured to collect performance counters, Windows events, and syslog

## Modules Overview

### Network Module (`modules/network/`)
- **Hub VNet**: Hosts the AMPLS private endpoint
- **Spoke VNet**: Hosts the virtual machines
- **VNet Peering**: Connects hub and spoke for realistic architecture
- **Network Security Groups**: Basic security rules for VM access
- **Subnets**: Properly segmented for different workloads

### Monitor Module (`modules/monitor/`)
- **Log Analytics Workspace**: Private-only configuration
- **Azure Monitor Private Link Scope**: Central AMPLS configuration
- **Private Endpoint**: Connects AMPLS to the hub network
- **Private DNS Zones**: All required zones for Azure Monitor services
- **Data Collection Rules**: Automated telemetry collection configuration

### Compute Module (`modules/compute/`)
- **Windows Server 2022 VM**: With Azure Monitor Agent
- **Ubuntu 22.04 LTS VM**: With Azure Monitor Agent
- **Network Interfaces**: Connected to the spoke subnet
- **Public IPs**: Optional for initial access (configurable)
- **Agent Extensions**: Automated AMA deployment

## Prerequisites

- Azure CLI installed and configured
- Terraform 1.0+ installed
- Appropriate Azure permissions to create resources

## Quick Start

1. **Navigate to the production environment**:
   ```bash
   cd environments/prod
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Review and customize variables** (optional):
   ```bash
   # Copy and edit terraform.tfvars if needed
   cp terraform.tfvars.example terraform.tfvars
   ```

4. **Plan the deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy the infrastructure**:
   ```bash
   terraform apply
   ```

6. **Get connection information**:
   ```bash
   terraform output
   ```

## Using the Deployment Scripts

For easier deployment, you can use the provided scripts from the project root:

```bash
# For Linux/Mac/WSL (navigate to environments/prod first)
cd environments/prod
../../deploy.sh deploy

# For Windows PowerShell (navigate to environments/prod first)
cd environments/prod
../../deploy.ps1 deploy
```

## Configuration Details

### Azure Monitor Private Link Service (AMPLS)

The AMPLS is configured with:
- **Ingestion Access Mode**: PrivateOnly - only accepts data from private networks
- **Query Access Mode**: PrivateOnly - only allows queries from private networks
- **Private Endpoint**: Deployed in the hub VNet with proper DNS configuration

### Log Analytics Workspace

The workspace is configured with:
- **Internet Ingestion**: Disabled (enforces private link only)
- **Internet Query**: Disabled (enforces private link only)
- **Retention**: 30 days
- **SKU**: PerGB2018

### Data Collection

Data Collection Rules are configured to collect:
- **Performance Counters**: CPU, Memory, Disk, Network metrics (60-second intervals)
- **Windows Event Logs**: Application, Security, System events
- **Syslog**: All facilities and log levels for Linux systems

### Virtual Machines

Both VMs are configured with:
- **Azure Monitor Agent**: Latest version with auto-upgrade
- **Data Collection Rule Associations**: Automatically configured
- **Network Security Groups**: Allow RDP (3389) and SSH (22) access
- **Public IPs**: For initial setup and testing (can be removed after deployment)

## Testing the Environment

### 1. Verify Private Connectivity

Connect to either VM and test DNS resolution:

**Windows VM** (PowerShell):
```powershell
# Test Azure Monitor endpoint resolution
nslookup oms.opinsights.azure.com
nslookup dc.services.visualstudio.com

# Check if endpoints resolve to private IPs (10.x.x.x range)
```

**Ubuntu VM** (Bash):
```bash
# Test Azure Monitor endpoint resolution
dig oms.opinsights.azure.com
dig dc.services.visualstudio.com

# Check if endpoints resolve to private IPs (10.x.x.x range)
```

### 2. Verify Data Ingestion

In the Azure Portal:
1. Navigate to the Log Analytics Workspace
2. Go to Logs section
3. Run queries to verify data ingestion:

```kql
// Check for performance data
Perf
| where TimeGenerated > ago(1h)
| summarize count() by Computer, CounterName

// Check for Windows events
Event
| where TimeGenerated > ago(1h)
| summarize count() by Computer, EventLevelName

// Check for Syslog data
Syslog
| where TimeGenerated > ago(1h)
| summarize count() by Computer, Facility
```

### 3. Verify Private Link Status

Check the AMPLS status:
1. Navigate to Azure Monitor Private Link Scope in the portal
2. Verify connected resources show the Log Analytics Workspace
3. Check private endpoint connections are approved and connected

## Customization

### Variables

Key variables you can customize in `environments/prod/terraform.tfvars`:

```hcl
# Basic settings
prefix              = "your-prefix"
resource_group_name = "rg-your-ampls-lab"
location           = "West Europe"

# VM settings
admin_username    = "youradmin"
vm_size          = "Standard_B2ms"  # Larger VMs if needed
enable_public_ips = false          # Use false for production

# Network settings
hub_vnet_address_space    = ["172.16.0.0/16"]
spoke_vnet_address_space  = ["172.17.0.0/16"]

# Tags
tags = {
  Environment = "Lab"
  Project     = "Your Project"
  Owner       = "Your Name"
}
```

### Adding New Environments

To create additional environments (e.g., dev, staging):

1. **Create a new environment directory**:
   ```bash
   mkdir environments/dev
   ```

2. **Copy the prod configuration**:
   ```bash
   cp environments/prod/* environments/dev/
   ```

3. **Customize variables** for the new environment in `environments/dev/terraform.tfvars`

### Module Customization

Each module can be customized independently:

- **Network Module**: Modify subnet ranges, add additional subnets, or configure different NSG rules
- **Monitor Module**: Adjust data collection rules, add more performance counters, or configure different retention policies  
- **Compute Module**: Change VM sizes, add more VMs, or use different OS images

## Security Considerations

### Production Recommendations

1. **Remove Public IPs**: After initial setup, remove public IPs and use Azure Bastion or VPN
2. **Implement Azure Firewall**: Add Azure Firewall for outbound filtering
3. **Use Managed Identity**: Configure VMs with managed identities instead of passwords
4. **Network Segmentation**: Implement additional subnets and NSGs for micro-segmentation
5. **Key Vault**: Store VM passwords and certificates in Azure Key Vault

### Current Security Features

- Network Security Groups with minimal required access
- Private-only Azure Monitor access
- Strong random passwords for VMs
- Latest OS images with security updates

## Troubleshooting

### Common Issues

1. **Agent Not Reporting Data**:
   - Check Data Collection Rule associations
   - Verify private endpoint DNS resolution
   - Check NSG rules allow outbound HTTPS (443)

2. **DNS Resolution Issues**:
   - Verify private DNS zone links to both VNets
   - Check VNet peering is properly configured
   - Restart VMs if DNS cache is stale

3. **Private Endpoint Connection**:
   - Ensure private endpoint network policies are disabled
   - Check subnet has sufficient IP addresses
   - Verify AMPLS configuration

### Useful Commands

```bash
# Navigate to production environment
cd environments/prod

# Check Terraform state
terraform state list

# View specific resource
terraform state show module.monitor.azurerm_monitor_private_link_scope.main

# Force recreation of problematic resource
terraform taint module.network.azurerm_virtual_network_peering.hub_to_spoke
terraform apply

# Get sensitive outputs
terraform output -json | jq '.vm_admin_password.value'
```

## Cleanup

To destroy all resources:

```bash
cd environments/prod
terraform destroy
```

**Warning**: This will permanently delete all resources created by this configuration.

## Cost Considerations

### Estimated Monthly Costs (East US pricing)

- **Virtual Machines**: ~$60-120/month (depending on size and runtime)
- **Log Analytics Workspace**: ~$2.30/GB ingested + $0.10/GB retention
- **Private Endpoints**: ~$7.20/month per endpoint
- **VNet Peering**: ~$0.01/GB transferred
- **Public IPs**: ~$3.65/month per IP

### Cost Optimization Tips

1. **Auto-shutdown**: Enable auto-shutdown for VMs during non-testing hours
2. **Smaller VM SKUs**: Use B1s for minimal testing requirements
3. **Reduce Retention**: Lower Log Analytics retention period
4. **Remove Public IPs**: Use Azure Bastion or VPN instead

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for improvements.

## License

This project is provided as-is for educational and testing purposes.
