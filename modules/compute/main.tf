# Compute Module - Windows & Ubuntu VMs with Azure Monitor Agent

# Generate random password for VMs
resource "random_password" "vm_password" {
  length  = 16
  special = true
}

# Public IP for Windows VM (for initial access)
resource "azurerm_public_ip" "windows_vm_pip" {
  count               = var.enable_public_ips ? 1 : 0
  name                = "${var.prefix}-windows-vm-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Public IP for Ubuntu VM (for initial access)
resource "azurerm_public_ip" "ubuntu_vm_pip" {
  count               = var.enable_public_ips ? 1 : 0
  name                = "${var.prefix}-ubuntu-vm-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Network Interface for Windows VM
resource "azurerm_network_interface" "windows_vm_nic" {
  name                = "${var.prefix}-windows-vm-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.windows_vm_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ips ? azurerm_public_ip.windows_vm_pip[0].id : null
  }

  tags = var.tags
}

# Network Interface for Ubuntu VM
resource "azurerm_network_interface" "ubuntu_vm_nic" {
  name                = "${var.prefix}-ubuntu-vm-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.ubuntu_vm_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ips ? azurerm_public_ip.ubuntu_vm_pip[0].id : null
  }

  tags = var.tags
}

# Windows Server VM
resource "azurerm_windows_virtual_machine" "windows_vm" {
  name                = "${var.prefix}-windows-vm"
  computer_name       = "winvm"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password != null ? var.admin_password : random_password.vm_password.result

  network_interface_ids = [
    azurerm_network_interface.windows_vm_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
  }

  source_image_reference {
    publisher = var.windows_vm_image.publisher
    offer     = var.windows_vm_image.offer
    sku       = var.windows_vm_image.sku
    version   = var.windows_vm_image.version
  }

  identity {
    type = "SystemAssigned"
  }

  # Install Azure Monitor Agent
  provision_vm_agent = true

  tags = var.tags
}

# Ubuntu Server VM
resource "azurerm_linux_virtual_machine" "ubuntu_vm" {
  name                = "${var.prefix}-ubuntu-vm"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username

  disable_password_authentication = false
  admin_password                  = var.admin_password != null ? var.admin_password : random_password.vm_password.result

  network_interface_ids = [
    azurerm_network_interface.ubuntu_vm_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
  }

  source_image_reference {
    publisher = var.ubuntu_vm_image.publisher
    offer     = var.ubuntu_vm_image.offer
    sku       = var.ubuntu_vm_image.sku
    version   = var.ubuntu_vm_image.version
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Azure Monitor Agent Extension for Windows VM
resource "azurerm_virtual_machine_extension" "azure_monitor_agent_windows" {
  name                 = "AzureMonitorWindowsAgent"
  virtual_machine_id   = azurerm_windows_virtual_machine.windows_vm.id
  publisher            = "Microsoft.Azure.Monitor"
  type                 = "AzureMonitorWindowsAgent"
  type_handler_version = "1.0"
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_windows_virtual_machine.windows_vm
  ]

  tags = var.tags
}

/*
# Custom Script Extension for .NET Core App Deployment
resource "azurerm_virtual_machine_extension" "windows_vm_custom_script" {
  name                 = "InstallDotNetApp"
  virtual_machine_id   = azurerm_windows_virtual_machine.windows_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -Command \"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile 'dotnet-install.ps1'; & .\\dotnet-install.ps1 -Channel 8.0; $env:PATH += ';C:\\Users\\${var.admin_username}\\.dotnet'; dotnet new console -n SampleApp; Set-Location SampleApp; dotnet add package Microsoft.ApplicationInsights; dotnet add package Microsoft.ApplicationInsights.DependencyCollector; dotnet add package Microsoft.Extensions.Logging.ApplicationInsights; Set-Content -Path Program.cs -Value 'using Microsoft.ApplicationInsights; using Microsoft.ApplicationInsights.Extensibility; using System.Collections.Generic; using System.Threading.Tasks; using System; var config = new TelemetryConfiguration(); config.ConnectionString = \\\"${var.application_insights_connection_string}\\\"; var client = new TelemetryClient(config); for(int i = 0; i < 10; i++) { client.TrackEvent($$\\\"SampleEvent_{i}\\\", new Dictionary<string, string> { [\\\"iteration\\\"] = i.ToString() }); Console.WriteLine($$\\\"Sent event {i}\\\"); await Task.Delay(1000); } client.Flush(); await Task.Delay(2000);'; dotnet run\""
  })

  depends_on = [
    azurerm_virtual_machine_extension.azure_monitor_agent_windows
  ]

  tags = var.tags
}

*/

# Azure Monitor Agent Extension for Ubuntu VM
resource "azurerm_virtual_machine_extension" "azure_monitor_agent_linux" {
  name                 = "AzureMonitorLinuxAgent"
  virtual_machine_id   = azurerm_linux_virtual_machine.ubuntu_vm.id
  publisher            = "Microsoft.Azure.Monitor"
  type                 = "AzureMonitorLinuxAgent"
  type_handler_version = "1.0"
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_linux_virtual_machine.ubuntu_vm
  ]

  tags = var.tags
}

# Custom Script Extension for Python and Flask App Deployment on Ubuntu VM
resource "azurerm_virtual_machine_extension" "ubuntu_vm_custom_script" {
  name                 = "InstallPythonAndFlaskApps"
  virtual_machine_id   = azurerm_linux_virtual_machine.ubuntu_vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = jsonencode({
    commandToExecute = "sudo apt-get update -y && sudo apt-get install -y python3-pip curl && pip3 install opentelemetry-api opentelemetry-sdk azure-monitor-opentelemetry-exporter flask opentelemetry-instrumentation-flask && cat > /home/azureuser/app.py << 'PYEOF'\nimport time\nfrom opentelemetry import trace\nfrom opentelemetry.sdk.trace import TracerProvider\nfrom opentelemetry.sdk.trace.export import BatchSpanProcessor\nfrom azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter\n\ntracer_provider = TracerProvider()\nexporter = AzureMonitorTraceExporter(connection_string=\"${var.application_insights_connection_string}\")\ntracer_provider.add_span_processor(BatchSpanProcessor(exporter))\ntrace.set_tracer_provider(tracer_provider)\ntracer = trace.get_tracer(__name__)\n\nfor i in range(10):\n    with tracer.start_as_current_span(f\"work-span-{i}\"):\n        print(f\"Iteration {i}\")\n        time.sleep(1)\nPYEOF\n&& mkdir -p /home/azureuser/flask-sample && cat > /home/azureuser/flask-sample/app.py << 'FLASKEOF'\nimport os\nfrom flask import Flask\nfrom opentelemetry import trace\nfrom opentelemetry.sdk.trace import TracerProvider\nfrom opentelemetry.sdk.trace.export import BatchSpanProcessor\nfrom azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter\nfrom opentelemetry.instrumentation.flask import FlaskInstrumentor\n\nos.environ[\"AZURE_MONITOR_CONNECTION_STRING\"] = \"${var.application_insights_connection_string}\"\nprovider = TracerProvider()\nexporter = AzureMonitorTraceExporter(connection_string=os.environ[\"AZURE_MONITOR_CONNECTION_STRING\"])\nprovider.add_span_processor(BatchSpanProcessor(exporter))\ntrace.set_tracer_provider(provider)\n\napp = Flask(__name__)\nFlaskInstrumentor().instrument_app(app, tracer_provider=provider)\n\n@app.route(\"/\")\ndef index():\n    return \"Hello from Flask with OpenTelemetry!\"\n\n@app.route(\"/sleep\")\ndef sleep():\n    import time\n    time.sleep(0.5)\n    return \"Slept for 0.5 seconds\"\n\nif __name__ == \"__main__\":\n    app.run(host=\"0.0.0.0\", port=5000)\nFLASKEOF\n&& chown azureuser:azureuser /home/azureuser/app.py && chown -R azureuser:azureuser /home/azureuser/flask-sample && nohup sudo -u azureuser python3 /home/azureuser/app.py > /dev/null 2>&1 & && cd /home/azureuser/flask-sample && nohup sudo -u azureuser python3 app.py > flask.log 2>&1 & && sleep 10 && while true; do curl -s http://127.0.0.1:5000/ > /dev/null && sleep 5 && curl -s http://127.0.0.1:5000/sleep > /dev/null && sleep 5; done > /dev/null 2>&1 &"
  })

  depends_on = [
    azurerm_virtual_machine_extension.azure_monitor_agent_linux
  ]

  tags = var.tags
}

# Associate Data Collection Rule with Windows VM
resource "azurerm_monitor_data_collection_rule_association" "windows_vm" {
  name                    = "${var.prefix}-dcra-windows"
  target_resource_id      = azurerm_windows_virtual_machine.windows_vm.id
  data_collection_rule_id = var.data_collection_rule_id
  
  depends_on = [
    azurerm_windows_virtual_machine.windows_vm,
    azurerm_virtual_machine_extension.azure_monitor_agent_windows
  ]
}

# Associate Data Collection Rule with Ubuntu VM
resource "azurerm_monitor_data_collection_rule_association" "ubuntu_vm" {
  name                    = "${var.prefix}-dcra-ubuntu"
  target_resource_id      = azurerm_linux_virtual_machine.ubuntu_vm.id
  data_collection_rule_id = var.ubuntu_data_collection_rule_id
  
  depends_on = [
    azurerm_linux_virtual_machine.ubuntu_vm,
    azurerm_virtual_machine_extension.azure_monitor_agent_linux
  ]
}

# Auto-shutdown for Windows VM
resource "azurerm_dev_test_global_vm_shutdown_schedule" "windows_vm_shutdown" {
  count              = var.enable_autoshutdown ? 1 : 0
  virtual_machine_id = azurerm_windows_virtual_machine.windows_vm.id
  location           = var.location
  enabled            = true

  daily_recurrence_time = var.autoshutdown_time
  timezone              = var.autoshutdown_timezone

  notification_settings {
    enabled         = var.autoshutdown_notification_enabled
    time_in_minutes = var.autoshutdown_notification_time_minutes
    email           = var.autoshutdown_notification_email
  }

  tags = var.tags
}

# Auto-shutdown for Ubuntu VM
resource "azurerm_dev_test_global_vm_shutdown_schedule" "ubuntu_vm_shutdown" {
  count              = var.enable_autoshutdown ? 1 : 0
  virtual_machine_id = azurerm_linux_virtual_machine.ubuntu_vm.id
  location           = var.location
  enabled            = true

  daily_recurrence_time = var.autoshutdown_time
  timezone              = var.autoshutdown_timezone

  notification_settings {
    enabled         = var.autoshutdown_notification_enabled
    time_in_minutes = var.autoshutdown_notification_time_minutes
    email           = var.autoshutdown_notification_email
  }

  tags = var.tags
}
