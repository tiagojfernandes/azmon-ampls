# Validation and Testing Scripts for Azure Monitor AMPLS Lab

This directory contains scripts to validate and test the Azure Monitor AMPLS lab environment.

## Scripts Overview

### validate-environment.ps1
PowerShell script to validate the Azure Monitor AMPLS configuration from a Windows VM.

### validate-environment.sh
Bash script to validate the Azure Monitor AMPLS configuration from a Linux VM.

### test-data-ingestion.kql
KQL queries to test data ingestion in Log Analytics Workspace.

## Usage

1. **Run validation from Windows VM**:
   ```powershell
   .\validate-environment.ps1
   ```

2. **Run validation from Linux VM**:
   ```bash
   chmod +x validate-environment.sh
   ./validate-environment.sh
   ```

3. **Test data ingestion in Azure Portal**:
   - Copy queries from `test-data-ingestion.kql`
   - Run in Log Analytics Workspace Logs section
