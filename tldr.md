# Dynamics 365 / Dataverse CI/CD Design (Azure DevOps) — One Page

## Scope

This design covers CI/CD for a Dynamics 365 (Dataverse) implementation that includes:

* **Model-driven customizations** (tables/columns, forms, views, apps, security roles)
* **Automation** (Power Automate flows where applicable)
* **Plug-ins** (.NET assemblies + steps)

## Goals

* **Repeatable, auditable deployments** (no “clickops” in Test/UAT/Prod)
* **Managed-only downstream** (Test/UAT/Prod get managed solutions only)
* **Plug-in binaries always match the built source** (deterministic builds)
* **Environment-specific configuration is injected automatically** (connection refs + env vars)
* **Quality gates** before merge/release (tests + static checks)

## Environments

| Environment                                                                                    | Purpose                    | Solution Type | Who         |
| ---------------------------------------------------------------------------------------------- | -------------------------- | ------------- | ----------- |
| Dev                                                                                            | Build features             | **Unmanaged** | Makers/devs |
| Test (SIT)                                                                                     | System/integration testing | **Managed**   | QA          |
| UAT                                                                                            | Business validation        | **Managed**   | Business    |
| Prod                                                                                           | Production                 | **Managed**   | Ops         |
| **Optional (recommended): Build/Validation** environment used by pipeline for validation only. |                            |               |             |

## Solution Strategy

* **Publisher:** Single custom publisher (prefix: `<prefix>`) used across all solutions.
* **Solutions (recommended split):**

  1. `<Prefix>_Core` — tables, relationships, forms/views, apps, security roles
  2. `<Prefix>_Plugins` — plug-in assembly + steps (keep assembly definition in *one* solution)
  3. (Optional) `<Prefix>_Automation` — flows, connection references, environment variables
* **Development rule:** Create/modify components only inside your team solutions (not Default solution).

## Repo Structure

Recommended layout:

* `/src/Plugins/` — C# plug-in projects + unit tests
* `/solutions/<SolutionName>/` — solution project (`.cdsproj`) **or** unpacked solution source
* `/deployment-settings/` — `test.json`, `uat.json`, `prod.json` (no secrets)
* `/pipelines/` — Azure DevOps YAML templates

## Branching & Release

* `main` = always deployable
* Feature branches → PR into `main` with CI gates
* Optional: `release/*` for controlled UAT/Prod releases (or use tags)

## Tooling (Azure DevOps)

* **Microsoft Power Platform Build Tools v2** (ADO extension)
* Windows build agent for plug-ins (typical for .NET Framework plug-ins)
* Authentication via **service principal**, ideally **Workload Identity Federation** (secretless)

## CI Pipeline (PR Validation)

Runs on every PR:

1. **Build plug-ins** (Release) + **run unit tests**
2. **Static checks**

   * Solution Checker (or equivalent)
   * Basic packaging validation (pack succeeds, no missing refs)
3. **Build/pack solution artifacts**

   * Produce a **managed solution zip artifact** from source (preferred: solution project `.cdsproj` Release build)

**Output artifacts:**

* `managed.zip` (primary)
* Optional: `unmanaged.zip` (for Dev sync scenarios)

## CD Pipeline (Deployments)

Triggered on merge to `main` (and/or release tags):

1. **Deploy to Test**

   * Import **managed** solution
   * Apply **deployment settings JSON** (env vars + connection refs)
   * Post-deploy smoke tests (key tables exist, critical plug-in steps present)
2. **Deploy to UAT**

   * Same steps, with **approval gate**
3. **Deploy to Prod**

   * Same steps, with **approval gate**
   * Optional: backup/export baseline before import

**Import mode decision (standard):**

* Default to **Upgrade** (clean drift control)
* Use **Stage for Upgrade (holding)** only when you require a migration window

## Configuration & Secrets

* Use **Environment Variables** for URLs, toggles, IDs (non-secret)
* Use **Connection References** for flows/connectors
* Store secrets in **Key Vault / ADO variable groups** (not in repo)
* Each environment has its own `/deployment-settings/<env>.json`

## Versioning & Release Management

* Solution version format: `Major.Minor.Build.Revision`

  * Major/Minor = planned releases
  * Build/Revision = CI-generated (optional)
* **Always increment solution versions** for releases (especially when plug-in assemblies change)
* Maintain a release note entry per deployment (what changed + solution versions)

## Rollback & Recovery

* Preferred: redeploy the **previous managed artifact** (stored in ADO artifacts)
* If data/schema rollback is risky: define “forward-fix” process + point-in-time restore plan
* Keep a record of: solution versions, import timestamps, approver, and artifact hash

## Ownership

* App/Dataverse customization owner: `<Team/Role>`
* Plug-in owner: `<Team/Role>`
* Pipeline owner: `<Team/Role>`
* Environment admin (Prod): `<Team/Role>`

---

### Decisions to confirm (fill these in)

* [ ] Solution packaging approach: **Solution Project (.cdsproj)** ☐ / Unpack-Pack ☐
* [ ] Use dedicated **Build/Validation** environment: Yes ☐ / No ☐
* [ ] Release model: `main` direct ☐ / `release/*` branches ☐
* [ ] Import mode default: Upgrade ☐ / Stage-and-upgrade for major releases ☐

