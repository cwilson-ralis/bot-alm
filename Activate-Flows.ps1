<#
.SYNOPSIS
    Activates all Power Automate flows in a specified solution.

.DESCRIPTION
    This script authenticates to a Power Platform environment using a Service Principal
    and activates all cloud flows that belong to a specified solution.

.PARAMETER EnvironmentUrl
    The URL of the target Power Platform environment (e.g., https://org.crm.dynamics.com)

.PARAMETER TenantId
    Azure AD Tenant ID

.PARAMETER ClientId
    Service Principal Application (Client) ID

.PARAMETER ClientSecret
    Service Principal Client Secret

.PARAMETER SolutionName
    The unique name of the solution containing the flows

.EXAMPLE
    .\Activate-Flows.ps1 -EnvironmentUrl "https://org.crm.dynamics.com" `
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
Write-Host "Activating Flows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentUrl"
Write-Host "Solution: $SolutionName"
Write-Host ""

# Get access token
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

# Get all solution components of type workflow (type 29)
Write-Host ""
Write-Host "Finding flows in solution..." -ForegroundColor Yellow

try {
    # Component type 29 = Workflow (includes cloud flows)
    $componentsUrl = "$apiUrl/solutioncomponents?`$filter=_solutionid_value eq '$solutionId' and componenttype eq 29&`$select=objectid"
    $components = Invoke-RestMethod -Method Get -Uri $componentsUrl -Headers $headers

    if ($components.value.Count -eq 0) {
        Write-Host "No workflow components found in solution" -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Found $($components.value.Count) workflow components" -ForegroundColor Green
}
catch {
    Write-Error "Failed to get solution components: $_"
    exit 1
}

# Get workflow details and activate cloud flows
$successCount = 0
$failCount = 0
$skippedCount = 0

foreach ($component in $components.value) {
    $workflowId = $component.objectid

    try {
        # Get workflow details
        $workflowUrl = "$apiUrl/workflows($workflowId)?`$select=name,category,statecode,statuscode,clientdata"
        $workflow = Invoke-RestMethod -Method Get -Uri $workflowUrl -Headers $headers

        $workflowName = $workflow.name
        $category = $workflow.category
        $stateCode = $workflow.statecode
        $statusCode = $workflow.statuscode

        # Category 5 = Modern Flow (Cloud Flow)
        # Category 0 = Workflow
        # Category 3 = Action
        if ($category -ne 5) {
            Write-Host "  Skipping '$workflowName' (not a cloud flow, category: $category)" -ForegroundColor Gray
            $skippedCount++
            continue
        }

        Write-Host ""
        Write-Host "Processing: $workflowName" -ForegroundColor Cyan
        Write-Host "  Current State: $stateCode, Status: $statusCode"

        # State 0 = Draft, State 1 = Activated
        # Status 1 = Draft, Status 2 = Activated
        if ($stateCode -eq 1 -and $statusCode -eq 2) {
            Write-Host "  Already activated, skipping" -ForegroundColor Gray
            $successCount++
            continue
        }

        # Activate the flow
        Write-Host "  Activating..." -ForegroundColor Yellow

        $updateBody = @{
            statecode = 1
            statuscode = 2
        } | ConvertTo-Json

        $updateUrl = "$apiUrl/workflows($workflowId)"
        Invoke-RestMethod -Method Patch -Uri $updateUrl -Headers $headers -Body $updateBody

        Write-Host "  Activated successfully" -ForegroundColor Green
        $successCount++
    }
    catch {
        $errorMessage = $_.Exception.Message
        
        # Check if it's a connection-related error
        if ($errorMessage -match "connection" -or $errorMessage -match "ConnectionReference") {
            Write-Warning "  Failed to activate '$workflowName' - Connection issue: $errorMessage"
            Write-Warning "  Ensure connections are properly configured in the target environment"
        }
        else {
            Write-Warning "  Failed to activate workflow $workflowId : $errorMessage"
        }
        $failCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Flow Activation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Activated/Already Active: $successCount" -ForegroundColor Green
Write-Host "Skipped (not cloud flows): $skippedCount" -ForegroundColor Gray
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })

if ($failCount -gt 0) {
    Write-Warning "Some flows failed to activate. Check connection references and try again."
    # Don't fail the pipeline for flow activation issues - they may need manual intervention
    # exit 1
}

Write-Host ""
Write-Host "Flow activation complete!" -ForegroundColor Green
