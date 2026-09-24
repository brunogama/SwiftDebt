# Repository Architecture Tree

| Field | Value |
| --- | --- |
| Commit | `a974304e` |
| Branch | `main` |
| Source date | `2026-02-05` |
| Tree renderer | `python` |
| Drift score | `43` / `8` |

## Repository overview

Summarized directory view at depth 3; generated artifacts and dependency or build noise use the shared ignore list.

```text
.
|-- backend
|   |-- src
|   |   `-- app
|   `-- tests
|-- docs
|   `-- architecture
|-- frontend
|   |-- public
|   `-- src
|       |-- components
|       `-- pages
`-- infra
    |-- environments
    |   |-- dev
    |   `-- prod
    `-- modules
        `-- network
```

## Python

Detected from `backend/pyproject.toml`. The Python slice follows a src layout with routers, services, and models.

### `backend`

Focused directory view at depth 3.

```text
backend
|-- src
|   `-- app
|       |-- models
|       |-- routers
|       `-- services
`-- tests
```

## Terraform

Detected from `infra/environments/dev/main.tf`, `infra/environments/prod/main.tf`, `infra/main.tf`, `infra/modules/network/main.tf`. The Terraform slice separates reusable modules from environment roots.

### `infra`

Focused directory view at depth 3.

```text
infra
|-- environments
|   |-- dev
|   `-- prod
`-- modules
    `-- network
```

## TypeScript/JavaScript

Detected from `frontend/package.json`. The TypeScript/JavaScript slice uses a source layout that separates reusable components from route-level pages.

### `frontend`

Focused directory view at depth 3.

```text
frontend
|-- public
`-- src
    |-- components
    `-- pages
```

## Change summary since last generation

- Commits considered: 4
- Feature commits: 3
- Breaking changes: 1
- Other commits: 1
- HEAD changed: yes
- Branch changed: no
- Structural tree changed: yes
- Ecosystem markers changed: no
- History diverged: no
- Drift score: 43 (threshold 8)
- Decision: Regenerated because the drift threshold was met.
