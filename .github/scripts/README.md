# Context Workflow Scripts

This directory contains modular bash scripts used by the Context workflow.

## Scripts

### `policy-evaluator.sh`
**Purpose**: Evaluates ITIL and DevSecOps policies based on workflow context

**Responsibilities**:
- Analyzes branch/tag patterns and event types
- Determines target environment and configuration
- Generates semantic versions using Commitizen
- Configures image tags based on deployment stage
- Applies security controls based on risk level
- Sets all workflow outputs for downstream jobs

**Environment Variables Required**:
- `GITHUB_SHA`: Commit SHA
- `GITHUB_EVENT_NAME`: Event type (push, pull_request, workflow_dispatch)
- `GITHUB_REF_NAME`: Branch or tag name
- `GITHUB_ACTOR`: User triggering the workflow

**Arguments**:
1. `ENVIRONMENT` (optional): Manual environment override for workflow_dispatch

**Outputs** (via `$GITHUB_OUTPUT`):
- `target_env`: Deployment target environment
- `vault_env`: Vault environment for secrets
- `primary_tag`: Primary image tag
- `additional_tags`: Comma-separated additional tags
- `source_tag`: Source image tag for promotion
- `is_build`: Whether to build from source
- `is_promote`: Whether to promote existing image
- `should_deploy`: Whether to deploy
- `should_run_sonar`: Enable SonarQube scan
- `should_run_sast`: Enable SAST scan
- `should_run_sca`: Enable SCA scan
- `should_run_trivy`: Enable Trivy scan
- `should_run_dast`: Enable DAST scan
- `is_production`: Production environment flag
- `require_approval`: Manual approval required
- `generate_evidence`: Generate compliance evidence
- `change_type`: ITIL change type
- `risk_level`: Risk assessment

---

### `generate-summary.sh`
**Purpose**: Generates formatted markdown summary for GitHub Actions workflow runs

**Responsibilities**:
- Creates formatted tables with policy decisions
- Displays risk levels and change types with emojis
- Shows security scan configurations
- Highlights governance controls
- Adds warnings for high-risk changes

**Environment Variables Required**:
- `GITHUB_EVENT_NAME`: Event type
- `GITHUB_REF_NAME`: Branch or tag name
- `GITHUB_SHA`: Commit SHA
- `GITHUB_ACTOR`: User triggering the workflow

**Arguments** (17 positional):
1. `risk_level`: Risk level (low, medium, high, critical)
2. `change_type`: Change type (standard, normal, major, emergency, production)
3. `target_env`: Target environment
4. `vault_env`: Vault environment
5. `primary_tag`: Primary image tag
6. `additional_tags`: Additional tags
7. `is_build`: Build flag
8. `is_promote`: Promote flag
9. `should_deploy`: Deploy flag
10. `should_run_sonar`: SonarQube flag
11. `should_run_sast`: SAST flag
12. `should_run_sca`: SCA flag
13. `should_run_trivy`: Trivy flag
14. `should_run_dast`: DAST flag
15. `is_production`: Production flag
16. `require_approval`: Approval flag
17. `generate_evidence`: Evidence flag

**Output**: Formatted markdown to `$GITHUB_STEP_SUMMARY`

---

## Versioning Strategy

### Year-Based Semantic Versioning
Format: `YY.MINOR.PATCH` (e.g., `26.1.3`)

- **Year (YY)**: Two-digit year (bumped on BREAKING CHANGE)
- **Minor**: Feature additions (bumped on `feat:` commits)
- **Patch**: Bug fixes and performance improvements (bumped on `fix:`, `perf:` commits)

### Tag Patterns by Branch

| Branch/Tag Pattern | Primary Tag | Additional Tags | Use Case |
|-------------------|-------------|-----------------|----------|
| `develop` | Semantic version | `dev-{sha}`, `dev-latest` | Development builds |
| `release/*` | Semantic version | `qa-{sha}`, `qa-latest` | QA testing |
| `v*` | Git tag | `uat-latest` | UAT/Staging |
| `hotfix/*` | Semantic version | `hotfix-{sha}`, `hotfix-latest` | Emergency fixes |
| Other | `sha-{sha}` | - | Unknown/adhoc |

---

## ITIL Change Management

### Change Types

| Type | Risk Level | Approval | Use Case |
|------|-----------|----------|----------|
| `standard` | Low | No | PR verification |
| `standard` | Medium | No | Development changes |
| `normal` | Medium | No | QA releases |
| `major` | High | No | UAT releases |
| `emergency` | High | No | Hotfixes |
| `production` | Critical | Yes | Production deployment |

### Risk-Based Security Controls

- **Low/Medium**: SonarQube, SAST, SCA, Trivy
- **High/Critical**: All scans + DAST

---

## Maintenance

### Adding New Policies
Edit `policy-evaluator.sh` and update the relevant case statement:
- Environment configuration: `set_environment_config()`
- Image tags: `configure_image_tags()`
- Security controls: `apply_security_controls()`

### Modifying Summary Format
Edit `generate-summary.sh` and update the `generate_summary()` function.

### Testing Scripts Locally
```bash
# Test policy evaluator
export GITHUB_SHA="abc123def456"
export GITHUB_EVENT_NAME="push"
export GITHUB_REF_NAME="develop"
export GITHUB_ACTOR="testuser"
export GITHUB_OUTPUT=/tmp/github_output.txt

.github/scripts/policy-evaluator.sh

# View outputs
cat $GITHUB_OUTPUT
```

---

## File Structure
```
.github/
├── scripts/
│   ├── README.md                    # This file
│   ├── policy-evaluator.sh          # Policy evaluation logic
│   └── generate-summary.sh          # Summary report generator
└── workflows/
    └── context.yml                   # Main context workflow
```

---

## Benefits of This Refactoring

1. **Separation of Concerns**: Bash logic separated from YAML workflow
2. **Reusability**: Scripts can be called from multiple workflows
3. **Testability**: Scripts can be tested independently
4. **Maintainability**: Easier to update logic without touching workflow structure
5. **Readability**: Workflow file is cleaner and focuses on orchestration
6. **Version Control**: Script changes are easier to track
7. **Documentation**: Self-documenting with proper comments and structure
