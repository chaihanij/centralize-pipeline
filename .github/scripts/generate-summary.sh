#!/usr/bin/env bash
# =========================================================
# GitHub Actions Summary Report Generator
# =========================================================
# Generates a formatted markdown summary for workflow runs
# =========================================================

set -euo pipefail

# =========================================================
# Helper Functions
# =========================================================

# Get emoji for risk level
get_risk_emoji() {
  case "$1" in
    critical) echo "🔴" ;;
    high)     echo "🟠" ;;
    medium)   echo "🟡" ;;
    low)      echo "🟢" ;;
    *)        echo "⚪" ;;
  esac
}

# Get emoji for change type
get_change_emoji() {
  case "$1" in
    production) echo "🚀" ;;
    emergency)  echo "🚨" ;;
    major)      echo "📦" ;;
    normal)     echo "📋" ;;
    standard)   echo "⚙️" ;;
    *)          echo "❓" ;;
  esac
}

# Get icon for boolean values
get_bool_icon() {
  [[ "$1" == "true" ]] && echo "✅" || echo "⏭️"
}

# Get approval status text
get_approval_status() {
  [[ "$1" == "true" ]] && echo "✅ Required" || echo "⏭️ Not Required"
}

# Get production status icon
get_prod_icon() {
  [[ "$1" == "true" ]] && echo "✅" || echo "❌"
}

# =========================================================
# Main Summary Generation
# =========================================================

generate_summary() {
  local risk_level="${1}"
  local change_type="${2}"
  local target_env="${3}"
  local vault_env="${4}"
  local primary_tag="${5}"
  local additional_tags="${6}"
  local is_build="${7}"
  local is_promote="${8}"
  local should_deploy="${9}"
  local should_run_sonar="${10}"
  local should_run_sast="${11}"
  local should_run_sca="${12}"
  local should_run_trivy="${13}"
  local should_run_dast="${14}"
  local is_production="${15}"
  local require_approval="${16}"
  local generate_evidence="${17}"

  local risk_emoji
  risk_emoji=$(get_risk_emoji "$risk_level")
  local change_emoji
  change_emoji=$(get_change_emoji "$change_type")

  # Generate Summary Report
  cat >> "${GITHUB_STEP_SUMMARY}" << EOF
## ${change_emoji} ITIL + DevSecOps Policy

### ${risk_emoji} Risk Level: \`${risk_level}\`

### 🌍 Environment Configuration

| Configuration | Value |
|--------------|-------|
| **Event Type** | \`${GITHUB_EVENT_NAME:-unknown}\` |
| **Branch/Tag** | \`${GITHUB_REF_NAME:-unknown}\` |
| **Target Environment** | \`${target_env}\` |
| **Vault Environment** | \`${vault_env}\` |

### 🏷️ Image Tags

| Tag Type | Value |
|----------|-------|
| **Primary** | \`${primary_tag}\` |
| **Additional** | \`${additional_tags}\` |

### 📋 ITIL Change Management

| Property | Value |
|----------|-------|
| **Change Type** | ${change_emoji} \`${change_type}\` |
| **Risk Level** | ${risk_emoji} \`${risk_level}\` |

### 🔄 Workflow Actions

| Action | Enabled |
|--------|---------|
| **Build Image** | $(get_bool_icon "$is_build") |
| **Promote Version** | $(get_bool_icon "$is_promote") |
| **Deploy** | $(get_bool_icon "$should_deploy") |

### 🔒 Security & Quality Scans

| Scan Type | Enabled |
|-----------|---------|
| **SonarQube** | $(get_bool_icon "$should_run_sonar") |
| **SAST** | $(get_bool_icon "$should_run_sast") |
| **SCA** | $(get_bool_icon "$should_run_sca") |
| **Trivy** | $(get_bool_icon "$should_run_trivy") |
| **DAST** | $(get_bool_icon "$should_run_dast") |

### 🛡️ Governance & Compliance

| Control | Status |
|---------|--------|
| **Production** | $(get_prod_icon "$is_production") |
| **Approval** | $(get_approval_status "$require_approval") |
| **Evidence** | $(get_prod_icon "$generate_evidence") |

EOF

  # Add warning for high-risk changes
  if [[ "$risk_level" == "critical" || "$risk_level" == "high" ]]; then
    cat >> "${GITHUB_STEP_SUMMARY}" << EOF
> **⚠️ Warning**: This is a **${risk_level}** risk change. Additional security controls are enforced.

EOF
  fi

  # Add footer
  cat >> "${GITHUB_STEP_SUMMARY}" << EOF
---

**Commit**: \`${GITHUB_SHA:-unknown}\`
**Actor**: @${GITHUB_ACTOR:-unknown}
**Timestamp**: \`$(date -u +"%Y-%m-%d %H:%M:%S UTC")\`
EOF
}

# Execute main function with all arguments
generate_summary "$@"
