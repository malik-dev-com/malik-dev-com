#!/bin/bash

echo "init env"

OWNER="malik-dev-com"
REPO_NAME="try-github-cli"

# OWNER_ID, get with : 
# gh api graphql -f query='
# query {
#   viewer {
#     id
#   }
# }'

OWNER_ID="U_kgDODLdQyQ"

echo "declare methods"

create_sprint() {
  local name="$1"

  gh api graphql -f query="
  mutation {
    createProjectV2(input: {
      ownerId: \"$OWNER_ID\",
      title: \"$name\"
    }) {
      projectV2 {
        id
      }
    }
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['createProjectV2']['projectV2']['id'])"
}
add_to_sprint() {
  local project_id="$1"
  local issue_id="$2"

  gh api graphql -f query="
  mutation {
    addProjectV2ItemById(input: {
      projectId: \"$project_id\",
      contentId: \"$issue_id\"
    }) {
      item {
        id
      }
    }
  }"
}
new_issue() {
  local title="$1"
  local desc="$2"
  local labels="$3"

  desc="${desc:-}"
  labels="${labels:-}"

  local label_args=""
  if [ -n "$labels" ]; then
    IFS=',' read -ra arr <<< "$labels"
    for l in "${arr[@]}"; do
      label_args+=" --label \"$l\""
    done
  fi

  gh issue create \
    --title "$title" \
    --body "$desc" \
    $label_args \
    | grep -oE '#[0-9]+' | tr -d '#'
}
# Helper to add_parent & mark_blocking
get_issue_node_id() {
  local issue_number="$1"

  gh api graphql -f query="
  query {
    repository(owner: \"$OWNER\", name: \"$REPO_NAME\") {
      issue(number: $issue_number) {
        id
      }
    }
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['repository']['issue']['id'])"
}
add_parent() {
  local parent="$1"
  local child="$2"

  local parent_id
  parent_id=$(get_issue_node_id "$parent")

  local child_id
  child_id=$(get_issue_node_id "$child")

  # Ajout d’une relation via Projects (sub-issues)
  gh api graphql -f query="
  mutation {
    addSubIssue(input: {
      issueId: \"$parent_id\",
      subIssueId: \"$child_id\"
    }) {
      clientMutationId
    }
  }"
}
new_issue_child_of() {
  local title="$1"
  local desc="$2"
  local labels="$3"
  local parent="$4"

  local child
  child=$(new_issue "$title" "$desc" "$labels")

  add_parent "$parent" "$child"

  echo "$child"
}
new_issue_in_sprint() {
  local title="$1"
  local desc="$2"
  local labels="$3"
  local project_id="$4"

  local issue_number
  issue_number=$(new_issue "$title" "$desc" "$labels")

  local issue_id
  issue_id=$(get_issue_node_id "$issue_number")

  add_to_sprint "$project_id" "$issue_id"

  echo "$issue_number"
}
mark_blocking() {
  local blocker="$1"
  local blocked="$2"

  local blocker_id
  blocker_id=$(get_issue_node_id "$blocker")

  local blocked_id
  blocked_id=$(get_issue_node_id "$blocked")

  gh api graphql -f query="
  mutation {
    addIssueDependency(input: {
      blockingIssueId: \"$blocker_id\",
      blockedIssueId: \"$blocked_id\"
    }) {
      clientMutationId
    }
  }"
}
create_label() {
  local name="$1"
  local color="$2"
  local ignore="$3"

  if [ "$ignore" = true ]; then
    gh label create "$name" --color "$color" 2>/dev/null || true
  else
    gh label create "$name" --color "$color"
  fi
}

echo "call methods"

# Create a sprint (project) and capture its ID
PROJECT_ID=$(create_sprint "Test Sprint")

# Create a test issue
ISSUE_NUMBER=$(new_issue "Test issue" "This is a test" "test")

# Get its GraphQL ID
ISSUE_ID=$(get_issue_node_id "$ISSUE_NUMBER")

# Add issue to sprint
add_to_sprint "$PROJECT_ID" "$ISSUE_ID"

# Create blocking relation between two issues
ISSUE_A=$(new_issue "Blocking issue A" "desc")
ISSUE_B=$(new_issue "Blocked issue B" "desc")

mark_blocking "$ISSUE_A" "$ISSUE_B"

# Create parent and child issue
PARENT=$(new_issue "Parent issue" "desc")
CHILD=$(new_issue_child_of "Child issue" "desc" "" "$PARENT")