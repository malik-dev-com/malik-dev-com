# GitLab Issue & Task Generation Guide

### WARNING :

- this uses GitLab tasks and relations which are not available in the free version of GitLab
- cannot create or link issues to a Sprint (it's possible, I'm just lazy)
- only one label per issue, and no label on tasks. not happy? do it yourself:
    - make new_issue() accept an array of labels
    - make new_task() $2 actually work (no idea why it doesn't)
        - then make it accept an array of labels like the previous method


## Overview

This document provides a reusable and generic approach to programmatically create issues, tasks, and relationships in GitLab using the CLI (glab) and APIs (REST + GraphQL).

The goal is to:

- Automate project setup
- Standardize issue structures
- Save time during project initialization

## Prerequisites

### Install GitLab CLI

```bash
sudo apt install glab
```

### Authenticate

```bash
glab auth login
```

Important: Never commit your token.

## Environment Variables

Use environment variables to keep your script reusable:

```bash
export REPO="<namespace>/<project>"
export HOST="gitlab.example.com"
export PROJECT_PATH="<namespace>%2F<project>"
export PROJECT_FULLPATH="<namespace>/<project>"
export PROJECT_ID="12345"
```

or directly in the script:

```bash
REPO="<namespace>/<project>"
HOST="gitlab.example.com"
PROJECT_PATH="<namespace>%2F<project>" # replace '/' by '%2F'
PROJECT_FULLPATH="<namespace>/<project>"
PROJECT_ID="12345" # get it with : glab api projects/<namespace>%2F<project>


# GraphQL Global IDs (GID) for work item types.
# 5 = Task, 1 = Issue.
# These IDs are required when creating work items via the GraphQL API.
# They can be retrieved using the workItemTypes query on the project.

TASK_TYPE_ID="gid://gitlab/WorkItems::Type/5" # id of tasks (child of issue) in gitlab
ISSUE_TYPE_ID="gid://gitlab/WorkItems::Type/1"
```

## Creating Labels

```bash
glab label create -R "$REPO" --name "name" --color "#e44c41"
```

Ignore errors if the label already exists:

```bash
glab label create -R "$REPO" --name "name" --color "#e44c41" 2>/dev/null || true
```

## Creating Issues

```bash
new_issue() {
  local title="$1" label="$2" desc="$3"
  glab issue create \
    -R "$REPO" \
    --title "$title" \
    --label "$label" \
    --description "$desc" \
    --no-editor > /dev/null 2>&1
  # get the last created issue
  local result
  result=$(glab api --hostname "$HOST" \
    "projects/$PROJECT_PATH/issues?order_by=created_at&sort=desc&per_page=1" \
    | python3 -c "import sys,json; i=json.load(sys.stdin)[0]; print(i['iid'], i['id'])")
  echo "$result"
}
```

## Get GraphQL GID of a work item from IID (issue number: #1, #42, etc.)

```bash
get_gid() {
  local iid="$1"
  glab api --hostname "$HOST" graphql -f query="
  {
    project(fullPath: \"$PROJECT_FULLPATH\") {
      workItems(iids: [\"$iid\"]) {
        nodes { id }
      }
    }
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['project']['workItems']['nodes'][0]['id'])"
}
```

Create a new Task (GitLab Premium) and attach it to its parent

```bash
new_task() {
  local title="$1" label="$2" parent_gid="$3"

  # Crée la Task via GraphQL
  local task_gid
  task_gid=$(glab api --hostname "$HOST" graphql -f query="
  mutation {
    workItemCreate(input: {
      projectPath: \"$PROJECT_FULLPATH\"
      title: \"$title\"
      workItemTypeId: \"$TASK_TYPE_ID\"
    }) {
      workItem { id iid }
      errors
    }
  }" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['workItemCreate']['workItem']['id'])")

  if [ -z "$task_gid" ]; then
    echo "  ⚠ task non créée : $title" >&2
    return
  fi

  # Attache la Task au parent
  local errors
  errors=$(glab api --hostname "$HOST" graphql -f query="
  mutation {
    workItemUpdate(input: {
      id: \"$task_gid\"
      hierarchyWidget: { parentId: \"$parent_gid\" }
    }) {
      workItem { id title }
      errors
    }
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['workItemUpdate']['errors'])")

  if [ "$errors" = "[]" ]; then
    echo "  ✓ task créée et attachée : $title"
  else
    echo "  ⚠ task créée mais attachement échoué ($errors) : $title"
  fi
}
```

Create a "blocks" relation between two issues ($2 is blocked by $1)

```bash
blocks() {
  local source="$1" target="$2"
  if [ -z "$source" ] || [ -z "$target" ]; then
    echo "  ⚠ relation ignorée (IID vide)"
    return
  fi
  glab api --hostname "$HOST" \
    "projects/$PROJECT_PATH/issues/$source/links" \
    -X POST \
    -F "target_project_id=$PROJECT_ID" \
    -F "target_issue_iid=$target" \
    -F "link_type=blocks" > /dev/null \
    && echo "  ✓ #$source bloque #$target" \
    || echo "  ⚠ relation échouée #$source → #$target"
}
```

## Example usage

```bash
echo "init env"

REPO="daniel_leberre/pacman"
PROJECT_PATH="daniel_leberre%2Fpacman"
PROJECT_FULLPATH="daniel_leberre/pacman"
PROJECT_ID="25338"
HOST="gitlab.univ-artois.fr"
TASK_TYPE_ID="gid://gitlab/WorkItems::Type/5"
ISSUE_TYPE_ID="gid://gitlab/WorkItems::Type/1"


echo "create label"

glab label create -R "$REPO" --name "fix"  --color "#ff0000" 2>/dev/null || true
glab label create -R "$REPO" --name "dev" --color "#8800ff" 2>/dev/null || true
glab label create -R "$REPO" --name "docs"   --color "#0000ff" 2>/dev/null || true
glab label create -R "$REPO" --name "test"   --color "#00ff00" 2>/dev/null || true

echo "declare method"

new_issue() {...}

get_gid() {...}

new_task() {...}

blocks() {...}

echo "create issue-1"

read ISSUE1_IID ISSUE1_ID <<< $(new_issue \
    "[ISSUE-1] Title of the issue number 1" "label"
    "Description if the issue 1")
ISSUE1_GID=$(get_git "$ISSUE1_IID")
echo "-> IID: $ISSUE1_IID | GID: $ISSUE1_GID"

new_task "Title of the task 1" "labelThatDoesNotWork" "$ISSUE1_GID"
new_task "Title of the task 2" "labelThatDoesNotWork" "$ISSUE1_GID"
new_task "Title of the task 3" "labelThatDoesNotWork" "$ISSUE1_GID"
new_task "Title of the task 4" "labelThatDoesNotWork" "$ISSUE1_GID"

echo "create issue-2"

# etc.

echo "create issue-3"

# etc.

echo "create issue-4"

# etc.

echo "create blocks relation"

blocks "$ISSUE1_IID" "ISSUE2_IID"
blocks "$ISSUE1_IID" "ISSUE3_IID"

blocks "$ISSUE2_IID" "ISSUE4_IID"
blocks "$ISSUE3_IID" "ISSUE4_IID"
