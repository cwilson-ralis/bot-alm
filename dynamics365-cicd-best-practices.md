# CI/CD Best Practices for Dynamics 365 (Dataverse) Solutions with Plug-ins

A practical "what good looks like" guide for implementing CI/CD pipelines for Dynamics 365 solutions that include plug-ins (.NET) plus other solution customizations (tables, forms, model-driven apps, flows, web resources, etc.).

---

## What "Good CI/CD" Means for Dataverse/Dynamics 365

A strong pipeline for Dynamics 365 typically ensures:

- **Source control is the source of truth** (not a random dev environment).
- **Only unmanaged solutions are used for development**; only managed solutions move into Test/UAT/Prod.
- You can **rebuild and redeploy plug-ins deterministically** from source.
- You have **quality gates** (Solution Checker + unit tests + basic deployment validation).
- Deployments are **repeatable, non-interactive, and credentialed safely** (service principal / workload identity).
- **Environment-specific values** (URLs, connection refs, environment variables) are injected automatically—no manual clicking.

> **Microsoft's ALM guidance** explicitly calls out that managed solutions for downstream environments should be produced by a build server and treated as a build artifact.

---

## Choose Your Automation "Lane"

You can mix these approaches based on your team's needs.

### Lane A — Azure DevOps + Power Platform Build Tools

**Most common enterprise choice.**

- Power Platform Build Tools v2 are the recommended modern path (CLI-based), and Microsoft advises moving to v2 early.
- Great if you want classic CI/CD with approvals, environments, artifacts, etc.

### Lane B — GitHub Actions + Power Platform Actions

- Microsoft Learn's tutorials show patterns like exporting/unpacking from Dev and generating a managed build artifact and deploying it.
- Good for teams already invested in GitHub.

### Lane C — "Pipelines in Power Platform" (Built-in Deployment Pipelines)

- Useful if you want a product-native deployment experience; it deploys solutions plus config like connections/connection refs/env vars.
- **Limitations:**
  - Less flexible for "advanced import behaviors" (defaults to upgrade behavior).
  - May not cover every pro-dev scenario.
  - Does not currently support **pre/post-deployment scripts**, limiting usefulness for teams needing data seeding or schema migrations.

> **Recommendation:** Most teams doing plug-ins + serious SDLC still use Azure DevOps/GitHub as the backbone, sometimes integrating Power Platform Pipelines later.

---

## Environment Strategy

### Minimum Viable (3 Environments)

| Environment | Purpose |
|-------------|---------|
| **Dev** | Unmanaged, makers/devs only |
| **Test/UAT** | Managed imports, validation |
| **Prod** | Managed only |

### Ideal (4–5 Environments)

| Environment | Purpose |
|-------------|---------|
| **Dev** | Active development (unmanaged) |
| **Build/Validation** | Optional but very useful for generating managed artifacts |
| **Test/SIT** | System integration testing |
| **UAT** | User acceptance testing |
| **Prod** | Production (managed only) |

> **Important:** If you install Dynamics 365 first-party apps (Sales/Service/etc.), decide that up front—those choices can create downstream dependencies and can't be toggled later the same way.

---

## Solution and Component Strategy

### 1. Use a Custom Publisher

**Never develop in the Default solution.**

Microsoft specifically recommends starting with a custom publisher + custom unmanaged solution, and not developing plug-ins in the Default solution and moving them later.

### 2. One Plug-in Assembly = One Solution

**Don't spread one plug-in assembly across multiple solutions.**

Dataverse solution layering can break imports if the same assembly appears in multiple solutions with mismatched plug-in types. Maintain the definition of a plug-in assembly in a single solution (often a dedicated plug-in solution).

### 3. Classic Assembly vs Plug-in Package

**Decide early: classic plug-in assembly vs plug-in package (dependent assemblies).**

If you need dependencies/resources, consider plug-in packages (dependent assemblies) early:

- Adding dependent assemblies later is harder
- ILMerge isn't supported
- **Migration warning:** Once you've deployed a *classic* plug-in assembly, migrating to a *plug-in package* requires **unregistering and re-registering**—not a simple upgrade. Plan this decision carefully.

---

## Source Control Best Practices

### Store Solutions in a "Diff-Friendly" Format

Use `pac solution unpack/pack` (or native Dataverse Git integration) so changes are reviewable in PRs.

> **Note:** SolutionPackager is no longer the recommended approach; these capabilities are now in Power Platform CLI (`pac solution unpack/pack/clone/...`).

### Avoid Committing Plug-in Binaries as Your "Truth"

Microsoft's Dataverse Git integration guidance explicitly warns that storing binaries can cause confusion. Instead:

- Make source code the single source of truth
- Build code-first assets through a solution build process

### Recommended Repository Layout

```
/solutions/<SolutionName>/...     # Unpacked solution files
/src/Plugins/...                  # C# plug-in source code
/src/Tests/...                    # Unit tests
/pipelines/...                    # YAML pipeline definitions/templates
/deployment-settings/...          # JSON config per environment
```

---

## CI Pipeline (Pull Request Validation)

Run these quality gates on every pull request.

### Quality Gate 1: Build and Test Plug-ins

**Key Dataverse plug-in build constraints to enforce in CI:**

| Constraint | Requirement |
|------------|-------------|
| Target Framework | .NET Framework 4.6.2 (current requirement) |
| Assembly Size | Maximum 16 MB |
| Signing | Strong-name signing required (if not using plug-in packages) |

**CI Steps:**

```yaml
- nuget restore / dotnet restore
- Build plug-in projects
- Run unit tests (xUnit/NUnit/MSTest)
- Optional: Static analysis (FxCop analyzers, SonarQube, etc.)
```

### Quality Gate 2: Solution Validation / Static Analysis

**Solution Checker options:**

- Power Platform Build Tools support "static analysis checks" using the Power Apps checker service (outputs SARIF for review)
- CLI: `pac solution check`

> **Environment consideration:** Some Solution Checker rules are **environment-specific** (e.g., deprecated API checks depend on the target Dataverse version). Running against a representative environment matters for accurate results.

### Quality Gate 3: Pack the Solution

Use `pac solution pack` into a zip for artifact creation. Fail the build on drift between source and packed output.

---

## The Plug-in Sync "Gotcha"

**This is where many Dynamics 365 CI/CD implementations go wrong.**

If you simply export a solution from Dev, that export contains whatever plug-in binary is registered in Dev. If Dev is updated manually and not reproducibly, you can end up deploying a binary that does not match what was built/tested.

### Best Practice Options

#### Option A: Build the Solution Project (Clone-Based) — Recommended

Use `pac solution clone` to get a `.cdsproj` and reference your plug-in project(s):

1. Use `pac solution add-reference` to associate a newly created plug-in with the solution project
2. Build with `dotnet build` or `msbuild`

This supports a more "code-first" reproducible pipeline.

#### Option B: Unpack/Pack with Mapping

- Don't check in binaries
- Use SolutionPackager (or PAC equivalent) mapping to inject binaries from build output into the packed solution

---

## CD Pipeline (Deployments)

### 1. Authenticate Safely (Service Principal)

**Recommended:** Service Principal via Workload Identity Federation where possible.

**Permission requirements:**

| Role | Notes |
|------|-------|
| System Administrator | Has `Create` privilege on `PluginAssembly` table (required for plug-in imports) |
| System Customizer | Does **not** have `Create` on `PluginAssembly` by default |

> **Additional consideration:** Even System Administrator may need explicit ownership or team membership on the solution if you're using solution-level security.

### 2. Inject Environment-Specific Config Automatically

Use a **deployment settings JSON** to pre-populate:

- Connection references
- Environment variables

Generate and pass the deployment settings file during import using `pac solution import` or Build Tools.

### 3. Import Behavior: Updates vs Upgrades

**Critical for plug-ins:** If you modify plug-in assembly characteristics, you must increment versions properly.

| Scenario | Behavior |
|----------|----------|
| Assembly changed, version not incremented | `InvalidPluginAssemblyContent` import error |
| Fix | Increase solution version |

**For larger releases, use holding + upgrade patterns:**

- CLI: `--import-as-holding` and `--stage-and-upgrade`
- Build Tools: `StageAndUpgrade` option

> **Production warning:** Stage-and-upgrade can cause **downtime** for active plug-in steps during the upgrade window. Plan production deployments accordingly and consider maintenance windows for critical plug-in changes.

### 4. Activate Plug-in Steps and Flows

During import, use the option to enable importing/activating plug-in steps and flows (important when some steps are shipped inactive).

### 5. Publishing Behavior

| Import Type | Publishing |
|-------------|------------|
| Managed | Arrives published |
| Unmanaged | May require explicit publish to become active |

---

## Reference Pipeline Blueprint

### PR Pipeline (CI)

```
1. Build plug-in projects + run unit tests
2. Solution unpack/pack consistency check
3. Solution Checker (pac solution check or Build Tools Checker)
4. Produce artifacts:
   - Packed unmanaged solution
   - (Optional) Packed managed candidate
```

### Main/Release Pipeline (CD)

```
1. Build plug-ins again (clean, reproducible)
2. Pack solution(s)
3. (Optional but valuable) Import into Build/Validation environment,
   then export managed as the official artifact
4. Deploy managed artifact sequentially:
   - Test → UAT → Prod
5. Post-deploy smoke tests:
   - Basic Dataverse API checks
   - Confirm key plug-in steps fire correctly
```

---

## Common Failure Points Checklist

| Issue | Impact | Resolution |
|-------|--------|------------|
| Wrong .NET target for plug-ins | Build/runtime failures | Target .NET Framework 4.6.2 |
| Pipeline identity lacks `PluginAssembly` create privilege | Import fails | Use System Administrator or grant explicit privilege |
| Plug-in assembly in multiple solutions | Type mismatch import failures | Maintain assembly in single solution |
| Assembly changed but solution version not incremented | `InvalidPluginAssemblyContent` error | Always increment solution version |
| Manual "clickops" for connection refs/env vars | Breaks unattended deployments | Use deployment settings JSON |
| Committing plug-in binaries without reproducible build | Drift between source and deployed artifacts | Build from source in pipeline |
| Solution Checker rules run against wrong environment | False positives/negatives | Run against representative target environment |
| Stage-and-upgrade without maintenance window | Production downtime during upgrade | Plan deployment windows for critical changes |

---

## The Single Most Important Best Practice

> **If you do nothing else:**
>
> Make the pipeline generate the managed solution artifact from source control (and built plug-in source), not from a dev environment export, and deploy only that artifact forward.

**That single change eliminates a huge class of "it worked in Dev but not in Prod" issues.**

---

## Handling Hotfixes

Hotfixes in Dynamics 365/Dataverse require careful handling because you're dealing with managed solutions and the layering system.

### Option 1: Patch Solutions (Built-in Mechanism)

Dataverse supports **solution patches** — smaller, incremental updates that layer on top of a base solution.

```bash
pac solution create-patch --solution-name "YourSolution"
```

| Pros | Cons |
|------|------|
| Faster to build and deploy (only contains changed components) | Once you create a patch, you can't edit the base solution until you clone (roll up) |
| Maintains solution layering integrity | Some component types don't patch well (use with caution for plug-ins) |
| Can be rolled up into the base solution later with `pac solution clone --patchname` | Adds complexity to your solution history |

**Best for:** Low-code component fixes (forms, views, business rules, flows)

### Option 2: Fast-Track Pipeline with Full Solution (Recommended for Plug-ins)

For plug-in hotfixes, a patch solution can be risky. Instead, use a **dedicated hotfix branch and expedited pipeline**.

#### Branching Strategy

```
main (production)
  └── hotfix/issue-12345    ← Branch from main, fix here
        └── PR back to main ← Expedited review + deploy
```

#### Expedited Pipeline Example

Create a separate pipeline (or pipeline stage) for hotfixes:

```yaml
# hotfix-pipeline.yml
trigger:
  branches:
    include:
      - hotfix/*

stages:
  - stage: Build
    jobs:
      - job: BuildAndTest
        steps:
          - task: DotNetCoreCLI@2
            displayName: 'Build Plugins'
            inputs:
              command: 'build'
              projects: 'src/Plugins/**/*.csproj'
          
          - task: DotNetCoreCLI@2
            displayName: 'Run Unit Tests'
            inputs:
              command: 'test'
              projects: 'src/Tests/**/*.csproj'
          
          - task: PowerPlatformPackSolution@2
            displayName: 'Pack Solution'
            inputs:
              SolutionSourceFolder: 'solutions/YourSolution'
              SolutionOutputFile: '$(Build.ArtifactStagingDirectory)/YourSolution_managed.zip'
              SolutionType: 'Managed'

  - stage: DeployToUAT
    dependsOn: Build
    jobs:
      - deployment: DeployUAT
        environment: 'UAT'  # Manual approval gate here
        
  - stage: DeployToProd
    dependsOn: DeployToUAT
    jobs:
      - deployment: DeployProd
        environment: 'Production'  # Manual approval gate here
```

**Key differences from standard pipeline:**

- Fewer quality gates (but keep unit tests — never skip those)
- Pre-approved reviewers for expedited PR review
- Manual approval gates at UAT and Prod (not automated promotion)
- Solution Checker can be optional or warning-only

### Option 3: Segmented Solutions (Proactive Strategy)

If you anticipate frequent hotfixes, **segment your solutions** by volatility:

```
CoreSolution (stable, infrequent changes)
  └── Tables, security roles, base plug-ins

PluginsSolution (moderate change frequency)
  └── All plug-in assemblies and steps

UISolution (high change frequency)
  └── Forms, views, sitemap, web resources

IntegrationsSolution (varies)
  └── Flows, connection references, environment variables
```

**Benefit:** You can hotfix just the `PluginsSolution` without touching the rest, reducing risk and deployment time.

### Hotfix Process Checklist

```
□ Create hotfix branch from main (not develop)
□ Make minimal, targeted fix only
□ Increment solution version (required for plug-in changes)
□ Run unit tests locally before PR
□ PR with expedited review (designated approvers)
□ Build pipeline produces managed artifact
□ Deploy to UAT with manual approval
□ Smoke test in UAT (verify fix, check for regressions)
□ Deploy to Prod with manual approval
□ Merge hotfix branch back to main AND develop
□ Document in release notes / incident ticket
```

### Version Numbering for Hotfixes

Use a consistent versioning scheme that distinguishes hotfixes:

```
Major.Minor.Patch.Hotfix

Example:
1.2.0.0  ← Standard release
1.2.0.1  ← Hotfix 1
1.2.0.2  ← Hotfix 2
1.3.0.0  ← Next standard release (rolls up hotfixes)
```

In your `.cdsproj` or solution settings:

```xml
<PropertyGroup>
  <SolutionVersion>1.2.0.1</SolutionVersion>
</PropertyGroup>
```

### Hotfix Anti-Patterns

| Anti-Pattern | Why It's Dangerous |
|--------------|-------------------|
| Edit directly in Prod | Unmanaged layers in Prod cause long-term pain |
| Skip the pipeline entirely | Lose traceability, risk deploying untested code |
| Deploy unmanaged to Prod "just this once" | Creates solution layer conflicts |
| Forget to merge hotfix back | Next release overwrites your fix |
| Skip version increment | `InvalidPluginAssemblyContent` error on import |

### Emergency "Break Glass" Scenario

If you have a true production-down emergency and can't wait for any pipeline:

1. **Still use source control** — commit the fix, even if you deploy manually
2. Use `pac solution import` directly from a secure workstation with service principal credentials
3. **Immediately** run the fix through the standard pipeline afterward to ensure artifacts are in sync
4. Document everything for post-incident review

> **Warning:** This should be exceedingly rare. If you're doing this frequently, your pipeline is too slow and needs optimisation.

---

## Additional Resources

- [Microsoft Power Platform ALM Documentation](https://learn.microsoft.com/en-us/power-platform/alm/)
- [Power Platform CLI Reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/)
- [Power Platform Build Tools for Azure DevOps](https://learn.microsoft.com/en-us/power-platform/alm/devops-build-tools)
- [GitHub Actions for Power Platform](https://learn.microsoft.com/en-us/power-platform/alm/devops-github-actions)

---

*Document Version: 1.1*
*Last Updated: February 2026*