# Dynamics 365 / Dataverse Developer Workflow Guide

This guide walks through the standard process for a developer to make changes to a Dataverse solution, from picking up a work item to seeing the change deployed to production.

---

## Overview: The Change Lifecycle

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Pick Up   │───▶│    Make     │───▶│   Export    │───▶│  Create PR  │───▶│   Deploy    │
│  Work Item  │    │   Changes   │    │  & Commit   │    │  & Review   │    │  to Envs    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
     Azure              Dev               Git +             Azure              CI/CD
    Boards           Environment         PAC CLI           DevOps            Pipeline
```

---

## Prerequisites

Before starting, ensure you have:

- [ ] Access to the **Dev environment** in Power Platform
- [ ] **Visual Studio 2022** (for plug-in development)
- [ ] **Power Platform CLI (PAC CLI)** installed — [Download here](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction)
- [ ] **Git** installed and configured
- [ ] Clone of the repository on your local machine
- [ ] Appropriate licenses (Power Apps, Dynamics 365, etc.)

### Verify PAC CLI Installation

```powershell
pac --version
```

### Authenticate to Your Dev Environment

```powershell
# Create an auth profile for your dev environment
pac auth create --environment "https://yourorg-dev.crm.dynamics.com"

# Verify authentication
pac auth list
pac org who
```

---

## Step 1: Pick Up a Work Item

1. Go to **Azure Boards** and find your assigned work item
2. Move the item to **In Progress**
3. Note the work item ID (e.g., `AB#1234`) — you'll use this in commit messages

---

## Step 2: Create a Feature Branch

Always work in a feature branch, never directly on `main` or `develop`.

```powershell
# Make sure you're on the latest develop branch
git checkout develop
git pull origin develop

# Create a feature branch
# Naming convention: feature/<work-item-id>-<short-description>
git checkout -b feature/1234-add-account-validation
```

---

## Step 3: Make Your Changes

The process differs depending on what type of change you're making.

### Scenario A: Configuration Changes (Tables, Forms, Views, Apps, Flows)

These changes are made directly in the Power Platform Maker Portal.

1. **Open the Dev environment** in [make.powerapps.com](https://make.powerapps.com)
2. **Select the correct solution** (e.g., `Core` or `Automation`)
3. **Make your changes:**
   - Add/modify tables, columns, relationships
   - Update forms, views, business rules
   - Create/edit model-driven or canvas apps
   - Build Power Automate flows
4. **Test your changes** in the Dev environment
5. **Save and publish** all customizations

> **Important:** Always work within your solution, never in the Default solution. Components created outside your solution won't be exported.

---

### Scenario B: Plug-in Development (C# Code)

Plug-in changes involve both code and registration.

#### B.1: Write/Modify the Plug-in Code

1. **Open the solution** in Visual Studio:
   ```
   src/Plugins/MyPlugins.sln
   ```

2. **Create or modify your plug-in class:**

   ```csharp
   using Microsoft.Xrm.Sdk;
   using System;

   namespace Contoso.Plugins
   {
       public class AccountValidationPlugin : IPlugin
       {
           public void Execute(IServiceProvider serviceProvider)
           {
               // Get the execution context
               var context = (IPluginExecutionContext)serviceProvider
                   .GetService(typeof(IPluginExecutionContext));
               
               // Get the organization service
               var serviceFactory = (IOrganizationServiceFactory)serviceProvider
                   .GetService(typeof(IOrganizationServiceFactory));
               var service = serviceFactory.CreateOrganizationService(context.UserId);

               try
               {
                   // Your business logic here
                   if (context.InputParameters.Contains("Target") && 
                       context.InputParameters["Target"] is Entity entity)
                   {
                       ValidateAccount(entity);
                   }
               }
               catch (Exception ex)
               {
                   throw new InvalidPluginExecutionException(
                       $"An error occurred in AccountValidationPlugin: {ex.Message}", ex);
               }
           }

           private void ValidateAccount(Entity account)
           {
               // Validation logic
           }
       }
   }
   ```

3. **Build the project** to ensure it compiles:
   ```powershell
   dotnet build src/Plugins/MyPlugins.csproj --configuration Release
   ```

4. **Run unit tests** (if you have them):
   ```powershell
   dotnet test src/Plugins.Tests/MyPlugins.Tests.csproj
   ```

#### B.2: Register the Plug-in in Dev Environment

You have two options for registration:

**Option 1: Plugin Registration Tool (GUI)**

1. Open the **Plugin Registration Tool** (from the SDK or XrmToolBox)
2. Connect to your Dev environment
3. Register your assembly and steps
4. The registration is stored in the Plugins solution

**Option 2: PAC CLI (Command Line)**

```powershell
# Push the plugin assembly to the environment
pac plugin push --solution-unique-name "Plugins"
```

#### B.3: Test the Plug-in

1. Trigger the plug-in by performing the action in the Dev environment
2. Use **Plugin Trace Log** to debug if needed:
   - Settings → Advanced Settings → Administration → Plugin Trace Log
3. Verify the expected behavior

---

### Scenario C: Web Resources (JavaScript, HTML, CSS, Images)

1. **Create/modify the web resource files** locally in your repo:
   ```
   src/Solutions/Core/WebResources/
   ├── scripts/
   │   └── account_form.js
   ├── html/
   │   └── custom_control.html
   └── images/
       └── logo.png
   ```

2. **Upload to Dev environment:**
   - Through the Maker Portal (Solutions → Web Resources)
   - Or using PAC CLI / XrmToolBox

3. **Publish customizations** after uploading

---

## Step 4: Export and Unpack the Solution

Once your changes are complete and tested in Dev, export them to source control.

### 4.1: Export Using PAC CLI

```powershell
# Navigate to your solution folder
cd src/Solutions/Core

# Export the solution as unmanaged (for source control)
pac solution export --path ./Core_export.zip --name Core --managed false --overwrite

# Unpack the solution into source-controlled folders
pac solution unpack --zipfile ./Core_export.zip --folder ./src --processCanvasApps

# Clean up the zip file (it's not checked in)
Remove-Item ./Core_export.zip
```

### 4.2: For Plug-in Solutions

When exporting the Plugins solution, the assembly is included. However, you also need to ensure your built DLL is in the `PluginAssemblies` folder:

```powershell
# Build the plugin in Release mode
dotnet build src/Plugins/MyPlugins.csproj --configuration Release

# Copy the DLL to the solution's PluginAssemblies folder
Copy-Item "src/Plugins/bin/Release/net462/MyPlugins.dll" `
          "src/Solutions/Plugins/PluginAssemblies/" -Force

# Export and unpack the Plugins solution
cd src/Solutions/Plugins
pac solution export --path ./Plugins_export.zip --name Plugins --managed false --overwrite
pac solution unpack --zipfile ./Plugins_export.zip --folder ./src --processCanvasApps
Remove-Item ./Plugins_export.zip
```

### 4.3: Review What Changed

```powershell
# See what files changed
git status

# Review the changes
git diff
```

Common files you'll see modified:
- `solution.xml` — Solution metadata and version
- `Entities/<TableName>/Entity.xml` — Table definitions
- `Entities/<TableName>/FormXml/main/*.xml` — Form layouts
- `Workflows/*.json` — Power Automate flow definitions
- `PluginAssemblies/*.dll` — Plug-in binaries
- `WebResources/*` — JavaScript, HTML, CSS, images

---

## Step 5: Commit Your Changes

### 5.1: Stage the Changes

```powershell
# Stage all changes
git add .

# Or stage specific files
git add src/Solutions/Core/
git add src/Plugins/
```

### 5.2: Commit with a Meaningful Message

Use a commit message that references the work item:

```powershell
git commit -m "AB#1234: Add account name validation plugin

- Created AccountValidationPlugin to validate account names
- Added pre-validation step on account create/update
- Updated Core solution with new business rule for fallback"
```

> **Tip:** The `AB#1234` syntax automatically links the commit to the Azure Boards work item.

### 5.3: Push to Remote

```powershell
git push origin feature/1234-add-account-validation
```

---

## Step 6: Create a Pull Request

1. Go to **Azure DevOps → Repos → Pull Requests**
2. Click **New Pull Request**
3. Set:
   - **Source branch:** `feature/1234-add-account-validation`
   - **Target branch:** `develop`
   - **Title:** `AB#1234: Add account name validation`
   - **Description:** Explain what changed and why
4. **Link the work item** (AB#1234)
5. **Add reviewers** (at least one other developer)
6. Click **Create**

### What Happens Automatically

When you create the PR, the **CI pipeline** runs automatically:

1. ✅ Builds the plug-in assembly
2. ✅ Runs unit tests
3. ✅ Packs the solutions (managed)
4. ✅ Runs Solution Checker for static analysis

If any step fails, you'll see the error in the PR. Fix the issue and push again.

---

## Step 7: Code Review

### As the Author

- Respond to reviewer comments
- Make requested changes and push new commits
- Re-request review when ready

### As a Reviewer

Check for:
- [ ] Does the code follow team standards?
- [ ] Are plug-ins properly handling exceptions?
- [ ] Are there appropriate comments/documentation?
- [ ] Does the solution structure follow our patterns?
- [ ] Are there any Solution Checker warnings to address?

---

## Step 8: Merge the Pull Request

Once approved:

1. Click **Complete** on the PR
2. Choose merge type:
   - **Squash commit** (recommended) — Combines all commits into one
   - **Merge commit** — Preserves all commits
3. Check **Delete source branch** (keeps repo clean)
4. Click **Complete merge**

---

## Step 9: Deployment to Environments

After merging to `develop`, the **CD pipeline** takes over.

### Automatic Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Merge   │────▶│  Deploy  │────▶│  Deploy  │────▶│  Deploy  │
│  to Dev  │     │  to Test │     │  to UAT  │     │  to Prod │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
   Auto            Auto           Manual            Manual
                                 Approval          Approval
```

### What the CD Pipeline Does

For each environment:

1. **Downloads** the solution artifacts from the CI build
2. **Imports** the managed solution
3. **Applies** environment-specific settings (from `settings.{env}.json`):
   - Connection references (different connections per environment)
   - Environment variables (different URLs, feature flags, etc.)
4. **Publishes** all customizations
5. **Applies upgrade** (removes deleted components)

### Approvals

- **Test:** Usually auto-deploys or requires minimal approval
- **UAT:** Requires approval from a team lead or QA
- **Production:** Requires approval from release manager or change board

To approve:
1. Go to **Azure DevOps → Pipelines → Environments**
2. Find the pending approval
3. Review and click **Approve**

---

## Step 10: Verify and Close

### Verify in Each Environment

After deployment:
1. Log into the target environment
2. Test your changes work correctly
3. Check plug-in trace logs for any errors

### Close the Work Item

1. Go to **Azure Boards**
2. Move the work item to **Done**
3. Add any relevant notes about the implementation

---

## Quick Reference: Common Commands

```powershell
# === Authentication ===
pac auth create --environment "https://yourorg-dev.crm.dynamics.com"
pac auth list
pac org who

# === Solution Export/Unpack ===
pac solution export --path ./Solution.zip --name SolutionName --managed false
pac solution unpack --zipfile ./Solution.zip --folder ./src --processCanvasApps

# === Solution Import/Pack (for testing locally) ===
pac solution pack --zipfile ./Solution_managed.zip --folder ./src --managed true
pac solution import --path ./Solution_managed.zip --activate-plugins

# === Plugin Commands ===
pac plugin push --solution-unique-name "Plugins"

# === Git Workflow ===
git checkout develop
git pull origin develop
git checkout -b feature/1234-description
git add .
git commit -m "AB#1234: Description of change"
git push origin feature/1234-description

# === Build Plugins ===
dotnet build src/Plugins/MyPlugins.csproj --configuration Release
dotnet test src/Plugins.Tests/MyPlugins.Tests.csproj
```

---

## Troubleshooting Common Issues

### "Solution import failed: Missing dependency"

**Cause:** Your solution references a component from another solution that isn't installed.

**Fix:** 
- Ensure solutions are imported in the correct order (Core before Plugins)
- Check that all dependencies are included in your solution or marked as external

### "Plugin assembly not found during import"

**Cause:** The DLL wasn't copied to `PluginAssemblies/` before packing.

**Fix:**
```powershell
Copy-Item "src/Plugins/bin/Release/net462/MyPlugins.dll" `
          "src/Solutions/Plugins/PluginAssemblies/" -Force
```

### "Merge conflict in solution.xml"

**Cause:** Multiple developers modified the solution simultaneously.

**Fix:**
1. Pull the latest `develop` branch
2. Re-export your solution from Dev
3. Carefully merge or re-apply your changes
4. Consider coordinating with teammates to avoid simultaneous edits

### "Solution Checker found critical issues"

**Cause:** Your code or configuration violates best practices.

**Fix:**
1. Review the Solution Checker results in the pipeline
2. Address the issues (common ones: hardcoded GUIDs, missing null checks, deprecated APIs)
3. Push a fix and re-run the pipeline

### "Canvas app won't unpack properly"

**Cause:** Canvas apps require special handling.

**Fix:** Use the `--processCanvasApps` flag:
```powershell
pac solution unpack --zipfile ./Solution.zip --folder ./src --processCanvasApps
```

---

## Best Practices Summary

| Do | Don't |
|----|-------|
| ✅ Work in a feature branch | ❌ Commit directly to `main` or `develop` |
| ✅ Export and commit changes daily | ❌ Let changes sit in Dev environment for weeks |
| ✅ Use meaningful commit messages with work item IDs | ❌ Use vague messages like "fixed stuff" |
| ✅ Build and test plug-ins locally before registering | ❌ Debug directly in shared Dev environment |
| ✅ Review Solution Checker results | ❌ Ignore warnings—they often predict production bugs |
| ✅ Coordinate with team on shared components | ❌ Modify the same form/table simultaneously |
| ✅ Keep solutions focused (Core, Plugins, Automation) | ❌ Put everything in one massive solution |