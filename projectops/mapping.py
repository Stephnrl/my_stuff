"""Rules engine: issue event -> board field values.

Kept deliberately dumb and declarative. Every decision this file makes is one
an agent does not have to make, which keeps the AI layer for the genuinely
ambiguous calls (is this a bug or a feature, how big is this story).

Rules are evaluated top to bottom; **the last matching rule wins**, so order
config from general to specific.
"""

from __future__ import annotations

from dataclasses import dataclass, field as dc_field
from datetime import date
from typing import Any

from .board import Issue
from .fields import Project


def _norm(value: str | None) -> str:
    """Collapse case, underscores, spaces and hyphens for lenient matching."""
    return "".join(c for c in (value or "").lower() if c.isalnum())


@dataclass(frozen=True)
class Condition:
    """All present keys must match (AND). Absent keys are ignored."""

    event: str | None = None            # opened|closed|reopened|labeled|assigned
    label: str | None = None            # issue carries this label
    any_label: tuple[str, ...] = ()     # issue carries at least one of these
    issue_type: str | None = None       # Epic|Feature|Story|Task
    state: str | None = None            # OPEN|CLOSED
    state_reason: str | None = None     # COMPLETED|NOT_PLANNED|REOPENED
    assigned: bool | None = None        # has at least one assignee

    def matches(self, issue: Issue, event: str) -> bool:
        labels = {label.lower() for label in issue.labels}

        if self.event and self.event.lower() != event.lower():
            return False
        if self.label and self.label.lower() not in labels:
            return False
        if self.any_label and not labels & {a.lower() for a in self.any_label}:
            return False
        if self.issue_type and (issue.issue_type or "").lower() != self.issue_type.lower():
            return False
        if self.state and (issue.state or "").upper() != self.state.upper():
            return False
        if self.state_reason:
            # Accept NOT_PLANNED / "not planned" / not-planned interchangeably.
            if _norm(issue.state_reason) != _norm(self.state_reason):
                return False
        if self.assigned is not None and bool(issue.assignees) != self.assigned:
            return False
        return True


@dataclass(frozen=True)
class Rule:
    when: Condition
    set: dict[str, Any] = dc_field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.set:
            raise ValueError("a rule with no 'set' block does nothing")


@dataclass
class Plan:
    """What we intend to write, plus why -- so runs are auditable in the log."""

    values: dict[str, Any] = dc_field(default_factory=dict)
    reasons: list[str] = dc_field(default_factory=list)

    def note(self, msg: str) -> None:
        self.reasons.append(msg)


def build_plan(
    issue: Issue,
    event: str,
    rules: list[Rule],
    project: Project,
    *,
    points_by_type: dict[str, int] | None = None,
    sprint_field: str | None = None,
    sprint_when_status: tuple[str, ...] = (),
    today: date | None = None,
) -> Plan:
    plan = Plan()

    for rule in rules:
        if rule.when.matches(issue, event):
            plan.values.update(rule.set)
            plan.note(f"rule matched -> {rule.set}")

    # Default story points by issue type, only if a rule did not set them.
    if points_by_type and issue.issue_type:
        key = next(
            (k for k in points_by_type if k.lower() == issue.issue_type.lower()),
            None,
        )
        if key and not _has_key(plan.values, "story points", "points"):
            field_name = _points_field_name(project)
            if field_name:
                plan.values[field_name] = points_by_type[key]
                plan.note(f"default {points_by_type[key]} points for {key}")

    # Auto-assign to the current iteration when entering an active status.
    if sprint_field and project.has_field(sprint_field):
        status = _lookup(plan.values, "status")
        if not sprint_when_status or (
            status and status.lower() in {s.lower() for s in sprint_when_status}
        ):
            current = project.field(sprint_field).current_iteration(today)
            if current and sprint_field not in plan.values:
                plan.values[sprint_field] = current
                plan.note(f"assigned to current sprint {current.title!r}")

    return plan


def _has_key(values: dict[str, Any], *candidates: str) -> bool:
    lowered = {k.lower() for k in values}
    return any(c in lowered for c in candidates)


def _lookup(values: dict[str, Any], name: str) -> Any:
    for k, v in values.items():
        if k.lower() == name.lower():
            return v
    return None


def _points_field_name(project: Project) -> str | None:
    for candidate in ("story points", "points", "estimate", "size"):
        if project.has_field(candidate):
            return project.field(candidate).name
    return None
