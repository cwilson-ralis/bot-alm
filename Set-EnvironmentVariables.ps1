<#
.SYNOPSIS
    Sets Power Platform environment variable values for a target environment.

.DESCRIPTION
    This script authenticates to a Power Platform environment using a Service Principal
    and updates environment variable values based on a JSON configuration file.

.PARAMETER EnvironmentUrl
    The URL of the target Power Platform environment (e.g., https://org.crm.dynamics.com)

.PARAMETER TenantId
    Azure AD Tenant ID

.PARAMETER ClientId
    Service Principal Application (Client) ID

.PARAMETER ClientSecret
    Service Principal Client Secret

.PARAMETER ConfigFile
    Path to JSON file containing environment variable values

.EXAMPLE
    .\Set-EnvironmentVariables.ps1 -EnvironmentUrl "https://org.crm.dynamics.com" `
        -TenantId "xxx" -ClientId "xxx" -ClientSecret "xxx" `
        -ConfigFile "./config/environment-variables-uat.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$ConfigFile
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setting Environment Variables" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentUrl"
Write-Host "Config File: $ConfigFile"
Write-Host ""

# Validate config file exists
if (-not (Test-Path $ConfigFile)) {
    Write-Error "Configuration file not found: $ConfigFile"
    exit 1
}

# Read configuration
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
Write-Host "Found $($config.PSObject.Properties.Count) environment variables to set" -ForegroundColor Yellow

# Get access token
Write-Host ""
Write-Host "Acquiring access token..." -ForegroundColor Yellow

$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    resource      = $EnvironmentUrl
}

try {
    $tokenResponse = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $tokenBody

    $accessToken = $tokenResponse.access_token
    Write-Host "Access token acquired successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to acquire access token: $_"
    exit 1
}

# Set up headers for Dataverse API
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
    "Accept" = "application/json"
    "Content-Type" = "application/json; charset=utf-8"
    "Prefer" = "return=representation"
}

$apiUrl = "$EnvironmentUrl/api/data/v9.2"

# Get all environment variable definitions
Write-Host ""
Write-Host "Retrieving environment variable definitions..." -ForegroundColor Yellow

try {
    $envVarDefsUrl = "$apiUrl/environmentvariabledefinitions?`$select=environmentvariabledefinitionid,schemaname,displayname"
    $envVarDefs = Invoke-RestMethod -Method Get -Uri $envVarDefsUrl -Headers $headers
    Write-Host "Found $($envVarDefs.value.Count) environment variable definitions" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve environment variable definitions: $_"
    exit 1
}

# Process each environment variable in config
$successCount = 0
$failCount = 0

foreach ($property in $config.PSObject.Properties) {
    $schemaName = $property.Name
    $newValue = $property.Value

    Write-Host ""
    Write-Host "Processing: $schemaName" -ForegroundColor Cyan

    # Find the environment variable definition
    $envVarDef = $envVarDefs.value | Where-Object { $_.schemaname -eq $schemaName }

    if (-not $envVarDef) {
        Write-Warning "Environment variable definition not found: $schemaName"
        $failCount++
        continue
    }

    $definitionId = $envVarDef.environmentvariabledefinitionid
    Write-Host "  Definition ID: $definitionId"

    # Check if a value record already exists
    try {
        $valueUrl = "$apiUrl/environmentvariablevalues?`$filter=_environmentvariabledefinitionid_value eq '$definitionId'&`$select=environmentvariablevalueid,value"
        $existingValues = Invoke-RestMethod -Method Get -Uri $valueUrl -Headers $headers

        if ($existingValues.value.Count -gt 0) {
            # Update existing value
            $valueId = $existingValues.value[0].environmentvariablevalueid
            $currentValue = $existingValues.value[0].value

            if ($currentValue -eq $newValue) {
                Write-Host "  Value unchanged, skipping" -ForegroundColor Gray
                $successCount++
                continue
            }

            Write-Host "  Updating existing value (ID: $valueId)"
            
            $updateBody = @{
                value = $newValue
            } | ConvertTo-Json

            $updateUrl = "$apiUrl/environmentvariablevalues($valueId)"
            Invoke-RestMethod -Method Patch -Uri $updateUrl -Headers $headers -Body $updateBody
            Write-Host "  Updated successfully" -ForegroundColor Green
        }
        else {
            # Create new value record
            Write-Host "  Creating new value record"
            
            $createBody = @{
                "value" = $newValue
                "EnvironmentVariableDefinitionId@odata.bind" = "/environmentvariabledefinitions($definitionId)"
            } | ConvertTo-Json

            $createUrl = "$apiUrl/environmentvariablevalues"
            Invoke-RestMethod -Method Post -Uri $createUrl -Headers $headers -Body $createBody
            Write-Host "  Created successfully" -ForegroundColor Green
        }

        $successCount++
    }
    catch {
        Write-Error "  Failed to set value: $_"
        $failCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment Variables Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

if ($failCount -gt 0) {
    Write-Error "Some environment variables failed to set"
    exit 1
}

Write-Host ""
Write-Host "Environment variables set successfully!" -ForegroundColor Green
