"""Load and validate ``projectops.yml``."""

from __future__ import annotations

from dataclasses import dataclass, field as dc_field
from pathlib import Path
from typing import Any

import yaml

from .mapping import Condition, Rule

_CONDITION_KEYS = {
    "event", "label", "any_label", "issue_type",
    "state", "state_reason", "assigned",
}


class ConfigError(ValueError):
    pass


@dataclass
class Config:
    project_url: str
    rules: list[Rule] = dc_field(default_factory=list)
    points_by_type: dict[str, int] = dc_field(default_factory=dict)
    sprint_field: str | None = None
    sprint_when_status: tuple[str, ...] = ()
    fail_on_field_error: bool = False
    agent_fields: list[str] = dc_field(default_factory=list)

    @classmethod
    def load(cls, path: str | Path) -> "Config":
        p = Path(path)
        if not p.exists():
            raise ConfigError(f"config not found: {p}")
        return cls.from_dict(yaml.safe_load(p.read_text()) or {})

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "Config":
        project = raw.get("project") or {}
        url = project.get("url")
        if not url:
            raise ConfigError("project.url is required")

        sprint = raw.get("sprint") or {}
        defaults = raw.get("defaults") or {}

        return cls(
            project_url=url,
            rules=[_parse_rule(r, i) for i, r in enumerate(raw.get("rules") or [])],
            points_by_type={
                str(k): int(v)
                for k, v in (defaults.get("points_by_type") or {}).items()
            },
            sprint_field=sprint.get("field"),
            sprint_when_status=tuple(sprint.get("only_when_status") or ()),
            fail_on_field_error=bool(raw.get("fail_on_field_error", False)),
            agent_fields=list((raw.get("agent") or {}).get("allowed_fields") or []),
        )


def _parse_rule(raw: dict[str, Any], index: int) -> Rule:
    if "when" not in raw or "set" not in raw:
        raise ConfigError(f"rules[{index}] needs both 'when' and 'set'")

    when = dict(raw["when"] or {})
    if unknown := set(when) - _CONDITION_KEYS:
        raise ConfigError(
            f"rules[{index}].when has unknown keys {sorted(unknown)}. "
            f"Valid: {sorted(_CONDITION_KEYS)}"
        )
    if "any_label" in when:
        when["any_label"] = tuple(when["any_label"])

    try:
        return Rule(when=Condition(**when), set=dict(raw["set"]))
    except (TypeError, ValueError) as exc:
        raise ConfigError(f"rules[{index}]: {exc}") from exc
