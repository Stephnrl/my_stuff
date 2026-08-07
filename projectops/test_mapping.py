from datetime import date, timedelta

import pytest

from projectops.board import Issue
from projectops.config import Config, ConfigError
from projectops.fields import Field, Iteration, Project
from projectops.mapping import Condition, Rule, build_plan


def make_issue(**over):
    base = dict(
        node_id="I_1", number=1, title="t", body="", state="OPEN", state_reason=None,
        issue_type=None, labels=[], assignees=[], parent_number=None,
    )
    return Issue(**{**base, **over})


def make_project(*, with_sprint=True, today=None):
    today = today or date.today()
    fields = {
        "status": Field(
            id="F_status", name="Status", data_type="SINGLE_SELECT",
            options={"backlog": "o1", "ready": "o2", "in progress": "o3",
                     "done": "o4", "cancelled": "o5"},
        ),
        "story points": Field(
            id="F_points", name="Story Points", data_type="NUMBER"
        ),
    }
    if with_sprint:
        fields["sprint"] = Field(
            id="F_sprint", name="Sprint", data_type="ITERATION",
            iterations=[
                Iteration("it0", "Sprint 1", today - timedelta(days=20), 14, True),
                Iteration("it1", "Sprint 2", today - timedelta(days=3), 14),
                Iteration("it2", "Sprint 3", today + timedelta(days=11), 14),
            ],
        )
    return Project(
        id="P_1", number=1, title="Board", url="u",
        login="acme", is_org=True, fields=fields,
    )


class TestCondition:
    def test_event_match(self):
        assert Condition(event="opened").matches(make_issue(), "opened")
        assert not Condition(event="opened").matches(make_issue(), "closed")

    def test_label_is_case_insensitive(self):
        issue = make_issue(labels=["Ready"])
        assert Condition(label="ready").matches(issue, "labeled")

    def test_any_label(self):
        issue = make_issue(labels=["sev1"])
        assert Condition(any_label=("incident", "sev1")).matches(issue, "labeled")
        assert not Condition(any_label=("incident",)).matches(issue, "labeled")

    def test_assigned_flag(self):
        assert Condition(assigned=True).matches(make_issue(assignees=["a"]), "x")
        assert Condition(assigned=False).matches(make_issue(), "x")

    def test_state_reason_normalises_underscores(self):
        issue = make_issue(state="CLOSED", state_reason="NOT_PLANNED")
        assert Condition(state_reason="not planned").matches(issue, "closed")

    def test_all_conditions_must_match(self):
        cond = Condition(event="closed", label="bug")
        assert not cond.matches(make_issue(labels=["bug"]), "opened")
        assert cond.matches(make_issue(labels=["bug"]), "closed")


class TestPlan:
    def test_last_matching_rule_wins(self):
        rules = [
            Rule(Condition(event="opened"), {"Status": "Backlog"}),
            Rule(Condition(label="ready"), {"Status": "Ready"}),
        ]
        plan = build_plan(
            make_issue(labels=["ready"]), "opened", rules, make_project()
        )
        assert plan.values["Status"] == "Ready"

    def test_no_match_yields_empty_plan(self):
        rules = [Rule(Condition(event="closed"), {"Status": "Done"})]
        assert not build_plan(make_issue(), "opened", rules, make_project()).values

    def test_default_points_by_issue_type(self):
        plan = build_plan(
            make_issue(issue_type="Feature"), "opened",
            [Rule(Condition(event="opened"), {"Status": "Backlog"})],
            make_project(), points_by_type={"Feature": 8},
        )
        assert plan.values["Story Points"] == 8

    def test_explicit_points_beat_defaults(self):
        plan = build_plan(
            make_issue(issue_type="Feature"), "opened",
            [Rule(Condition(event="opened"), {"Story Points": 2})],
            make_project(), points_by_type={"Feature": 8},
        )
        assert plan.values["Story Points"] == 2

    def test_sprint_assigned_only_for_allowed_status(self):
        rules = [Rule(Condition(event="opened"), {"Status": "Backlog"})]
        plan = build_plan(
            make_issue(), "opened", rules, make_project(),
            sprint_field="Sprint", sprint_when_status=("Ready", "In Progress"),
        )
        assert "Sprint" not in plan.values

    def test_sprint_assigned_when_status_allows(self):
        rules = [Rule(Condition(event="assigned"), {"Status": "In Progress"})]
        plan = build_plan(
            make_issue(assignees=["a"]), "assigned", rules, make_project(),
            sprint_field="Sprint", sprint_when_status=("Ready", "In Progress"),
        )
        assert plan.values["Sprint"].title == "Sprint 2"

    def test_completed_iterations_are_never_current(self):
        project = make_project()
        current = project.field("Sprint").current_iteration()
        assert current is not None and not current.completed

    def test_reasons_are_recorded(self):
        plan = build_plan(
            make_issue(), "opened",
            [Rule(Condition(event="opened"), {"Status": "Backlog"})],
            make_project(),
        )
        assert plan.reasons


class TestConfig:
    def test_requires_project_url(self):
        with pytest.raises(ConfigError, match="project.url"):
            Config.from_dict({})

    def test_rejects_unknown_condition_key(self):
        raw = {
            "project": {"url": "https://github.com/orgs/a/projects/1"},
            "rules": [{"when": {"labl": "x"}, "set": {"Status": "Done"}}],
        }
        with pytest.raises(ConfigError, match="unknown keys"):
            Config.from_dict(raw)

    def test_rejects_rule_without_set(self):
        raw = {
            "project": {"url": "https://github.com/orgs/a/projects/1"},
            "rules": [{"when": {"event": "opened"}}],
        }
        with pytest.raises(ConfigError):
            Config.from_dict(raw)

    def test_parses_full_config(self):
        cfg = Config.from_dict({
            "project": {"url": "https://github.com/orgs/a/projects/7"},
            "rules": [{"when": {"any_label": ["sev1"]}, "set": {"Priority": "P0"}}],
            "defaults": {"points_by_type": {"Story": 3}},
            "sprint": {"field": "Sprint", "only_when_status": ["Ready"]},
        })
        assert cfg.points_by_type == {"Story": 3}
        assert cfg.sprint_field == "Sprint"
        assert cfg.rules[0].when.any_label == ("sev1",)
