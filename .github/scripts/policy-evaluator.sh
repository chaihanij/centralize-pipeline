#!/usr/bin/env bash
# =========================================================
# ITIL + DevSecOps Policy Evaluator
# =========================================================
# Evaluates workflow context and sets appropriate policies
# based on branch, event type, and change management rules
# =========================================================

set -euo pipefail

# =========================================================
# Constants & Configuration
# =========================================================
readonly GITHUB_SHA="${GITHUB_SHA:-}"
readonly GITHUB_EVENT_NAME="${GITHUB_EVENT_NAME:-}"
readonly GITHUB_REF_NAME="${GITHUB_REF_NAME:-}"
readonly SHORT_SHA="${GITHUB_SHA:0:7}"
readonly MANUAL_ENVIRONMENT="${1:-}"

# =========================================================
# Utility Functions
# =========================================================

# Initialize all variables with safe defaults
initialize_defaults() {
    ENV_NAME="none"
    VAULT_ENV="none"

    IS_BUILD="false"
    IS_PROMOTE="false"
    SHOULD_DEPLOY="false"

    SHOULD_RUN_SONAR="true"
    SHOULD_RUN_SAST="true"
    SHOULD_RUN_SCA="true"
    SHOULD_RUN_TRIVY="true"
    SHOULD_RUN_DAST="false"

    IS_PRODUCTION="false"
    REQUIRE_APPROVAL="false"
    GENERATE_EVIDENCE="false"

    CHANGE_TYPE="standard"
    RISK_LEVEL="low"

    SOURCE_TAG="sha-${SHORT_SHA}"

    PRIMARY_TAG=""
    ADDITIONAL_TAGS=""
}

# Normalize Vault environment
normalize_vault_env() {
    local env=$1
    if [[ "$env" == "prod" ]]; then
        echo "production"
    else
        echo "$env"
    fi
}

# Apply security controls based on risk level
apply_security_controls() {
    local risk=$1
    if [[ "$risk" == "high" || "$risk" == "critical" ]]; then
        SHOULD_RUN_DAST="true"
    fi
}

# Generate semantic version using Commitizen
# Year-based semantic versioning: YY.MINOR.PATCH (e.g., 26.1.3)
# Sets PRIMARY_TAG, SOURCE_TAG, and ADDITIONAL_TAGS based on the branch pattern
generate_semantic_version() {
    local branch_pattern=$1

    echo "::group::🔢 Generating Semantic Version" >&2

    # Get current version from git tags or default to YY.0.0 (current year)
    CURRENT_YEAR=$(date +%y) # Two-digit year
    CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v${CURRENT_YEAR}.0.0")
    CURRENT_VERSION="${CURRENT_VERSION#v}" # Strip 'v' prefix

    echo "Current version from tags: ${CURRENT_VERSION}" >&2

    local APP_VERSION

    # Check if commitizen is available
    if ! command -v cz &>/dev/null; then
        echo "⚠️ Commitizen not found, falling back to SHA-based version" >&2
        APP_VERSION="${CURRENT_VERSION}-${SHORT_SHA}"
    else
        # Use commitizen to determine next version based on conventional commits
        # BREAKING CHANGE → YY+1.0.0 (year bump)
        # feat → YY.MINOR+1.0 (minor bump)
        # fix/perf → YY.MINOR.PATCH+1 (patch bump)
        set +e # Don't exit on error - allow commitizen to fail gracefully
        BUMP_OUTPUT=$(cz bump --dry-run --yes 2>&1)
        BUMP_EXIT_CODE=$? # Capture exit code immediately before any other command overwrites it
        set -e            # Re-enable exit on error for remaining script

        echo "Commitizen output:" >&2
        echo "$BUMP_OUTPUT" >&2

        # Extract version from bump output
        NEXT_VERSION=$(echo "$BUMP_OUTPUT" | grep -oP "(?<=bump: version )\S+" || echo "")

        # If no version bump detected or commitizen failed, use current version with SHA
        if [ -z "$NEXT_VERSION" ] || [ "$NEXT_VERSION" == "$CURRENT_VERSION" ] || [ $BUMP_EXIT_CODE -ne 0 ]; then
            APP_VERSION="${CURRENT_VERSION}-${SHORT_SHA}"
            echo "No version bump needed or error occurred, using: ${APP_VERSION}" >&2
        else
            APP_VERSION="${NEXT_VERSION}"
            echo "New version determined: ${APP_VERSION}" >&2
        fi
    fi

    # Set PRIMARY_TAG
    PRIMARY_TAG="$APP_VERSION"

    # Set SOURCE_TAG (for promotion scenarios)
    SOURCE_TAG="$APP_VERSION"

    # Set ADDITIONAL_TAGS based on branch pattern
    case "$branch_pattern" in
        "develop")
            ADDITIONAL_TAGS="dev-${SHORT_SHA},dev-latest"
            ;;
        "release")
            ADDITIONAL_TAGS="qa-${SHORT_SHA},qa-latest"
            ;;
        "hotfix")
            ADDITIONAL_TAGS="hotfix-${SHORT_SHA},hotfix-latest"
            ;;
        *)
            ADDITIONAL_TAGS=""
            ;;
    esac

    echo "Primary Tag: $PRIMARY_TAG" >&2
    echo "Source Tag: $SOURCE_TAG" >&2
    echo "Additional Tags: $ADDITIONAL_TAGS" >&2
    echo "::endgroup::" >&2
}

# Configure image tags based on branch/tag pattern
# Uses semantic versioning (YY.MINOR.PATCH) for develop/release/hotfix branches
configure_image_tags() {
    local ref_name=$1
    case "$ref_name" in
    "develop")
        generate_semantic_version "develop"
        ;;
    release/*)
        generate_semantic_version "release"
        ;;
    v*)
        PRIMARY_TAG="$ref_name" # Use git tag directly for releases
        SOURCE_TAG="$ref_name"
        ADDITIONAL_TAGS="uat-latest"
        ;;
    hotfix/*)
        generate_semantic_version "hotfix"
        ;;
    *)
        PRIMARY_TAG="sha-${SHORT_SHA}" # Fallback for unknown branches
        SOURCE_TAG="sha-${SHORT_SHA}"
        ADDITIONAL_TAGS=""
        ;;
    esac
}

# Set environment configuration
set_environment_config() {
    local event_name="$1"
    local ref_name="$2"

    case "$event_name" in
    "pull_request")
        ENV_NAME="pr"
        VAULT_ENV="dev"
        CHANGE_TYPE="standard"
        RISK_LEVEL="low"
        GENERATE_EVIDENCE="true"
        ;;
    "workflow_dispatch")
        ENV_NAME="${MANUAL_ENVIRONMENT}"
        VAULT_ENV="${MANUAL_ENVIRONMENT}"
        IS_PROMOTE="true"
        SHOULD_DEPLOY="true"
        IS_PRODUCTION="true"
        REQUIRE_APPROVAL="true"
        GENERATE_EVIDENCE="true"
        CHANGE_TYPE="production"
        RISK_LEVEL="critical"
        ;;
    *)
        case "$ref_name" in
        "develop")
            ENV_NAME="dev"
            VAULT_ENV="dev"
            IS_BUILD="true"
            SHOULD_DEPLOY="true"
            CHANGE_TYPE="standard"
            RISK_LEVEL="medium"
            GENERATE_EVIDENCE="true"
            ;;
        release/*)
            ENV_NAME="qa"
            VAULT_ENV="qa"
            IS_PROMOTE="true"
            SHOULD_DEPLOY="true"
            CHANGE_TYPE="normal"
            RISK_LEVEL="medium"
            GENERATE_EVIDENCE="true"
            ;;
        v*)
            ENV_NAME="uat"
            VAULT_ENV="uat"
            IS_PROMOTE="true"
            SHOULD_DEPLOY="true"
            CHANGE_TYPE="major"
            RISK_LEVEL="high"
            GENERATE_EVIDENCE="true"
            ;;
        hotfix/*)
            ENV_NAME="hotfix"
            VAULT_ENV="dev"
            IS_BUILD="true"
            SHOULD_DEPLOY="false"
            CHANGE_TYPE="emergency"
            RISK_LEVEL="high"
            GENERATE_EVIDENCE="true"
            ;;
        esac
        ;;
    esac
}

# Output all variables to GitHub outputs
set_github_outputs() {
    cat >>"${GITHUB_OUTPUT}" <<EOF
target_env=$ENV_NAME
vault_env=$(normalize_vault_env "$VAULT_ENV")
primary_tag=$PRIMARY_TAG
additional_tags=$ADDITIONAL_TAGS
source_tag=$SOURCE_TAG
is_build=$IS_BUILD
is_promote=$IS_PROMOTE
should_deploy=$SHOULD_DEPLOY
should_run_sonar=$SHOULD_RUN_SONAR
should_run_sast=$SHOULD_RUN_SAST
should_run_sca=$SHOULD_RUN_SCA
should_run_trivy=$SHOULD_RUN_TRIVY
should_run_dast=$SHOULD_RUN_DAST
is_production=$IS_PRODUCTION
require_approval=$REQUIRE_APPROVAL
generate_evidence=$GENERATE_EVIDENCE
change_type=$CHANGE_TYPE
risk_level=$RISK_LEVEL
EOF
}

# Log change type analysis
log_change_analysis() {
    case "$GITHUB_EVENT_NAME" in
    "pull_request")
        echo "✅ Pull Request - Verification Mode"
        ;;
    "workflow_dispatch")
        echo "✅ Manual Dispatch - Production Change"
        ;;
    *)
        case "$GITHUB_REF_NAME" in
        "develop")
            echo "✅ Develop Branch - Standard Change"
            ;;
        release/*)
            echo "✅ Release Branch - Normal Change"
            ;;
        v*)
            echo "✅ Version Tag - Major Change"
            ;;
        hotfix/*)
            echo "🚨 Hotfix Branch - Emergency Change"
            ;;
        *)
            echo "⚠️ Unknown trigger context"
            ;;
        esac
        ;;
    esac
}

# =========================================================
# Main Execution
# =========================================================
main() {
    # Display trigger information
    echo "::group::📋 Trigger Information"
    echo "Event Type: $GITHUB_EVENT_NAME"
    echo "Branch/Tag: $GITHUB_REF_NAME"
    echo "Actor:      ${GITHUB_ACTOR:-unknown}"
    echo "Short SHA:  $SHORT_SHA"
    echo "::endgroup::"

    # Initialize defaults
    initialize_defaults

    # Configure environment and change management
    echo "::group::🔍 Analyzing Change Type"
    set_environment_config "$GITHUB_EVENT_NAME" "$GITHUB_REF_NAME"
    log_change_analysis
    echo "::endgroup::"

    # Configure image tags
    echo "::group::🏷️ Configuring Image Tags"
    configure_image_tags "$GITHUB_REF_NAME"
    echo "Primary Tag: $PRIMARY_TAG"
    echo "Source Tag: $SOURCE_TAG"
    echo "Additional Tags: $ADDITIONAL_TAGS"
    echo "::endgroup::"

    # Apply security controls
    echo "::group::🔒 Applying Security Controls"
    apply_security_controls "$RISK_LEVEL"
    echo "Risk Level: $RISK_LEVEL"
    echo "  - SonarQube: $SHOULD_RUN_SONAR"
    echo "  - SAST:      $SHOULD_RUN_SAST"
    echo "  - SCA:       $SHOULD_RUN_SCA"
    echo "  - Trivy:     $SHOULD_RUN_TRIVY"
    echo "  - DAST:      $SHOULD_RUN_DAST"
    echo "::endgroup::"

    # Display policy decision summary
    echo "::group::📊 Policy Decision Summary"
    echo "Environment:"
    echo "  Target:     $ENV_NAME"
    echo "  Vault:      $(normalize_vault_env "$VAULT_ENV")"
    echo ""
    echo "Change Management:"
    echo "  Type:       $CHANGE_TYPE"
    echo "  Risk:       $RISK_LEVEL"
    echo ""
    echo "Actions:"
    echo "  Build:      $IS_BUILD"
    echo "  Promote:    $IS_PROMOTE"
    echo "  Deploy:     $SHOULD_DEPLOY"
    echo ""
    echo "Governance:"
    echo "  Production: $IS_PRODUCTION"
    echo "  Approval:   $REQUIRE_APPROVAL"
    echo "  Evidence:   $GENERATE_EVIDENCE"
    echo "::endgroup::"

    # Set GitHub outputs
    set_github_outputs
}

# Execute main function
main
