#!/usr/bin/env bash
# =========================================================
# ITIL + DevSecOps Policy Evaluator (Build Once, Deploy Many)
# =========================================================
# Goals:
# - Build Once: build immutable image tag (sha-<SHORT_SHA>) only on build branches (e.g., develop/hotfix)
# - Deploy Many: promote (retag) the SAME built image across environments (dev -> qa -> uat -> prod)
# - Governance: main/prod deployment requires approval; tag events do NOT auto-deploy
#
# Inputs (optional, for workflow_dispatch / promote flows):
#   $1 = MANUAL_ENVIRONMENT   (dev|qa|uat|prod)
#   $2 = MANUAL_SOURCE_TAG    (existing image tag to promote from, e.g., sha-abc1234, qa-abc1234, uat-abc1234, v26.1.3)
#   $3 = MANUAL_VERSION_TAG   (optional, for prod: vX.Y.Z, e.g., v26.1.3)
#
# Outputs (GitHub Actions):
#   target_env, vault_env, primary_tag, additional_tags, source_tag,
#   is_build, is_promote, should_deploy,
#   should_run_sonar, should_run_sast, should_run_sca, should_run_trivy, should_run_dast,
#   is_production, require_approval, generate_evidence, change_type, risk_level
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
readonly MANUAL_SOURCE_TAG="${2:-}"
readonly MANUAL_VERSION_TAG="${3:-}"

# =========================================================
# Utility Functions
# =========================================================

die() {
    echo "❌ $*" >&2
    exit 1
}

is_valid_env() {
    case "$1" in
    dev | qa | uat | prod) return 0 ;;
    *) return 1 ;;
    esac
}

normalize_vault_env() {
    local env="${1:-}"
    if [[ "$env" == "prod" ]]; then
        echo "production"
    else
        echo "$env"
    fi
}

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

    # Default immutable build tag
    SOURCE_TAG="sha-${SHORT_SHA}"

    PRIMARY_TAG=""
    ADDITIONAL_TAGS=""
}

# Apply security controls based on risk level
apply_security_controls() {
    local risk="${1:-low}"
    if [[ "$risk" == "high" || "$risk" == "critical" ]]; then
        SHOULD_RUN_DAST="true"
    fi
}

# Configure image tags by environment (promotion)
set_env_tags_for_manual() {
    local env="$1"

    # Source tag must point to an EXISTING tag in registry (build once)
    if [[ -n "$MANUAL_SOURCE_TAG" ]]; then
        SOURCE_TAG="$MANUAL_SOURCE_TAG"
    fi

    case "$env" in
    dev)
        PRIMARY_TAG="dev-${SHORT_SHA}"
        ADDITIONAL_TAGS="dev-latest"
        ;;
    qa)
        PRIMARY_TAG="qa-${SHORT_SHA}"
        ADDITIONAL_TAGS="qa-latest"
        ;;
    uat)
        PRIMARY_TAG="uat-${SHORT_SHA}"
        ADDITIONAL_TAGS="uat-latest"
        ;;
    prod)
        # Prefer version tag for prod (immutable release identifier)
        if [[ -n "$MANUAL_VERSION_TAG" ]]; then
            PRIMARY_TAG="$MANUAL_VERSION_TAG"
        else
            PRIMARY_TAG="prod-${SHORT_SHA}"
        fi
        # Optional convenience tags for prod
        ADDITIONAL_TAGS="prod-latest"
        ;;
    *)
        die "Invalid environment '$env' for manual tagging"
        ;;
    esac
}

# Configure image tags based on branch/tag pattern (automatic flows)
configure_image_tags() {
    local ref_name="$1"

    case "$ref_name" in
    "develop")
        # Build once: immutable sha tag; also publish dev tags for convenience
        PRIMARY_TAG="sha-${SHORT_SHA}"
        SOURCE_TAG="sha-${SHORT_SHA}"
        ADDITIONAL_TAGS="dev-${SHORT_SHA},dev-latest"
        ;;
    release/*)
        # Promote to QA (should retag the previously built artifact)
        # NOTE: In push-based release flow, source_tag often equals same commit sha.
        # If you promote from another tag, pass MANUAL_SOURCE_TAG via workflow_dispatch instead.
        PRIMARY_TAG="qa-${SHORT_SHA}"
        ADDITIONAL_TAGS="qa-latest"
        ;;
    v*)
        # Version tag is immutable release identifier; DO NOT auto-deploy here
        PRIMARY_TAG="$ref_name"
        SOURCE_TAG="sha-${SHORT_SHA}"
        ADDITIONAL_TAGS=""
        ;;
    hotfix/*)
        # Hotfix: build once (sha) but DO NOT auto-deploy by default (governance)
        PRIMARY_TAG="sha-${SHORT_SHA}"
        SOURCE_TAG="sha-${SHORT_SHA}"
        ADDITIONAL_TAGS="hotfix-${SHORT_SHA}"
        ;;
    *)
        PRIMARY_TAG="sha-${SHORT_SHA}"
        SOURCE_TAG="sha-${SHORT_SHA}"
        ADDITIONAL_TAGS=""
        ;;
    esac
}

# Set environment configuration and ITIL change management policy
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
        # PR verification only
        IS_BUILD="false"
        IS_PROMOTE="false"
        SHOULD_DEPLOY="false"
        ;;

    "workflow_dispatch")
        # Manual promote/deploy across environments (deploy many)
        if ! is_valid_env "$MANUAL_ENVIRONMENT"; then
            die "workflow_dispatch requires MANUAL_ENVIRONMENT as dev|qa|uat|prod (arg1). Got: '${MANUAL_ENVIRONMENT:-empty}'"
        fi

        ENV_NAME="$MANUAL_ENVIRONMENT"
        VAULT_ENV="$MANUAL_ENVIRONMENT"

        IS_BUILD="false"
        IS_PROMOTE="true"
        SHOULD_DEPLOY="true"
        GENERATE_EVIDENCE="true"

        case "$ENV_NAME" in
        dev | qa)
            CHANGE_TYPE="normal"
            RISK_LEVEL="medium"
            REQUIRE_APPROVAL="false"
            IS_PRODUCTION="false"
            ;;
        uat)
            CHANGE_TYPE="major"
            RISK_LEVEL="high"
            REQUIRE_APPROVAL="true"
            IS_PRODUCTION="false"
            ;;
        prod)
            CHANGE_TYPE="production"
            RISK_LEVEL="critical"
            REQUIRE_APPROVAL="true"
            IS_PRODUCTION="true"
            ;;
        esac

        # Set tags for manual promotion
        set_env_tags_for_manual "$ENV_NAME"
        ;;

    *)
        # push / tag events
        case "$ref_name" in
        "develop")
            ENV_NAME="dev"
            VAULT_ENV="dev"
            IS_BUILD="true" # build once here
            IS_PROMOTE="false"
            SHOULD_DEPLOY="true" # deploy dev is OK
            CHANGE_TYPE="standard"
            RISK_LEVEL="medium"
            GENERATE_EVIDENCE="true"
            ;;

        release/*)
            ENV_NAME="qa"
            VAULT_ENV="qa"
            IS_BUILD="false"
            IS_PROMOTE="true" # promote to QA from built artifact
            SHOULD_DEPLOY="true"
            CHANGE_TYPE="normal"
            RISK_LEVEL="medium"
            GENERATE_EVIDENCE="true"
            ;;

        v*)
            # Tag event should NOT auto-deploy; use workflow_dispatch for uat/prod
            ENV_NAME="release"
            VAULT_ENV="qa"
            IS_BUILD="false"
            IS_PROMOTE="false"
            SHOULD_DEPLOY="false"
            CHANGE_TYPE="major"
            RISK_LEVEL="high"
            GENERATE_EVIDENCE="true"
            REQUIRE_APPROVAL="true"
            ;;

        hotfix/*)
            ENV_NAME="hotfix"
            VAULT_ENV="dev"
            IS_BUILD="true" # build once
            IS_PROMOTE="false"
            SHOULD_DEPLOY="false" # deploy via manual approval
            CHANGE_TYPE="emergency"
            RISK_LEVEL="high"
            GENERATE_EVIDENCE="true"
            REQUIRE_APPROVAL="true"
            ;;
        *)
            ENV_NAME="none"
            VAULT_ENV="none"
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

log_change_analysis() {
    case "$GITHUB_EVENT_NAME" in
    "pull_request")
        echo "✅ Pull Request - Verification Mode (no deploy)"
        ;;
    "workflow_dispatch")
        echo "✅ Manual Dispatch - Promote/Deploy to '${MANUAL_ENVIRONMENT:-unknown}'"
        ;;
    *)
        case "$GITHUB_REF_NAME" in
        "develop")
            echo "✅ Develop - Build Once + Deploy Dev"
            ;;
        release/*)
            echo "✅ Release - Promote to QA + Deploy QA"
            ;;
        v*)
            echo "✅ Tag - Freeze Artifact (no auto deploy)"
            ;;
        hotfix/*)
            echo "🚨 Hotfix - Build Once (manual deploy)"
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
    if [[ "$GITHUB_EVENT_NAME" == "workflow_dispatch" ]]; then
        echo "Manual Env: ${MANUAL_ENVIRONMENT:-}"
        echo "Source Tag: ${MANUAL_SOURCE_TAG:-}"
        echo "Version:    ${MANUAL_VERSION_TAG:-}"
    fi
    echo "::endgroup::"

    initialize_defaults

    echo "::group::🔍 Analyzing Change Type"
    set_environment_config "$GITHUB_EVENT_NAME" "$GITHUB_REF_NAME"
    log_change_analysis
    echo "::endgroup::"

    # Configure image tags for non-manual events.
    # For workflow_dispatch we already set tags inside set_environment_config()
    if [[ "$GITHUB_EVENT_NAME" != "workflow_dispatch" ]]; then
        echo "::group::🏷️ Configuring Image Tags"
        configure_image_tags "$GITHUB_REF_NAME"
        echo "Primary Tag: $PRIMARY_TAG"
        echo "Source Tag:  $SOURCE_TAG"
        echo "Additional:  $ADDITIONAL_TAGS"
        echo "::endgroup::"
    else
        echo "::group::🏷️ Configuring Image Tags (Manual)"
        echo "Primary Tag: $PRIMARY_TAG"
        echo "Source Tag:  $SOURCE_TAG"
        echo "Additional:  $ADDITIONAL_TAGS"
        echo "::endgroup::"
    fi

    echo "::group::🔒 Applying Security Controls"
    apply_security_controls "$RISK_LEVEL"
    echo "Risk Level: $RISK_LEVEL"
    echo "  - SonarQube: $SHOULD_RUN_SONAR"
    echo "  - SAST:      $SHOULD_RUN_SAST"
    echo "  - SCA:       $SHOULD_RUN_SCA"
    echo "  - Trivy:     $SHOULD_RUN_TRIVY"
    echo "  - DAST:      $SHOULD_RUN_DAST"
    echo "::endgroup::"

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

    set_github_outputs
}

main
