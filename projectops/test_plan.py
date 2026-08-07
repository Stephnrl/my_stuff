import json

import pytest

from projectops.plan import Change, Plan, PlanRejected, build_schema, validate

FIELDS = ["Status", "Priority"]
VALUES = {
    "Status": ["Backlog", "Ready", "In Progress", "Done"],
    "Priority": ["P0", "P1", "P2", "P3"],
}


def make_plan(**over):
    base = dict(
        issue_number=42,
        reasoning="looks like a bug report",
        confidence="high",
        changes=[Change("Status", "Ready")],
    )
    return Plan(**{**base, **over})


def check(plan, **over):
    kwargs = dict(
        expected_issue=42,
        allowed_fields=FIELDS,
        allowed_values=VALUES,
        max_changes=5,
        min_confidence="low",
    )
    return validate(plan, **{**kwargs, **over})


class TestSchema:
    def test_strict_mode_requirements(self):
        """strict:true needs additionalProperties:false and all keys required."""
        schema = build_schema(FIELDS, VALUES)
        assert schema["additionalProperties"] is False
        assert set(schema["required"]) == set(schema["properties"])

        item = schema["properties"]["changes"]["items"]
        assert item["additionalProperties"] is False
        assert set(item["required"]) == set(item["properties"])

    def test_field_names_are_an_enum(self):
        schema = build_schema(FIELDS, VALUES)
        enum = schema["properties"]["changes"]["items"]["properties"]["field"]["enum"]
        assert enum == FIELDS

    def test_schema_is_json_serialisable(self):
        json.dumps(build_schema(FIELDS, VALUES))


class TestInjectionDefence:
    def test_plan_targeting_another_issue_is_rejected(self):
        """The signature of a successful prompt injection."""
        with pytest.raises(PlanRejected, match="prompt injection"):
            check(make_plan(issue_number=999))

    def test_unknown_field_rejected(self):
        plan = make_plan(changes=[Change("Assignees", "attacker")])
        with pytest.raises(PlanRejected, match="not in the allowlist"):
            check(plan)

    def test_unknown_value_rejected(self):
        plan = make_plan(changes=[Change("Status", "Shipped")])
        with pytest.raises(PlanRejected, match="not permitted"):
            check(plan)

    def test_change_flood_rejected(self):
        plan = make_plan(changes=[Change("Status", "Ready")] * 9)
        with pytest.raises(PlanRejected, match="limit is"):
            check(plan, max_changes=3)

    def test_duplicate_field_rejected(self):
        plan = make_plan(
            changes=[Change("Status", "Ready"), Change("Status", "Done")]
        )
        with pytest.raises(PlanRejected, match="more than once"):
            check(plan)

    def test_rejection_is_all_or_nothing(self):
        """One bad change invalidates the whole plan, not just that change."""
        plan = make_plan(
            changes=[Change("Status", "Ready"), Change("Priority", "P9")]
        )
        with pytest.raises(PlanRejected):
            check(plan)


class TestConfidence:
    def test_below_threshold_rejected(self):
        with pytest.raises(PlanRejected, match="below the required"):
            check(make_plan(confidence="low"), min_confidence="high")

    def test_at_threshold_accepted(self):
        assert check(make_plan(confidence="medium"), min_confidence="medium")

    def test_unknown_confidence_rejected(self):
        with pytest.raises(PlanRejected, match="unknown confidence"):
            check(make_plan(confidence="certain"))


class TestHappyPath:
    def test_valid_plan_passes(self):
        assert check(make_plan()).changes[0].field == "Status"

    def test_empty_plan_is_valid(self):
        """The model declining to classify is a correct answer, not an error."""
        assert check(make_plan(changes=[], confidence="low")).changes == []

    def test_field_matching_is_case_insensitive(self):
        assert check(make_plan(changes=[Change("status", "Ready")]))

    def test_as_values_maps_to_board_input(self):
        plan = make_plan(
            changes=[Change("Status", "Ready"), Change("Priority", "P1")]
        )
        assert plan.as_values() == {"Status": "Ready", "Priority": "P1"}

    def test_roundtrip_through_json(self):
        original = make_plan()
        assert Plan.from_dict(original.to_dict()).to_dict() == original.to_dict()

    def test_malformed_payload_rejected(self):
        with pytest.raises(PlanRejected, match="malformed"):
            Plan.from_dict({"issue_number": 1})
