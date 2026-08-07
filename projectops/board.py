"""High-level board operations built on the resolved project schema."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

from .fields import Project, encode_value
from .graphql import Client

log = logging.getLogger("projectops.board")

_ISSUE_NODE = """
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      id title body state stateReason
      issueType { name }
      labels(first: 50) { nodes { name } }
      assignees(first: 10) { nodes { login } }
      parent { id number title }
    }
  }
}
"""

_ADD_ITEM = """
mutation($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
    item { id }
  }
}
"""

_SET_FIELD = """
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!,
         $value: ProjectV2FieldValue!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId, itemId: $itemId,
    fieldId: $fieldId, value: $value
  }) { projectV2Item { id } }
}
"""

_CLEAR_FIELD = """
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!) {
  clearProjectV2ItemFieldValue(input: {
    projectId: $projectId, itemId: $itemId, fieldId: $fieldId
  }) { projectV2Item { id } }
}
"""

_ITEM_FOR_CONTENT = """
query($projectId: ID!, $cursor: String) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          content { ... on Issue { id number } ... on PullRequest { id number } }
        }
      }
    }
  }
}
"""

_ADD_SUB_ISSUE = """
mutation($parentId: ID!, $childId: ID!) {
  addSubIssue(input: {issueId: $parentId, subIssueId: $childId}) {
    issue { number }
  }
}
"""


@dataclass
class Issue:
    node_id: str
    number: int
    title: str
    body: str
    state: str
    state_reason: str | None
    issue_type: str | None
    labels: list[str]
    assignees: list[str]
    parent_number: int | None


class Board:
    def __init__(self, client: Client, project: Project):
        self.client = client
        self.project = project
        self._item_cache: dict[str, str] | None = None  # content node id -> item id

    # ---------------------------------------------------------------- reads

    def fetch_issue(self, owner: str, repo: str, number: int) -> Issue:
        data = self.client.execute(
            _ISSUE_NODE, owner=owner, repo=repo, number=number
        )
        raw = (data.get("repository") or {}).get("issue")
        if not raw:
            raise LookupError(f"{owner}/{repo}#{number} not found")

        return Issue(
            node_id=raw["id"],
            number=number,
            title=raw["title"],
            body=raw.get("body") or "",
            state=raw["state"],
            state_reason=raw.get("stateReason"),
            issue_type=(raw.get("issueType") or {}).get("name"),
            labels=[n["name"] for n in raw["labels"]["nodes"]],
            assignees=[n["login"] for n in raw["assignees"]["nodes"]],
            parent_number=(raw.get("parent") or {}).get("number"),
        )

    def _load_items(self) -> dict[str, str]:
        """Page the whole board once. Cheaper than a lookup query per item."""
        if self._item_cache is not None:
            return self._item_cache

        cache: dict[str, str] = {}
        cursor: str | None = None
        while True:
            data = self.client.execute(
                _ITEM_FOR_CONTENT, projectId=self.project.id, cursor=cursor
            )
            items = data["node"]["items"]
            for node in items["nodes"]:
                if content := node.get("content"):
                    cache[content["id"]] = node["id"]
            if not items["pageInfo"]["hasNextPage"]:
                break
            cursor = items["pageInfo"]["endCursor"]

        self._item_cache = cache
        return cache

    # --------------------------------------------------------------- writes

    def ensure_item(self, content_node_id: str) -> str:
        """Add content to the board if absent; return the project item id.

        ``addProjectV2ItemById`` is idempotent -- re-adding existing content
        returns the existing item rather than erroring -- so we could always
        call it. We check the cache first purely to save rate-limit points.
        """
        if existing := self._load_items().get(content_node_id):
            return existing

        data = self.client.execute(
            _ADD_ITEM, projectId=self.project.id, contentId=content_node_id
        )
        item_id = data["addProjectV2ItemById"]["item"]["id"]
        if self._item_cache is not None:
            self._item_cache[content_node_id] = item_id
        return item_id

    def set_field(self, item_id: str, field_name: str, value: Any) -> None:
        field = self.project.field(field_name)
        self.client.execute(
            _SET_FIELD,
            projectId=self.project.id,
            itemId=item_id,
            fieldId=field.id,
            value=encode_value(field, value),
        )
        log.info("set %s = %r", field.name, value)

    def clear_field(self, item_id: str, field_name: str) -> None:
        field = self.project.field(field_name)
        self.client.execute(
            _CLEAR_FIELD,
            projectId=self.project.id,
            itemId=item_id,
            fieldId=field.id,
        )

    def apply(self, item_id: str, values: dict[str, Any]) -> dict[str, str]:
        """Set several fields, collecting per-field failures instead of
        aborting. A bad Priority value should not block the Status update."""
        errors: dict[str, str] = {}
        for name, value in values.items():
            if value is None:
                continue
            if not self.project.has_field(name):
                errors[name] = "field not on board"
                continue
            try:
                self.set_field(item_id, name, value)
            except Exception as exc:  # noqa: BLE001 - reported, not swallowed
                errors[name] = str(exc)
        return errors

    def link_sub_issue(self, parent_node_id: str, child_node_id: str) -> None:
        """Epic -> Story -> Task hierarchy via native sub-issues."""
        self.client.execute(
            _ADD_SUB_ISSUE, parentId=parent_node_id, childId=child_node_id
        )
