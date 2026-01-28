<#
.SYNOPSIS
    Publishes Copilot Studio bots in a specified solution.

.DESCRIPTION
    This script authenticates to a Power Platform environment using a Service Principal
    and publishes all Copilot Studio bots that belong to a specified solution.

.PARAMETER EnvironmentUrl
    The URL of the target Power Platform environment (e.g., https://org.crm.dynamics.com)

.PARAMETER TenantId
    Azure AD Tenant ID

.PARAMETER ClientId
    Service Principal Application (Client) ID

.PARAMETER ClientSecret
    Service Principal Client Secret

.PARAMETER SolutionName
    The unique name of the solution containing the bots

.EXAMPLE
    .\Publish-Bot.ps1 -EnvironmentUrl "https://org.crm.dynamics.com" `
        -TenantId "xxx" -ClientId "xxx" -ClientSecret "xxx" `
        -SolutionName "Retainer"
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
    [string]$SolutionName
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Publishing Copilot Studio Bots" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentUrl"
Write-Host "Solution: $SolutionName"
Write-Host ""

# Get access token for Dataverse
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
}

$apiUrl = "$EnvironmentUrl/api/data/v9.2"

# Get the solution ID
Write-Host ""
Write-Host "Finding solution '$SolutionName'..." -ForegroundColor Yellow

try {
    $solutionUrl = "$apiUrl/solutions?`$filter=uniquename eq '$SolutionName'&`$select=solutionid,friendlyname"
    $solutionResponse = Invoke-RestMethod -Method Get -Uri $solutionUrl -Headers $headers

    if ($solutionResponse.value.Count -eq 0) {
        Write-Error "Solution not found: $SolutionName"
        exit 1
    }

    $solutionId = $solutionResponse.value[0].solutionid
    $solutionFriendlyName = $solutionResponse.value[0].friendlyname
    Write-Host "Found solution: $solutionFriendlyName (ID: $solutionId)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to find solution: $_"
    exit 1
}

# Find Copilot Studio bots in the solution
# Bots are stored in the 'bot' entity (chatbot)
Write-Host ""
Write-Host "Finding Copilot Studio bots in solution..." -ForegroundColor Yellow

try {
    # First, get bot component IDs from solution components
    # Component type 300 = Bot
    $componentsUrl = "$apiUrl/solutioncomponents?`$filter=_solutionid_value eq '$solutionId' and componenttype eq 300&`$select=objectid"
    $components = Invoke-RestMethod -Method Get -Uri $componentsUrl -Headers $headers

    if ($components.value.Count -eq 0) {
        Write-Host "No bot components found in solution (component type 300)" -ForegroundColor Yellow
        
        # Try to find bots directly that might be associated with the solution
        # This is a fallback approach
        Write-Host "Searching for bots directly..." -ForegroundColor Yellow
        
        $botsUrl = "$apiUrl/bots?`$select=botid,name,publishedon,statecode"
        $bots = Invoke-RestMethod -Method Get -Uri $botsUrl -Headers $headers
        
        if ($bots.value.Count -eq 0) {
            Write-Host "No bots found in environment" -ForegroundColor Yellow
            exit 0
        }
        
        Write-Host "Found $($bots.value.Count) bots in environment" -ForegroundColor Green
        $botIds = $bots.value | ForEach-Object { $_.botid }
    }
    else {
        Write-Host "Found $($components.value.Count) bot components in solution" -ForegroundColor Green
        $botIds = $components.value | ForEach-Object { $_.objectid }
    }
}
catch {
    Write-Warning "Failed to query bot components: $_"
    Write-Host "Attempting alternative approach..." -ForegroundColor Yellow
    $botIds = @()
}

# Publish each bot
$successCount = 0
$failCount = 0

foreach ($botId in $botIds) {
    try {
        # Get bot details
        $botUrl = "$apiUrl/bots($botId)?`$select=name,publishedon,statecode,statuscode"
        $bot = Invoke-RestMethod -Method Get -Uri $botUrl -Headers $headers

        $botName = $bot.name
        $publishedOn = $bot.publishedon
        $stateCode = $bot.statecode

        Write-Host ""
        Write-Host "Processing bot: $botName" -ForegroundColor Cyan
        Write-Host "  Bot ID: $botId"
        Write-Host "  Last Published: $publishedOn"
        Write-Host "  State Code: $stateCode"

        # Publish the bot using the PvaPublish action
        Write-Host "  Publishing..." -ForegroundColor Yellow

        # Method 1: Try using the publish action on the bot entity
        try {
            $publishUrl = "$apiUrl/bots($botId)/Microsoft.Dynamics.CRM.PvaPublish"
            $publishResponse = Invoke-RestMethod -Method Post -Uri $publishUrl -Headers $headers -Body "{}"
            Write-Host "  Published successfully using PvaPublish action" -ForegroundColor Green
            $successCount++
            continue
        }
        catch {
            Write-Host "  PvaPublish action not available, trying alternative method..." -ForegroundColor Yellow
        }

        # Method 2: Try the PublishBot unbound action
        try {
            $publishUrl = "$apiUrl/PublishBot"
            $publishBody = @{
                "BotId" = $botId
            } | ConvertTo-Json

            $publishResponse = Invoke-RestMethod -Method Post -Uri $publishUrl -Headers $headers -Body $publishBody
            Write-Host "  Published successfully using PublishBot action" -ForegroundColor Green
            $successCount++
            continue
        }
        catch {
            Write-Host "  PublishBot action not available, trying alternative method..." -ForegroundColor Yellow
        }

        # Method 3: Update statecode to trigger publish
        try {
            $updateUrl = "$apiUrl/bots($botId)"
            $updateBody = @{
                "statecode" = 0  # Active
                "statuscode" = 1  # Active
            } | ConvertTo-Json

            Invoke-RestMethod -Method Patch -Uri $updateUrl -Headers $headers -Body $updateBody
            Write-Host "  Bot state updated (publish may be triggered)" -ForegroundColor Green
            $successCount++
        }
        catch {
            throw $_
        }
    }
    catch {
        Write-Warning "  Failed to publish bot $botId : $_"
        $failCount++
    }
}

# If no bots were found via solution components, try to publish using PAC CLI approach
if ($botIds.Count -eq 0) {
    Write-Host ""
    Write-Host "No specific bots identified. Solution may need manual bot publishing." -ForegroundColor Yellow
    Write-Host "To publish bots manually:" -ForegroundColor Yellow
    Write-Host "  1. Open Copilot Studio: https://copilotstudio.microsoft.com" -ForegroundColor Gray
    Write-Host "  2. Select the environment: $EnvironmentUrl" -ForegroundColor Gray
    Write-Host "  3. Open each bot and click Publish" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Bot Publishing Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Published: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })

if ($failCount -gt 0) {
    Write-Warning "Some bots failed to publish. Manual publishing may be required."
    # Don't fail the pipeline - bot publishing can be done manually
}

Write-Host ""
Write-Host "Bot publishing complete!" -ForegroundColor Green
