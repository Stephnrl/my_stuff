"""Field resolution -- the part of Projects v2 that actually costs you time.

Nothing in Projects v2 is addressable by name. To set "Status = In Progress"
you need the project node id, the *field* node id, and for single-selects the
*option* node id. Iterations are worse: you need the iteration id, and the
current sprint is whichever iteration's date window contains today.

So: fetch the whole schema once, index it, and hand out ids. One round trip
per run instead of one per write.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field as dc_field
from datetime import date, datetime, timedelta
from typing import Any, Iterable

from .graphql import Client, GraphQLError

PROJECT_URL_RE = re.compile(
    r"github\.com/(?P<kind>orgs|users)/(?P<login>[^/]+)/projects/(?P<number>\d+)"
)

_SCHEMA_QUERY = """
query($login: String!, $number: Int!) {
  OWNER(login: $login) {
    projectV2(number: $number) {
      id
      title
      url
      fields(first: 50) {
        nodes {
          ... on ProjectV2FieldCommon { id name dataType }
          ... on ProjectV2SingleSelectField {
            id name dataType
            options { id name }
          }
          ... on ProjectV2IterationField {
            id name dataType
            configuration {
              duration
              iterations { id title startDate duration }
              completedIterations { id title startDate duration }
            }
          }
        }
      }
    }
  }
}
"""


class FieldNotFound(KeyError):
    pass


class OptionNotFound(KeyError):
    pass


@dataclass(frozen=True)
class Iteration:
    id: str
    title: str
    start: date
    duration_days: int
    completed: bool = False

    @property
    def end(self) -> date:
        return self.start + timedelta(days=self.duration_days)

    def contains(self, when: date) -> bool:
        return self.start <= when < self.end


@dataclass
class Field:
    id: str
    name: str
    data_type: str  # TEXT NUMBER DATE SINGLE_SELECT ITERATION ...
    options: dict[str, str] = dc_field(default_factory=dict)  # lower(name) -> id
    option_labels: list[str] = dc_field(default_factory=list)  # display casing
    iterations: list[Iteration] = dc_field(default_factory=list)

    def option_id(self, label: str) -> str:
        try:
            return self.options[label.strip().lower()]
        except KeyError:
            raise OptionNotFound(
                f"Field {self.name!r} has no option {label!r}. "
                f"Available: {sorted(o for o in self._option_names())}"
            ) from None

    def _option_names(self) -> Iterable[str]:
        return self.options.keys()

    def current_iteration(self, today: date | None = None) -> Iteration | None:
        today = today or date.today()
        for it in self.iterations:
            if not it.completed and it.contains(today):
                return it
        return None

    def next_iteration(self, today: date | None = None) -> Iteration | None:
        today = today or date.today()
        upcoming = sorted(
            (i for i in self.iterations if not i.completed and i.start > today),
            key=lambda i: i.start,
        )
        return upcoming[0] if upcoming else None

    def iteration_id(self, title: str) -> str:
        wanted = title.strip().lower()
        for it in self.iterations:
            if it.title.strip().lower() == wanted:
                return it.id
        raise OptionNotFound(
            f"No iteration titled {title!r} on field {self.name!r}. "
            f"Available: {[i.title for i in self.iterations]}"
        )


@dataclass
class Project:
    id: str
    number: int
    title: str
    url: str
    login: str
    is_org: bool
    fields: dict[str, Field]  # lower(name) -> Field

    def field(self, name: str) -> Field:
        try:
            return self.fields[name.strip().lower()]
        except KeyError:
            raise FieldNotFound(
                f"No field named {name!r} on project {self.title!r}. "
                f"Available: {sorted(f.name for f in self.fields.values())}"
            ) from None

    def has_field(self, name: str) -> bool:
        return name.strip().lower() in self.fields


def parse_project_url(url: str) -> tuple[str, bool, int]:
    """-> (login, is_org, number). Raises ValueError on anything unparseable."""
    m = PROJECT_URL_RE.search(url)
    if not m:
        raise ValueError(
            f"Cannot parse project URL {url!r}. Expected e.g. "
            "https://github.com/orgs/ACME/projects/42"
        )
    return m["login"], m["kind"] == "orgs", int(m["number"])


def _parse_iterations(config: dict[str, Any]) -> list[Iteration]:
    out: list[Iteration] = []
    for key, completed in (("iterations", False), ("completedIterations", True)):
        for raw in config.get(key) or []:
            out.append(
                Iteration(
                    id=raw["id"],
                    title=raw["title"],
                    start=datetime.strptime(raw["startDate"], "%Y-%m-%d").date(),
                    duration_days=int(raw["duration"]),
                    completed=completed,
                )
            )
    return sorted(out, key=lambda i: i.start)


def load_project(client: Client, project_url: str) -> Project:
    """One round trip; everything you need to write fields afterwards."""
    login, is_org, number = parse_project_url(project_url)
    root = "organization" if is_org else "user"
    query = _SCHEMA_QUERY.replace("OWNER", root)

    data = client.execute(query, login=login, number=number)
    owner = data.get(root)
    if not owner or not owner.get("projectV2"):
        raise GraphQLError(
            f"Project #{number} not visible to this token under {root} "
            f"{login!r}. If the project exists, the token cannot see it -- "
            "see the auth checklist in auth.py."
        )

    raw = owner["projectV2"]
    fields: dict[str, Field] = {}

    for node in raw["fields"]["nodes"]:
        if not node:
            continue
        f = Field(id=node["id"], name=node["name"], data_type=node["dataType"])
        if opts := node.get("options"):
            f.options = {o["name"].strip().lower(): o["id"] for o in opts}
            f.option_labels = [o["name"].strip() for o in opts]
        if cfg := node.get("configuration"):
            f.iterations = _parse_iterations(cfg)
        fields[f.name.strip().lower()] = f

    return Project(
        id=raw["id"],
        number=number,
        title=raw["title"],
        url=raw["url"],
        login=login,
        is_org=is_org,
        fields=fields,
    )


def encode_value(field: Field, value: Any) -> dict[str, Any]:
    """Build the ``ProjectV2FieldValue`` input for a field, resolving ids."""
    if value is None:
        raise ValueError("use board.clear_field() to unset a value")

    match field.data_type:
        case "TEXT":
            return {"text": str(value)}
        case "NUMBER":
            return {"number": float(value)}
        case "DATE":
            if isinstance(value, date):
                return {"date": value.isoformat()}
            return {"date": str(value)}  # expects YYYY-MM-DD
        case "SINGLE_SELECT":
            return {"singleSelectOptionId": field.option_id(str(value))}
        case "ITERATION":
            if isinstance(value, Iteration):
                return {"iterationId": value.id}
            return {"iterationId": field.iteration_id(str(value))}
        case other:
            raise ValueError(
                f"Field {field.name!r} has type {other}, which is not writable "
                "via updateProjectV2ItemFieldValue (labels, milestones, "
                "assignees and repository are derived from the issue itself)."
            )
