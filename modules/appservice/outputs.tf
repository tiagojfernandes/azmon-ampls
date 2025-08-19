output "plan_id"                 { value = azurerm_service_plan.plan.id }
output "dotnet_webapp_id"        { value = azurerm_linux_web_app.dotnet.id }
output "java_webapp_id"          { value = azurerm_linux_web_app.java.id }
output "dotnet_webapp_name"      { value = azurerm_linux_web_app.dotnet.name }
output "java_webapp_name"        { value = azurerm_linux_web_app.java.name }
output "dotnet_default_hostname" { value = azurerm_linux_web_app.dotnet.default_hostname }
output "java_default_hostname"   { value = azurerm_linux_web_app.java.default_hostname }
