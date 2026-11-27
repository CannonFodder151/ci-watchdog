#!/bin/bash
set -euo pipefail

WORKFLOW_NAME="${WORKFLOW_NAME}"
WORKFLOW_RUN_ID="${WORKFLOW_RUN_ID}"
WORKFLOW_RUN_URL="${WORKFLOW_RUN_URL}"
REPO="${REPO}"
BRANCH="${BRANCH}"
COMMIT_SHA="${COMMIT_SHA}"
COMMIT_MESSAGE="${COMMIT_MESSAGE}"
COMMIT_AUTHOR="${COMMIT_AUTHOR}"
RUN_STARTED_AT="${RUN_STARTED_AT}"
RUN_ENDED_AT="${RUN_ENDED_AT}"
CONCLUSION="${CONCLUSION}"

AGENT_MAPPING='
{
  "CI": "6764b91c-3ed1-4a04-89b1-0395f72dd31a",
  "CD": "6764b91c-3ed1-4a04-89b1-0395f72dd31a"
}'

AGENT_ID=$(echo "$AGENT_MAPPING" | jq -r --arg wf "$WORKFLOW_NAME" '.[$wf] // "6764b91c-3ed1-4a04-89b1-0395f72dd31a"')

LOG_SUMMARY=""
if [ -d "logs" ]; then
  LOG_SUMMARY=$(find logs -type f -name "*.txt" -exec head -100 {} \; 2>/dev/null | head -200 || echo "No logs available")
fi

cat > /tmp/issue_body.md <<EOF
## 🚨 CI/CD Failure: $WORKFLOW_NAME

**Workflow Run:** #$WORKFLOW_RUN_ID
**Repository:** $REPO
**Branch:** $BRANCH
**Commit:** $COMMIT_SHA
**Author:** $COMMIT_AUTHOR
**Started:** $RUN_STARTED_AT
**Ended:** $RUN_ENDED_AT
**Conclusion:** $CONCLUSION

[View Workflow Run]($WORKFLOW_RUN_URL)

---

### 📋 Failure Summary
Workflow \`$WORKFLOW_NAME\` failed on branch \`$BRANCH\` at commit \`$COMMIT_SHA\`.

### 📝 Commit Message
$COMMIT_MESSAGE

---

### 📄 Logs (truncated)
\`\`\`
$LOG_SUMMARY
\`\`\`

---

### 🔧 Postmortem Template
<!-- Fill in after investigation -->

#### Root Cause
- What caused the failure?

#### Impact
- What was affected?
- How long was it broken?

#### Resolution
- How was it fixed?
- Any workarounds?

#### Prevention
- What will prevent recurrence?
- Any process/tooling changes needed?

#### MTTR Tracking
- **Detected:** $RUN_ENDED_AT
- **Investigated:** 
- **Resolved:** 
- **Total MTTR:** 

---

### 🤖 Assigned Agent
Agent ID: $AGENT_ID

### 🏷️ Labels
ci-failure, $WORKFLOW_NAME, needs-investigation
EOF

GH_ASSIGNEE=$(echo "$AGENT_MAPPING" | jq -r --arg wf "$WORKFLOW_NAME" '.[$wf] // empty')

BODY_CONTENT=$(cat /tmp/issue_body.md)

if [[ "$GH_ASSIGNEE" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]){0,38}$ ]] && [[ ! "$GH_ASSIGNEE" =~ ^[0-9a-f-]{36}$ ]]; then
  ISSUE_RESPONSE=$(curl -s -X POST "https://api.github.com/repos/$REPO/issues" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$(jq -n \
      --arg title "🚨 CI Failure: $WORKFLOW_NAME on $BRANCH" \
      --arg body "$BODY_CONTENT" \
      --argjson labels '["ci-failure", "'"$WORKFLOW_NAME"'", "needs-investigation"]' \
      --arg assignee "$GH_ASSIGNEE" \
      '{title: $title, body: $body, labels: $labels, assignees: [$assignee]}')")
else
  ISSUE_RESPONSE=$(curl -s -X POST "https://api.github.com/repos/$REPO/issues" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$(jq -n \
      --arg title "🚨 CI Failure: $WORKFLOW_NAME on $BRANCH" \
      --arg body "$BODY_CONTENT" \
      --argjson labels '["ci-failure", "'"$WORKFLOW_NAME"'", "needs-investigation"]' \
      '{title: $title, body: $body, labels: $labels}')")
fi

ISSUE_NUMBER=$(echo "$ISSUE_RESPONSE" | jq -r '.number // empty')
ISSUE_ID=$(echo "$ISSUE_RESPONSE" | jq -r '.id // empty')
ISSUE_URL=$(echo "$ISSUE_RESPONSE" | jq -r '.html_url // empty')

if [ -z "$ISSUE_NUMBER" ] || [ "$ISSUE_NUMBER" = "null" ]; then
  echo "Failed to create issue"
  echo "$ISSUE_RESPONSE"
  exit 1
fi

echo "Created issue #$ISSUE_NUMBER: $ISSUE_URL"

PAPERCLIP_ISSUE_RESPONSE=$(curl -s -X POST "$PAPERCLIP_API_URL/api/companies/df33b840-b692-45ba-9a95-62d2341c95e6/issues" \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg title "🚨 CI Failure: $WORKFLOW_NAME on $BRANCH" \
    --arg description "$BODY_CONTENT" \
    --arg status "todo" \
    --arg project_id "default" \
    --arg assignee_agent_id "$AGENT_ID" \
    --argjson metadata "{\"github_issue_number\": $ISSUE_NUMBER, \"github_issue_url\": \"$ISSUE_URL\", \"workflow_run_id\": $WORKFLOW_RUN_ID, \"workflow_name\": \"$WORKFLOW_NAME\", \"branch\": \"$BRANCH\", \"commit_sha\": \"$COMMIT_SHA\"}" \
    '{title: $title, description: $description, status: $status, project_id: $project_id, assignee_agent_id: $assignee_agent_id, metadata: $metadata}')")

PAPERCLIP_ISSUE_ID=$(echo "$PAPERCLIP_ISSUE_RESPONSE" | jq -r '.id // empty')

if [ -z "$PAPERCLIP_ISSUE_ID" ] || [ "$PAPERCLIP_ISSUE_ID" = "null" ]; then
  echo "Warning: Failed to create Paperclip issue"
  echo "$PAPERCLIP_ISSUE_RESPONSE"
  PAPERCLIP_ISSUE_ID=""
fi

if [ -n "$PAPERCLIP_ISSUE_ID" ] && [ "$PAPERCLIP_ISSUE_ID" != "null" ]; then
  curl -s -X PATCH "https://api.github.com/repos/$REPO/issues/$ISSUE_NUMBER" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$(jq -n --arg body "$BODY_CONTENT\n\n---\n**Paperclip Issue ID:** $PAPERCLIP_ISSUE_ID" '{body: $body}')" > /dev/null
fi

echo "issue_number=$ISSUE_NUMBER" >> $GITHUB_OUTPUT
echo "issue_id=$PAPERCLIP_ISSUE_ID" >> $GITHUB_OUTPUT
echo "agent_id=$AGENT_ID" >> $GITHUB_OUTPUT