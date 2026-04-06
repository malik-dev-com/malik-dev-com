## WARNING

- This project is not finished because GitHub suspended my account when I tried to create 4 issues, 2 sprints, 3 labels, and 5 relationships (parent / blocking) via the API
- Automated API usage can trigger rate limits or abuse detection, very efficient, they also block the current user to preserve the server.
- Be careful when running "bulk" operations (yes, even 20 requests can be considered bulk for GitHub) against the GitHub API.

```bash
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
```

```bash
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
```

```bash
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
```

```bash
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
```

```bash
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
```

```bash
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
```

```bash
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
```

```bash
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
```

```bash
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
```