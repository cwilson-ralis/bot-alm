# Power Platform ALM Implementation Guide
## Copilot Studio Bots with Power Automate Flows

**Version:** 1.0  
**Date:** January 2026  
**Solutions:** Retainer, ConnectionRef

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Phase 1: Publisher Remediation](#3-phase-1-publisher-remediation)
4. [Phase 2: Azure DevOps Configuration](#4-phase-2-azure-devops-configuration)
5. [Phase 3: Pipeline Implementation](#5-phase-3-pipeline-implementation)
6. [Phase 4: Environment Variables Configuration](#6-phase-4-environment-variables-configuration)
7. [Branching Strategy](#7-branching-strategy)
8. [Rollback Procedures](#8-rollback-procedures)
9. [Reference Data Migration](#9-reference-data-migration)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ALM FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌───────────┐ │
│  │    DEV      │     │    GIT      │     │    UAT      │     │   PROD    │ │
│  │ (Unmanaged) │────►│  Repository │────►│  (Managed)  │────►│ (Managed) │ │
│  └─────────────┘     └─────────────┘     └─────────────┘     └───────────┘ │
│        │                    │                   │                   │       │
│        │                    │                   │                   │       │
│   Developers          PR to Main          Approval Gate       Approval Gate │
│   work here           triggers CI         before deploy       before deploy │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Pipeline Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           CI/CD PIPELINE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PR Merged to Main                                                           │
│        │                                                                     │
│        ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────┐                │
│  │                    BUILD STAGE                          │                │
│  │  1. Export Unmanaged Solution from Dev                  │                │
│  │  2. Unpack Solution to Source Control Format            │                │
│  │  3. Pack as Managed Solution                            │                │
│  │  4. Publish Build Artifact                              │                │
│  └───────────────────────────┬─────────────────────────────┘                │
│                              │                                               │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────┐                │
│  │                  UAT DEPLOYMENT STAGE                   │                │
│  │  ┌─────────────────┐                                    │                │
│  │  │  Manual Gate    │◄── Approval Required               │                │
│  │  └────────┬────────┘                                    │                │
│  │           ▼                                             │                │
│  │  1. Download Artifact                                   │                │
│  │  2. Set Environment Variables (UAT values)              │                │
│  │  3. Import Managed Solution                             │                │
│  │  4. Activate Flows                                      │                │
│  │  5. Publish Bot                                         │                │
│  └───────────────────────────┬─────────────────────────────┘                │
│                              │                                               │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────┐                │
│  │                  PROD DEPLOYMENT STAGE                  │                │
│  │  ┌─────────────────┐                                    │                │
│  │  │  Manual Gate    │◄── Approval Required               │                │
│  │  └────────┬────────┘                                    │                │
│  │           ▼                                             │                │
│  │  1. Download Artifact                                   │                │
│  │  2. Set Environment Variables (Prod values)             │                │
│  │  3. Import Managed Solution                             │                │
│  │  4. Activate Flows                                      │                │
│  │  5. Publish Bot                                         │                │
│  └─────────────────────────────────────────────────────────┘                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Solutions

| Solution | Unique Name | Purpose |
|----------|-------------|---------|
| Retainer | Retainer | Copilot Studio Bot, Flows, Table |
| Connection References | ConnectionRef | Shared connection references |

---

## 2. Prerequisites

### Required Tools

- Azure DevOps with Pipelines enabled
- Power Platform CLI (pac) - installed via pipeline
- Service Principal with Power Platform admin permissions

### Service Principal Requirements

The Service Principal must have:

- **Application User** created in each Power Platform environment (Dev, UAT, Prod)
- **System Administrator** security role in each environment
- Azure AD permissions: `Dynamics CRM` API permissions

### Repository Structure (Target State)

```
/
├── pipelines/
│   ├── build-pipeline.yml
│   ├── release-pipeline.yml
│   └── templates/
│       ├── export-solution.yml
│       ├── deploy-solution.yml
│       └── set-environment-variables.yml
├── src/
│   └── solutions/
│       ├── Retainer/
│       │   └── (unpacked solution files)
│       └── ConnectionRef/
│           └── (unpacked solution files)
├── config/
│   ├── environment-variables-uat.json
│   └── environment-variables-prod.json
└── scripts/
    └── activate-flows.ps1
```

---

## 3. Phase 1: Publisher Remediation

### Overview

Current state has publisher prefix `cra02` in Dev while UAT/Prod expect `cr`. Since this is weeks-old development with no production data, we will perform a clean rebuild.

### Step-by-Step Instructions

#### 3.1 Create New Publisher in Dev

1. Navigate to Dev environment: `https://make.powerapps.com`
2. Go to **Solutions** > **Publishers** (gear icon in command bar)
3. Click **+ New publisher**
4. Configure:
   - **Display Name:** Your Company Name
   - **Name:** cr (lowercase)
   - **Prefix:** cr
   - **Choice Value Prefix:** 10000 (or your standard)
5. Click **Save**

#### 3.2 Create New Solutions

**Connection References Solution (if rebuilding):**

1. **Solutions** > **+ New solution**
2. Configure:
   - **Display Name:** Connection References
   - **Name:** ConnectionRef
   - **Publisher:** Select `cr` publisher
   - **Version:** 1.0.0.0
3. Click **Create**
4. Add existing connection references to this solution

**Retainer Solution:**

1. **Solutions** > **+ New solution**
2. Configure:
   - **Display Name:** Retainer
   - **Name:** Retainer
   - **Publisher:** Select `cr` publisher
   - **Version:** 1.0.0.0
3. Click **Create**

#### 3.3 Recreate Components with Correct Prefix

Since components have schema names baked in, you must recreate:

**Table:**
1. In the new Retainer solution, create the table fresh with `cr_` prefix
2. Recreate all columns
3. Migrate any test data if needed

**Flows (7 total):**
1. Open each existing flow
2. **Save As** to create a copy
3. Add the copy to the new Retainer solution
4. Delete the original from the old solution
5. Rename as needed

**Bot Components (40 total):**
1. Export bot configuration/documentation for reference
2. Recreate the bot in the new solution
3. Rebuild topics and dialogs
4. Reconnect to the new flows

> **Tip:** Consider doing this over 1-2 focused days. Document the bot's conversation flows before rebuilding.

#### 3.4 Clean Up Target Environments

**UAT:**
```powershell
# Connect to UAT
pac auth create --environment https://[uat-org].crm.dynamics.com

# Delete existing managed solutions (order matters - delete dependent first)
pac solution delete --solution-name Retainer
pac solution delete --solution-name ConnectionRef
```

**Prod:**
```powershell
# Connect to Prod
pac auth create --environment https://[prod-org].crm.dynamics.com

# Delete existing managed solutions
pac solution delete --solution-name Retainer
pac solution delete --solution-name ConnectionRef
```

#### 3.5 Delete Old Solutions in Dev

Once new solutions are verified working:

1. Remove components from old `cra02` solutions
2. Delete old solutions
3. (Optional) Delete old publisher

#### 3.6 Establish Git Baseline

After remediation:

```bash
# Export and unpack new solutions
pac solution export --name Retainer --path ./Retainer.zip --managed false
pac solution unpack --zipfile ./Retainer.zip --folder ./src/solutions/Retainer --processCanvasApps

pac solution export --name ConnectionRef --path ./ConnectionRef.zip --managed false  
pac solution unpack --zipfile ./ConnectionRef.zip --folder ./src/solutions/ConnectionRef

# Commit to develop branch
git add .
git commit -m "Initial commit with corrected publisher (cr)"
git push origin develop

# Create PR to main
```

---

## 4. Phase 2: Azure DevOps Configuration

### 4.1 Service Connections

Create Power Platform service connections for each environment:

1. **Project Settings** > **Service connections** > **New service connection**
2. Select **Power Platform**
3. Configure for each environment:

| Connection Name | Environment URL | Authentication |
|-----------------|-----------------|----------------|
| PowerPlatform-Dev | https://[dev-org].crm.dynamics.com | Service Principal |
| PowerPlatform-UAT | https://[uat-org].crm.dynamics.com | Service Principal |
| PowerPlatform-Prod | https://[prod-org].crm.dynamics.com | Service Principal |

**Service Principal Configuration:**
- **Application (Client) ID:** Your SP's Client ID
- **Client Secret:** Your SP's secret (store in Azure Key Vault recommended)
- **Tenant ID:** Your Azure AD Tenant ID

### 4.2 Variable Groups

Create three variable groups:

#### PowerPlatform-Common

| Variable | Value | Secret |
|----------|-------|--------|
| SolutionName | Retainer | No |
| ConnectionRefSolutionName | ConnectionRef | No |
| ServicePrincipalId | [Your SP Client ID] | No |
| TenantId | [Your Tenant ID] | No |
| ServicePrincipalSecret | [Link to Key Vault] | Yes |

#### PowerPlatform-UAT

| Variable | Value | Secret |
|----------|-------|--------|
| EnvironmentUrl | https://[uat-org].crm.dynamics.com | No |
| ServiceConnection | PowerPlatform-UAT | No |
| EnvironmentVariablesFile | config/environment-variables-uat.json | No |

#### PowerPlatform-Prod

| Variable | Value | Secret |
|----------|-------|--------|
| EnvironmentUrl | https://[prod-org].crm.dynamics.com | No |
| ServiceConnection | PowerPlatform-Prod | No |
| EnvironmentVariablesFile | config/environment-variables-prod.json | No |

### 4.3 Environments with Approval Gates

1. **Pipelines** > **Environments** > **New environment**
2. Create:
   - **UAT** - Add approval check with designated approvers
   - **Prod** - Add approval check with designated approvers (likely different/more approvers)

**Configure Approvals:**
1. Click environment name
2. Click **⋮** > **Approvals and checks**
3. **+ Add check** > **Approvals**
4. Add approvers and configure timeout (e.g., 72 hours)

---

## 5. Phase 3: Pipeline Implementation

### 5.1 Pipeline Files to Create

The following YAML files should be added to your repository. See the `/pipelines` folder in this solution package.

### 5.2 Register Pipelines

1. **Pipelines** > **New pipeline**
2. Select **Azure Repos Git**
3. Select your repository
4. Select **Existing Azure Pipelines YAML file**
5. Select `/pipelines/ci-cd-pipeline.yml`
6. Save (don't run yet)

### 5.3 Branch Policies

Configure branch policy on `main`:

1. **Repos** > **Branches** > **main** > **⋮** > **Branch policies**
2. Enable:
   - **Require a minimum number of reviewers:** 1+
   - **Check for linked work items:** Optional but recommended
   - **Build validation:** Add the CI pipeline

---

## 6. Phase 4: Environment Variables Configuration

### 6.1 Create Configuration Files

Create JSON files for each environment's variable values:

**config/environment-variables-uat.json:**
```json
{
  "cr_ApiBaseUrl": "https://api.uat.yourcompany.com",
  "cr_SomeApiKey": "uat-key-value",
  "cr_FeatureFlag": "true"
}
```

**config/environment-variables-prod.json:**
```json
{
  "cr_ApiBaseUrl": "https://api.yourcompany.com",
  "cr_SomeApiKey": "prod-key-value",
  "cr_FeatureFlag": "true"
}
```

> **Note:** Replace with your actual environment variable schema names (they'll have `cr_` prefix after remediation).

### 6.2 Sensitive Values

For sensitive values (API keys, secrets):

1. Store in Azure Key Vault
2. Link to variable groups
3. Reference in pipeline with `$(VariableName)`

---

## 7. Branching Strategy

### Branch Structure

```
main (protected)
  │
  └── develop
        │
        ├── feature/bot-topic-xyz
        ├── feature/new-flow-abc
        └── hotfix/critical-fix-123
```

### Workflow

#### Standard Development

1. Developer works in Power Platform Dev environment
2. Changes sync to `develop` branch (via Copilot Studio Git integration)
3. Developer creates PR: `develop` → `main`
4. PR approved and merged
5. Pipeline triggers:
   - Build stage runs automatically
   - UAT deployment waits for approval
   - After UAT testing, Prod deployment waits for approval

#### Hotfix Process

1. Create `hotfix/description` branch from `main`
2. Make minimal fix in Dev environment
3. Export and commit to hotfix branch
4. Create PR: `hotfix/description` → `main`
5. After merge, pipeline deploys through UAT → Prod
6. Merge `main` back to `develop` to sync

### Git Integration Limitation Workaround

Since Power Platform Git integration binds to one branch:

- Keep it bound to `develop`
- For hotfixes, manually export solution and commit to hotfix branch
- This is acceptable given hotfixes should be rare

---

## 8. Rollback Procedures

### Strategy: Previous Version Redeployment

We recommend keeping the last 3-5 successful build artifacts. To rollback:

### 8.1 Via Azure DevOps UI

1. **Pipelines** > **Releases** (or your pipeline runs)
2. Find the last known good deployment
3. Click **⋮** > **Redeploy**
4. Select target stage (UAT or Prod)
5. Approve when prompted

### 8.2 Via Command Line

```powershell
# Authenticate
pac auth create --environment https://[target-org].crm.dynamics.com `
    --applicationId [SP-Client-ID] `
    --clientSecret [SP-Secret] `
    --tenant [Tenant-ID]

# Import previous version (you'll need the artifact)
pac solution import --path ./Retainer_managed_v1.0.0.X.zip --async --max-async-wait-time 60
```

### 8.3 Emergency Rollback (Delete and Redeploy)

If an import fails due to corruption:

```powershell
# Delete current managed solution
pac solution delete --solution-name Retainer

# Reimport previous version
pac solution import --path ./Previous_Retainer_managed.zip
```

> **Warning:** Deleting a managed solution removes all data in custom tables. Only use if absolutely necessary.

### Artifact Retention

Configure in pipeline:

```yaml
trigger:
  # ...

resources:
  pipelines:
    - pipeline: RetainerBuild
      source: 'Retainer-CI'
      trigger: true

# In your build job
- publish: $(Build.ArtifactStagingDirectory)
  artifact: Solutions
  displayName: 'Publish Solution Artifact'
  # Retention handled by project settings
```

**Project Settings** > **Settings** > **Retention**:
- Set minimum days to keep: 30
- Set maximum to keep: 90 (or as needed)

---

## 9. Reference Data Migration

### For Dataverse Table Data

If your table contains configuration/reference data:

#### 9.1 Configuration Migration Tool Approach

1. Install Configuration Migration Tool (part of Power Platform CLI)
2. Create schema file defining what data to export
3. Include data packages in your repo

**Schema file example (schema.xml):**
```xml
<entities>
  <entity name="cr_configtable" displayname="Config Table">
    <fields>
      <field name="cr_name" displayname="Name" />
      <field name="cr_value" displayname="Value" />
    </fields>
  </entity>
</entities>
```

#### 9.2 Pipeline Integration

Add to deployment template:

```yaml
- task: PowerPlatformImportData@2
  displayName: 'Import Reference Data'
  inputs:
    authenticationType: 'PowerPlatformSPN'
    PowerPlatformSPN: '${{ parameters.serviceConnection }}'
    DataFile: '$(Pipeline.Workspace)/Solutions/data/data.zip'
```

### For Environment Variables

Already handled - environment variables are part of the solution and values are set per environment via the deployment pipeline.

### For External Files (JSON/XML)

If configuration is in external files:

1. Store in repo under `/config`
2. Deploy via pipeline task or custom script
3. Reference in flows/bots via environment variables pointing to blob storage or similar

---

## 10. Troubleshooting

### Common Issues

#### "Solution import failed: Publisher does not match"

**Cause:** Trying to import solution with different publisher than existing components.

**Fix:** Follow Phase 1 remediation completely. Ensure all target environments have old solutions deleted.

#### "Connection reference not found"

**Cause:** ConnectionRef solution not deployed or connection not created in target environment.

**Fix:**
1. Ensure ConnectionRef solution deploys first
2. Pre-create connections in target environment
3. Map connection references to connections during import

#### "Flow activation failed"

**Cause:** Missing connections or permissions.

**Fix:**
1. Ensure connections exist and are shared with the Application User
2. Check flow's connection references are properly mapped
3. Review `activate-flows.ps1` script output

#### "Bot publish failed"

**Cause:** Bot components have validation errors.

**Fix:**
1. Check bot in Power Virtual Agents portal
2. Ensure all topics are valid
3. Verify flow connections are active

### Pipeline Debugging

Enable verbose logging:

```yaml
variables:
  System.Debug: true
```

Check specific task logs:
1. Click failed task in pipeline run
2. Review full log output
3. Look for PAC CLI error messages

### Support Resources

- [Power Platform ALM Documentation](https://docs.microsoft.com/en-us/power-platform/alm/)
- [Power Platform Build Tools](https://docs.microsoft.com/en-us/power-platform/alm/devops-build-tools)
- [PAC CLI Reference](https://docs.microsoft.com/en-us/power-platform/developer/cli/reference/)

---

## Appendix A: Checklist

### Pre-Implementation

- [ ] Service Principal created with correct permissions
- [ ] Application User created in all environments
- [ ] Azure DevOps project with Repos and Pipelines
- [ ] Access to all Power Platform environments

### Phase 1: Remediation

- [ ] New publisher `cr` created in Dev
- [ ] New Retainer solution created with `cr` publisher
- [ ] Table recreated with `cr_` prefix
- [ ] All 7 flows recreated in new solution
- [ ] All 40 bot components recreated
- [ ] Old solutions deleted from UAT
- [ ] Old solutions deleted from Prod
- [ ] Git baseline established

### Phase 2: Azure DevOps

- [ ] Service connections created (Dev, UAT, Prod)
- [ ] Variable groups created (Common, UAT, Prod)
- [ ] Environments created with approval gates
- [ ] Key Vault integrated for secrets

### Phase 3: Pipelines

- [ ] Pipeline YAML files added to repo
- [ ] Pipeline registered in Azure DevOps
- [ ] Branch policies configured on `main`
- [ ] Test run completed successfully

### Phase 4: Configuration

- [ ] Environment variables JSON files created
- [ ] Sensitive values stored in Key Vault
- [ ] Flow activation script tested

### Validation

- [ ] Full deployment to UAT successful
- [ ] UAT testing completed
- [ ] Full deployment to Prod successful
- [ ] Rollback procedure tested
