#!/usr/bin/env bash
# =============================================================================
# Cloudchipr - Databricks Integration Setup
# =============================================================================
# This script creates a read-only service principal for Cloudchipr and grants
# it the minimum permissions needed to scan your Databricks workspace.
#
# Requirements:
#   - Databricks CLI v0.205+ installed via official installer (Homebrew, curl, WinGet, or Chocolatey)
#     The new standalone CLI executable is required for modern account/workspace commands used by this script.
#   - Account admin access to accounts.cloud.databricks.com
#
# Usage:
#   bash setup.sh
# =============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}=== Cloudchipr Databricks Integration Setup ===${RESET}"
echo ""

# =============================================================================
# Step 1 - Collect inputs
# =============================================================================
echo -e "${CYAN}Step 1 - Enter your Databricks details${RESET}"
echo ""

read -r -p "  Workspace URL (e.g. https://dbc-xxxx.cloud.databricks.com): " WORKSPACE_HOST
read -r -p "  Account ID (from accounts.cloud.databricks.com): " ACCOUNT_ID

echo ""

# =============================================================================
# Step 2 - Authenticate CLI at account level
# =============================================================================
echo -e "${CYAN}Step 2 - Authenticating with Databricks account (browser will open)${RESET}"
echo ""

databricks auth login \
  --host https://accounts.cloud.databricks.com \
  --account-id "$ACCOUNT_ID" \
  --profile cloudchipr-setup

echo -e "${GREEN}  ✓ Authenticated${RESET}"
echo ""

# Auto-detect workspace ID from the account
DEPLOYMENT_NAME=$(echo "$WORKSPACE_HOST" | sed 's|https://||' | cut -d'.' -f1)
WORKSPACE_ID=$(databricks account workspaces list --profile cloudchipr-setup -o json |
  python3 -c "
import sys, json
ws = json.load(sys.stdin)
for w in ws:
    if w.get('deployment_name') == '$DEPLOYMENT_NAME':
        print(w['workspace_id'])
        break
" || true)

if [ -z "$WORKSPACE_ID" ]; then
  echo -e "${RED}  Could not auto-detect workspace ID. Please enter it manually.${RESET}"
  read -r -p "  Workspace ID (numeric, from workspace URL ?o=XXXXXXX): " WORKSPACE_ID
else
  echo -e "${GREEN}  ✓ Workspace ID detected: $WORKSPACE_ID${RESET}"
fi
echo ""

# =============================================================================
# Step 3 - Create service principal
# =============================================================================
echo -e "${CYAN}Step 3 - Creating service principal 'cloudchipr'${RESET}"
echo ""

SP_JSON=$(databricks account service-principals create \
  --display-name "cloudchipr" \
  -o json \
  --profile cloudchipr-setup)

SP_ID=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
APP_ID=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['applicationId'])")

echo -e "${GREEN}  ✓ Service principal created${RESET}"
echo "    ID:             $SP_ID"
echo "    Application ID: $APP_ID"
echo ""

# =============================================================================
# Step 4 - Assign to workspace
# =============================================================================
echo -e "${CYAN}Step 4 - Assigning service principal to workspace${RESET}"
echo ""

databricks account workspace-assignment update \
  "$WORKSPACE_ID" \
  "$SP_ID" \
  --json '{"permissions": ["USER"]}' \
  --profile cloudchipr-setup >/dev/null

echo -e "${GREEN}  ✓ Assigned to workspace as USER${RESET}"
echo ""

# =============================================================================
# Step 5 - Generate OAuth secret
# =============================================================================
echo -e "${CYAN}Step 5 - Generating OAuth secret${RESET}"
echo ""

SECRET_JSON=$(databricks account service-principal-secrets create \
  "$SP_ID" \
  --profile cloudchipr-setup \
  -o json)

CLIENT_SECRET=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['secret'])")
EXPIRE_TIME=$(echo "$SECRET_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['expire_time'])")

echo -e "${GREEN}  ✓ Secret generated (expires: $EXPIRE_TIME)${RESET}"
echo ""

# =============================================================================
# Step 6 - Grant system table access (for precise dollar savings)
# =============================================================================
echo -e "${CYAN}Step 6 - Granting system table access${RESET}"
echo "  (requires a running SQL warehouse - skip with Ctrl+C if none available)"
echo ""

read -r -p "  SQL Warehouse ID (leave empty to skip): " WAREHOUSE_ID

if [ -n "$WAREHOUSE_ID" ]; then
  # Authenticate at workspace level for SQL execution
  echo ""
  echo "  Step 6 requires workspace-level authentication (browser will open again)."
  databricks auth login \
    --host "$WORKSPACE_HOST" \
    --profile cloudchipr-setup-ws >/dev/null 2>&1 || true

  WS_TOKEN=$(databricks auth token --profile cloudchipr-setup-ws -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || true)

  # Validate token before proceeding
  if [ -z "$WS_TOKEN" ]; then
    echo -e "${RED}  ✗ Failed to obtain workspace token${RESET}"
    SQL_FAILED=1
  else
    # Grant SP permission to use the warehouse
    databricks warehouses set-permissions "$WAREHOUSE_ID" \
      --json "{\"access_control_list\": [{\"service_principal_name\": \"${APP_ID}\", \"permission_level\": \"CAN_USE\"}]}" \
      --profile cloudchipr-setup-ws >/dev/null

    run_sql() {
      # Disable errexit temporarily to capture curl failures
      set +e
      RESPONSE=$(curl -s -X POST "${WORKSPACE_HOST}/api/2.0/sql/statements" \
        -H "Authorization: Bearer ${WS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"warehouse_id\": \"${WAREHOUSE_ID}\", \"statement\": \"$1\", \"wait_timeout\": \"10s\"}")
      CURL_EXIT=$?
      set -e

      if [ $CURL_EXIT -ne 0 ]; then
        echo -e "${RED}  ✗ Failed: $1${RESET}"
        echo -e "${RED}    curl error (exit code $CURL_EXIT)${RESET}"
        SQL_FAILED=1
        return
      fi

      STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
      if [ "$STATE" != "SUCCEEDED" ]; then
        echo -e "${RED}  ✗ Failed: $1${RESET}"
        echo -e "${RED}    $(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || true)${RESET}"
        SQL_FAILED=1
      else
        echo -e "${GREEN}  ✓ $1${RESET}"
      fi
    }

    SQL_FAILED=0

    run_sql "GRANT USE CATALOG ON CATALOG system TO \`${APP_ID}\`"
    run_sql "GRANT USE SCHEMA ON SCHEMA system.billing TO \`${APP_ID}\`"
    run_sql "GRANT USE SCHEMA ON SCHEMA system.compute TO \`${APP_ID}\`"
    run_sql "GRANT USE SCHEMA ON SCHEMA system.query TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.billing.usage TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.billing.list_prices TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.compute.node_timeline TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.query.history TO \`${APP_ID}\`"
  fi

  if [ $SQL_FAILED -eq 0 ]; then
    echo -e "${GREEN}  ✓ System table access granted${RESET}"
  else
    echo -e "${YELLOW}  ⚠ Some grants failed - dollar savings estimates will use list prices as fallback${RESET}"
    echo -e "${YELLOW}    Ensure the user running this script has Metastore Admin privileges${RESET}"
  fi
fi

echo ""

# =============================================================================
# Done - print credentials to use in Cloudchipr
# =============================================================================
echo -e "${GREEN}=== Setup complete! Use these credentials in Cloudchipr ===${RESET}"
echo ""
echo "  Workspace URL:  $WORKSPACE_HOST"
echo "  Client ID:      $APP_ID"
echo "  Client Secret:  $CLIENT_SECRET"
echo ""
echo -e "${YELLOW}  Keep the client secret safe - it cannot be retrieved again.${RESET}"
echo ""
