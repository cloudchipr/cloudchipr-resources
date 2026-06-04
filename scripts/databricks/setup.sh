#!/usr/bin/env bash
# =============================================================================
# Cloudchipr — Databricks Integration Setup
# =============================================================================
# This script creates a read-only service principal for Cloudchipr and grants
# it the minimum permissions needed to scan your Databricks workspace.
#
# Requirements:
#   - Databricks CLI v0.205+ installed via official installer (Homebrew, curl, WinGet, or Chocolatey)
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

for cmd in databricks python3 curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required dependency: $cmd" >&2
    exit 1
  fi
done

echo ""
echo -e "${CYAN}=== Cloudchipr Databricks Integration Setup ===${RESET}"
echo ""

# =============================================================================
# Step 1 — Collect inputs
# =============================================================================
echo -e "${CYAN}Step 1 — Enter your Databricks details${RESET}"
echo ""

read -r -p "  Workspace URL (e.g. https://dbc-xxxx.cloud.databricks.com): " WORKSPACE_HOST </dev/tty
read -r -p "  Account ID (from accounts.cloud.databricks.com): " ACCOUNT_ID </dev/tty

if [[ -z "$WORKSPACE_HOST" || -z "$ACCOUNT_ID" ]]; then
  echo -e "${RED}  ✗ Workspace URL and Account ID are required.${RESET}"
  exit 1
fi

if [[ ! "$WORKSPACE_HOST" =~ ^https:// ]]; then
  echo -e "${RED}  ✗ Workspace URL must start with https://${RESET}"
  exit 1
fi

# Strip query string, fragment, and trailing slash (handles browser copy-paste URLs)
WORKSPACE_HOST=$(echo "$WORKSPACE_HOST" | sed 's/[?#].*//' | sed 's|/$||')

echo ""

# =============================================================================
# Step 2 — Authenticate CLI at account level
# =============================================================================
echo -e "${CYAN}Step 2 — Authenticating with Databricks account (browser will open)${RESET}"
echo ""

# Remove stale profiles if they exist
python3 -c "
import configparser, os
path = os.path.expanduser('~/.databrickscfg')
cfg = configparser.ConfigParser()
cfg.read(path)
for section in ['cloudchipr-setup', 'cloudchipr-setup-ws']:
    if section in cfg:
        cfg.remove_section(section)
with open(path, 'w') as f:
    cfg.write(f)
" 2>/dev/null || true

databricks auth login \
  --host https://accounts.cloud.databricks.com \
  --account-id "$ACCOUNT_ID" \
  --profile cloudchipr-setup \
  --skip-workspace

echo -e "${GREEN}  ✓ Authenticated${RESET}"

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
  read -r -p "  Workspace ID (numeric, from workspace URL ?o=XXXXXXX): " WORKSPACE_ID </dev/tty
else
  echo -e "${GREEN}  ✓ Workspace ID detected: $WORKSPACE_ID${RESET}"
fi
echo ""

# =============================================================================
# Step 3 — Create service principal
# =============================================================================
echo -e "${CYAN}Step 3 — Creating service principal 'cloudchipr'${RESET}"
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
# Step 4 — Assign to workspace
# =============================================================================
echo -e "${CYAN}Step 4 — Assigning service principal to workspace${RESET}"
echo ""

databricks account workspace-assignment update \
  "$WORKSPACE_ID" \
  "$SP_ID" \
  --json '{"permissions": ["USER"]}' \
  --profile cloudchipr-setup >/dev/null

echo -e "${GREEN}  ✓ Assigned to workspace as USER${RESET}"
echo ""

# =============================================================================
# Step 5 — Generate OAuth secret
# =============================================================================
echo -e "${CYAN}Step 5 — Generating OAuth secret${RESET}"
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
# Step 6 — Grant system table access
# =============================================================================
echo -e "${CYAN}Step 6 — Granting system table access${RESET}"
echo "  (requires a running SQL warehouse — press Enter to skip if none available)"
echo ""

read -r -p "  SQL Warehouse ID (leave empty to skip): " WAREHOUSE_ID </dev/tty

if [ -n "$WAREHOUSE_ID" ]; then
  echo ""
  echo "  Step 6 requires workspace-level authentication (browser will open again)."

  databricks auth login \
    --host "$WORKSPACE_HOST" \
    --profile cloudchipr-setup-ws

  WS_TOKEN=$(databricks auth token --profile cloudchipr-setup-ws -o json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || true)

  if [ -z "$WS_TOKEN" ]; then
    echo -e "${RED}  ✗ Failed to obtain workspace token${RESET}"
    SQL_FAILED=1
  else
    # Grant SP CAN_USE on the warehouse via PATCH (non-fatal: won't wipe existing ACL)
    set +e
    databricks warehouses update-permissions "$WAREHOUSE_ID" \
      --json "{\"access_control_list\": [{\"service_principal_name\": \"${APP_ID}\", \"permission_level\": \"CAN_USE\"}]}" \
      --profile cloudchipr-setup-ws >/dev/null 2>&1
    WH_RC=$?
    set -e

    if [ $WH_RC -eq 0 ]; then
      echo -e "${GREEN}  ✓ Warehouse CAN_USE granted to service principal${RESET}"
    else
      echo -e "${YELLOW}  ⚠ Could not grant warehouse CAN_USE (non-fatal — continuing with GRANT statements)${RESET}"
    fi

    _sql_state() { echo "$1" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('state',''))" 2>/dev/null || echo ""; }

    _sql_errmsg() {
      echo "$1" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# Statement API error
if d.get('status', {}).get('error', {}).get('message'):
    print(d['status']['error']['message'])
# General Databricks API error (e.g. 401/403 responses)
elif d.get('message'):
    print(d['message'])
else:
    import json as j; print(j.dumps(d)[:400])
" 2>/dev/null || echo "${1:0:400}"
    }

    run_sql() {
      local stmt="$1"
      local response state stmt_id attempts
      set +e
      response=$(curl -s -X POST "${WORKSPACE_HOST}/api/2.0/sql/statements" \
        -H "Authorization: Bearer ${WS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"warehouse_id\":\"${WAREHOUSE_ID}\",\"statement\":\"${stmt}\",\"wait_timeout\":\"50s\"}")
      local rc=$?
      set -e

      if [ $rc -ne 0 ]; then
        echo -e "${RED}  ✗ curl error — ${stmt}${RESET}"
        SQL_FAILED=1
        return
      fi

      state=$(_sql_state "$response")

      # Poll if the warehouse is still starting (PENDING / RUNNING beyond the 50s wait)
      if [ "$state" = "PENDING" ] || [ "$state" = "RUNNING" ]; then
        stmt_id=$(echo "$response" | python3 -c \
          "import sys,json; print(json.load(sys.stdin).get('statement_id',''))" 2>/dev/null || echo "")
        attempts=0
        while { [ "$state" = "PENDING" ] || [ "$state" = "RUNNING" ]; } && [ $attempts -lt 12 ]; do
          sleep 10
          set +e
          response=$(curl -s "${WORKSPACE_HOST}/api/2.0/sql/statements/${stmt_id}" \
            -H "Authorization: Bearer ${WS_TOKEN}")
          set -e
          state=$(_sql_state "$response")
          attempts=$((attempts + 1))
        done
      fi

      if [ "$state" = "SUCCEEDED" ]; then
        echo -e "${GREEN}  ✓ ${stmt}${RESET}"
      else
        echo -e "${RED}  ✗ ${stmt}${RESET}"
        echo -e "${RED}    $(_sql_errmsg "$response")${RESET}"
        SQL_FAILED=1
      fi
    }

    SQL_FAILED=0

    run_sql "GRANT USE CATALOG ON CATALOG system TO \`${APP_ID}\`"
    run_sql "GRANT USE SCHEMA ON SCHEMA system.billing TO \`${APP_ID}\`"
    run_sql "GRANT USE SCHEMA ON SCHEMA system.compute TO \`${APP_ID}\`"
    run_sql "GRANT USE SCHEMA ON SCHEMA system.query TO \`${APP_ID}\`"
    run_sql "GRANT USE SCHEMA ON SCHEMA system.lakeflow TO \`${APP_ID}\`"
    run_sql "GRANT USE SCHEMA ON SCHEMA system.access TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.billing.usage TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.billing.list_prices TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.billing.account_prices TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.compute.node_timeline TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.compute.clusters TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.compute.warehouses TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.compute.warehouse_events TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.compute.node_types TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.query.history TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.lakeflow.jobs TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.lakeflow.job_run_timeline TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.lakeflow.job_task_run_timeline TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.lakeflow.job_tasks TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.lakeflow.pipelines TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.lakeflow.pipeline_update_timeline TO \`${APP_ID}\`"
    run_sql "GRANT SELECT ON TABLE system.access.workspaces_latest TO \`${APP_ID}\`"
  fi

  if [ "${SQL_FAILED:-0}" -eq 0 ]; then
    echo -e "${GREEN}  ✓ System table access granted${RESET}"
  else
    echo -e "${YELLOW}  ⚠ Some grants failed — ensure the authenticated user has Metastore Admin privileges${RESET}"
    echo -e "${YELLOW}    Dollar savings estimates will use list prices as fallback${RESET}"
  fi
else
  echo -e "${YELLOW}  ⚠ Skipped — dollar savings estimates will use list prices as fallback${RESET}"
fi

echo ""

# =============================================================================
# Done — print credentials to share with Cloudchipr
# =============================================================================
echo -e "${GREEN}=== Setup complete! Share these credentials with Cloudchipr ===${RESET}"
echo ""
echo "  Workspace URL:  $WORKSPACE_HOST"
echo "  Client ID:      $APP_ID"
echo "  Client Secret:  $CLIENT_SECRET"
echo ""
echo -e "${YELLOW}  Keep the client secret safe — it cannot be retrieved again.${RESET}"
echo ""
