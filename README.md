# Power Platform ALM - Retainer Bot

This repository contains the Copilot Studio Bot solution with Power Automate Flows for the Retainer project.

## Repository Structure

```
/
├── pipelines/                          # Azure DevOps Pipeline definitions
│   ├── ci-cd-pipeline.yml             # Main CI/CD pipeline (build + deploy)
│   └── pr-validation-pipeline.yml     # PR validation pipeline
├── src/
│   └── solutions/
│       ├── Retainer/                  # Main bot solution (unpacked)
│       └── ConnectionRef/             # Connection references solution (unpacked)
├── config/
│   ├── environment-variables-uat.json      # UAT environment variable values
│   ├── environment-variables-prod.json     # Prod environment variable values
│   ├── deployment-settings-uat.json        # UAT connection mappings
│   └── deployment-settings-prod.json       # Prod connection mappings
├── scripts/
│   ├── Set-EnvironmentVariables.ps1   # Sets env vars during deployment
│   ├── Activate-Flows.ps1             # Activates flows after import
│   └── Publish-Bot.ps1                # Publishes bot after import
└── docs/
    └── ALM-Implementation-Guide.md    # Full implementation documentation
```

## Solutions

| Solution | Unique Name | Description |
|----------|-------------|-------------|
| Retainer | Retainer | Main solution containing Copilot Studio bot, flows, and custom table |
| Connection References | ConnectionRef | Shared connection references used by flows |

## Branching Strategy

```
main (protected)          ← Production-ready code, triggers deployments
  │
  └── develop             ← Integration branch, synced with Power Platform Dev
        │
        ├── feature/*     ← Feature development
        └── hotfix/*      ← Emergency fixes
```

## Pipeline Flow

1. **PR to `main`**: Triggers validation pipeline (export + solution checker)
2. **Merge to `main`**: Triggers CI/CD pipeline
   - **Build**: Exports solution from Dev, creates managed package
   - **UAT**: Requires approval, deploys to UAT environment
   - **Prod**: Requires approval, deploys to Production environment

## Getting Started

### Prerequisites

- Azure DevOps project with Pipelines enabled
- Service Principal with System Administrator role in all Power Platform environments
- Power Platform service connections configured in Azure DevOps

### Initial Setup

1. Complete the publisher remediation (see Implementation Guide)
2. Configure variable groups in Azure DevOps
3. Create environments with approval gates
4. Register pipelines

See `docs/ALM-Implementation-Guide.md` for detailed setup instructions.

## Configuration Files

### Environment Variables (`config/environment-variables-*.json`)

Contains environment-specific values for Power Platform environment variables:

```json
{
  "cr_ApiBaseUrl": "https://api.yourcompany.com",
  "cr_ApiKey": "your-api-key"
}
```

### Deployment Settings (`config/deployment-settings-*.json`)

Maps connection references to environment-specific connections:

```json
{
  "ConnectionReferences": [
    {
      "LogicalName": "cr_sharedcommondataserviceforapps_connectionref",
      "ConnectionId": "YOUR_CONNECTION_ID",
      "ConnectorId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
    }
  ]
}
```

## Common Tasks

### Update Environment Variables

1. Edit the appropriate `config/environment-variables-*.json` file
2. Commit and push to `develop`
3. Create PR to `main`
4. Pipeline will apply new values on deployment

### Add a New Flow

1. Create flow in Power Platform Dev environment
2. Add flow to the Retainer solution
3. Changes sync to `develop` via Git integration
4. Create PR to `main`

### Rollback

1. Navigate to the pipeline run history
2. Find the last successful deployment
3. Click "Redeploy" to the target environment

## Support

For issues with the ALM process, contact the DevOps team.

For Power Platform-specific issues, consult the [Power Platform ALM documentation](https://docs.microsoft.com/en-us/power-platform/alm/).
