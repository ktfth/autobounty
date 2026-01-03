#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"

LAST_RUN_FILE="$ROOT_DIR/output/LAST_RUN"
require_file "$LAST_RUN_FILE"

RUN_ID="$(cat "$LAST_RUN_FILE")"
OUT_DIR="$ROOT_DIR/output/$RUN_ID"
require_dir "$OUT_DIR"

REPORT_MD="$OUT_DIR/REPORT.md"
HTTPX_JSON="$OUT_DIR/httpx.json"
TECH_JSON="$OUT_DIR/technologies.json"
TARGETS_JSON="$OUT_DIR/targets_analysis.json"
TECH_STATUS="$OUT_DIR/tech_analysis.status.json"

log "Building technology reconnaissance report for RUN_ID=$RUN_ID..."

# Count artifacts
alive_count="$(test -f "$OUT_DIR/alive.urls.txt" && wc -l < "$OUT_DIR/alive.urls.txt" | tr -d ' ' || echo 0)"
sub_count="$(test -f "$OUT_DIR/subdomains.txt" && wc -l < "$OUT_DIR/subdomains.txt" | tr -d ' ' || echo 0)"
ports_count="$(test -f "$OUT_DIR/open.ports.txt" && wc -l < "$OUT_DIR/open.ports.txt" | tr -d ' ' || echo 0)"

# Parse tech analysis status
tech_status="unknown"
admin_count=0
dev_count=0
interesting_count=0

if [[ -f "$TECH_STATUS" ]]; then
  tech_status=$(jq -r '.status // "unknown"' "$TECH_STATUS" 2>/dev/null || echo "unknown")
  admin_count=$(jq -r '.admin_panels // 0' "$TECH_STATUS" 2>/dev/null || echo 0)
  dev_count=$(jq -r '.dev_envs // 0' "$TECH_STATUS" 2>/dev/null || echo 0)
  interesting_count=$(jq -r '.interesting_tech // 0' "$TECH_STATUS" 2>/dev/null || echo 0)
fi

# Extract top technologies
declare -A tech_stats
tech_list=""

if [[ -f "$TECH_JSON" ]]; then
  # Count technology occurrences
  while IFS= read -r tech; do
    if [[ -n "$tech" ]]; then
      tech_stats["$tech"]=$((${tech_stats["$tech"]:-0} + 1))
    fi
  done < <(jq -r '.[].technologies[]?' "$TECH_JSON" 2>/dev/null || true)

  # Build sorted list
  for tech in "${!tech_stats[@]}"; do
    count="${tech_stats[$tech]}"
    tech_list+="- **$tech**: ${count} site(s)\n"
  done
  tech_list=$(echo -e "$tech_list" | sort -rn -t: -k2 || echo "")
fi

# Status emoji
case "$tech_status" in
  success) tech_emoji="✅" ;;
  skipped) tech_emoji="⏭️" ;;
  *) tech_emoji="❓" ;;
esac

{
  echo "# Bug Bounty Technology Reconnaissance Report"
  echo
  echo "**Run ID:** \`$RUN_ID\`  "
  echo "**Generated:** $(date +'%Y-%m-%d %H:%M:%S')"
  echo
  echo "## Summary"
  echo
  echo "| Metric | Count |"
  echo "|--------|-------|"
  echo "| Subdomains Discovered | **$sub_count** |"
  echo "| Live Web Services | **$alive_count** |"
  echo "| Open Ports | **$ports_count** |"
  echo "| Potential Admin Panels | **$admin_count** |"
  echo "| Dev/Staging Environments | **$dev_count** |"
  echo "| Interesting Technologies | **$interesting_count** |"
  echo
  echo "## Analysis Status $tech_emoji"
  echo
  echo "- **Status:** \`$tech_status\`"
  echo "- **Admin Panels Detected:** $admin_count"
  echo "- **Dev Environments:** $dev_count"
  echo "- **Interesting Tech Stack:** $interesting_count"

  echo
  echo "## Technology Stack Detected"
  echo

  if [[ -n "$tech_list" ]]; then
    echo "$tech_list"
  else
    echo "_No technologies detected or analysis not available._"
  fi

  echo
  echo "## 🎯 High-Value Targets"
  echo

  # Show high-value targets based on analysis
  if [[ -f "$TARGETS_JSON" ]]; then
    echo "### 🔐 Admin Panels & Dashboards"
    echo
    ADMIN_LIST=$(jq -r '.[] | select(.is_admin == true) | "- [\(.title)](\(.url)) - \(.status_code) - Server: \(.server)"' \
      "$TARGETS_JSON" 2>/dev/null | head -n 20)
    if [[ -n "$ADMIN_LIST" ]]; then
      echo "$ADMIN_LIST"
    else
      echo "_None detected_"
    fi

    echo
    echo "### 🔧 Development/Staging Environments"
    echo
    DEV_LIST=$(jq -r '.[] | select(.is_dev == true) | "- [\(.url)](\(.url)) - \(.title)"' \
      "$TARGETS_JSON" 2>/dev/null | head -n 20)
    if [[ -n "$DEV_LIST" ]]; then
      echo "$DEV_LIST"
    else
      echo "_None detected_"
    fi

    echo
    echo "### ⚡ Interesting Technology Stack"
    echo
    TECH_LIST=$(jq -r '.[] | select(.has_interesting_tech == true) | "- [\(.url)](\(.url)) - Technologies: \(.technologies | join(", "))"' \
      "$TARGETS_JSON" 2>/dev/null | head -n 20)
    if [[ -n "$TECH_LIST" ]]; then
      echo "$TECH_LIST"
    else
      echo "_None detected_"
    fi
  fi

  echo
  echo "## Output Files"
  echo
  echo "### Reconnaissance Data"
  echo "- \`scope.normalized.txt\` - Normalized target domains"
  echo "- \`subdomains.txt\` - Discovered subdomains ($sub_count)"
  echo "- \`alive.urls.txt\` - Live web services ($alive_count)"
  echo "- \`alive.hosts.txt\` - Live hosts"
  echo "- \`httpx.json\` - Detailed HTTP probe results"
  echo "- \`naabu.json\` - Port scan results"
  echo "- \`open.ports.txt\` - Open ports list ($ports_count)"
  echo
  echo "### Technology Analysis"
  echo "- \`technologies.json\` - Detected technology stacks"
  echo "- \`targets_analysis.json\` - Comprehensive target analysis"
  echo "- \`tech_analysis.status.json\` - Analysis status and stats"
  echo
  echo "## Next Steps"
  echo
  echo "1. **Review Targets by Priority:**"
  echo "   \`\`\`bash"
  echo "   # Admin panels (highest priority)"
  echo "   jq -r '.[] | select(.is_admin == true) | .url' output/$RUN_ID/targets_analysis.json"
  echo
  echo "   # Dev/staging environments (good for testing)"
  echo "   jq -r '.[] | select(.is_dev == true) | .url' output/$RUN_ID/targets_analysis.json"
  echo "   \`\`\`"
  echo
  echo "2. **Filter by Technology:**"
  echo "   \`\`\`bash"
  echo "   # Find all WordPress sites"
  echo "   jq -r '.[] | select(.technologies[]? == \"WordPress\") | .url' output/$RUN_ID/technologies.json"
  echo
  echo "   # Find all sites with specific server"
  echo "   jq -r '.[] | select(.server | contains(\"Apache\")) | .url' output/$RUN_ID/targets_analysis.json"
  echo "   \`\`\`"
  echo
  echo "3. **Export for Manual Testing:**"
  echo "   \`\`\`bash"
  echo "   # All interesting targets to a file"
  echo "   jq -r '.[] | select(.is_admin == true or .is_dev == true or .has_interesting_tech == true) | .url' \\"
  echo "     output/$RUN_ID/targets_analysis.json > priority_targets.txt"
  echo "   \`\`\`"
  echo
  echo "4. **Manual Testing Checklist:**"
  echo "   - [ ] Test admin panels for default credentials"
  echo "   - [ ] Check dev/staging for exposed secrets or debug info"
  echo "   - [ ] Look for version disclosure in technologies"
  echo "   - [ ] Test for common vulnerabilities in detected tech stack"
  echo "   - [ ] Check unusual ports for exposed services"
  echo
  echo "---"
  echo "_Generated by AutoBounty Technology Recon Pipeline_"
} > "$REPORT_MD"

log "✓ Report generated: $REPORT_MD"
echo
cat "$REPORT_MD"
