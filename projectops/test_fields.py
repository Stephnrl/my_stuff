from datetime import date, timedelta

import pytest

from projectops.fields import (
    Field,
    Iteration,
    OptionNotFound,
    encode_value,
    parse_project_url,
)


class TestParseProjectUrl:
    def test_org_project(self):
        assert parse_project_url(
            "https://github.com/orgs/acme/projects/42"
        ) == ("acme", True, 42)

    def test_user_project(self):
        assert parse_project_url(
            "https://github.com/users/octocat/projects/3"
        ) == ("octocat", False, 3)

    def test_tolerates_trailing_view_path(self):
        assert parse_project_url(
            "https://github.com/orgs/acme/projects/42/views/1"
        ) == ("acme", True, 42)

    def test_rejects_repo_url(self):
        # A common mistake: Projects v2 is owner-scoped, not repo-scoped.
        with pytest.raises(ValueError, match="Cannot parse"):
            parse_project_url("https://github.com/acme/repo/projects/1")


class TestEncodeValue:
    def test_text(self):
        f = Field(id="f", name="Notes", data_type="TEXT")
        assert encode_value(f, "hello") == {"text": "hello"}

    def test_number_coerces(self):
        f = Field(id="f", name="Points", data_type="NUMBER")
        assert encode_value(f, "5") == {"number": 5.0}

    def test_date_object_and_string(self):
        f = Field(id="f", name="Start", data_type="DATE")
        assert encode_value(f, date(2026, 3, 1)) == {"date": "2026-03-01"}
        assert encode_value(f, "2026-03-01") == {"date": "2026-03-01"}

    def test_single_select_resolves_option_id(self):
        f = Field(
            id="f", name="Status", data_type="SINGLE_SELECT",
            options={"in progress": "opt_3"},
        )
        assert encode_value(f, "In Progress") == {"singleSelectOptionId": "opt_3"}

    def test_unknown_option_lists_valid_ones(self):
        f = Field(
            id="f", name="Status", data_type="SINGLE_SELECT",
            options={"done": "o1"},
        )
        with pytest.raises(OptionNotFound, match="Available"):
            encode_value(f, "Shipped")

    def test_iteration_by_object_and_title(self):
        it = Iteration("it1", "Sprint 2", date(2026, 3, 1), 14)
        f = Field(id="f", name="Sprint", data_type="ITERATION", iterations=[it])
        assert encode_value(f, it) == {"iterationId": "it1"}
        assert encode_value(f, "sprint 2") == {"iterationId": "it1"}

    def test_derived_field_types_are_rejected(self):
        f = Field(id="f", name="Labels", data_type="LABELS")
        with pytest.raises(ValueError, match="not writable"):
            encode_value(f, "bug")

    def test_none_is_rejected(self):
        f = Field(id="f", name="Notes", data_type="TEXT")
        with pytest.raises(ValueError, match="clear_field"):
            encode_value(f, None)


class TestIteration:
    def test_window_is_half_open(self):
        it = Iteration("i", "S1", date(2026, 3, 1), 14)
        assert it.end == date(2026, 3, 15)
        assert it.contains(date(2026, 3, 1))
        assert it.contains(date(2026, 3, 14))
        assert not it.contains(date(2026, 3, 15))

    def test_current_skips_completed(self):
        today = date.today()
        f = Field(
            id="f", name="Sprint", data_type="ITERATION",
            iterations=[
                Iteration("a", "Old", today - timedelta(days=1), 14, completed=True),
                Iteration("b", "Now", today - timedelta(days=1), 14),
            ],
        )
        assert f.current_iteration().title == "Now"

    def test_next_iteration_picks_earliest_future(self):
        today = date.today()
        f = Field(
            id="f", name="Sprint", data_type="ITERATION",
            iterations=[
                Iteration("c", "Later", today + timedelta(days=30), 14),
                Iteration("b", "Soon", today + timedelta(days=5), 14),
            ],
        )
        assert f.next_iteration().title == "Soon"
