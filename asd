"""Render POA&M state to xlsx.

This is a VIEW of state/current.json, never a source of truth. Nothing in the
pipeline ever reads a workbook back.

Summary counts are written as COUNTIFS formulas rather than baked-in numbers so
the workbook stays live if someone edits a status cell by hand during review.
"""

from __future__ import annotations

import io
from typing import Any, Iterable

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

from .models import DiffResult, PoamRecord, ScanMeta, SEVERITY_ORDER, today_iso

FONT = "Arial"

HEADER_FILL = PatternFill("solid", fgColor="1F3864")
HEADER_FONT = Font(name=FONT, size=10, bold=True, color="FFFFFF")
BASE_FONT = Font(name=FONT, size=10)
BOLD = Font(name=FONT, size=10, bold=True)
TITLE_FONT = Font(name=FONT, size=14, bold=True, color="1F3864")

SEVERITY_FILL = {
    "CRITICAL": PatternFill("solid", fgColor="C00000"),
    "HIGH": PatternFill("solid", fgColor="ED7D31"),
    "MEDIUM": PatternFill("solid", fgColor="FFC000"),
    "LOW": PatternFill("solid", fgColor="A9D08E"),
    "UNKNOWN": PatternFill("solid", fgColor="D9D9D9"),
}
SEVERITY_TEXT = {
    "CRITICAL": Font(name=FONT, size=10, bold=True, color="FFFFFF"),
    "HIGH": Font(name=FONT, size=10, bold=True, color="FFFFFF"),
}
OVERDUE_FILL = PatternFill("solid", fgColor="FFC7CE")
NEW_FILL = PatternFill("solid", fgColor="FFF2CC")
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)

COLUMNS: list[tuple[str, str, int]] = [
    ("poam_id", "POA&M ID", 20),
    ("vuln_id", "Vulnerability ID", 18),
    ("severity", "Severity", 11),
    ("poam_status", "Status", 24),
    ("pkg_name", "Package", 24),
    ("installed_version", "Installed Version", 18),
    ("fixed_version", "Fixed Version", 18),
    ("target", "Location", 34),
    ("pkg_type", "Package Type", 14),
    ("cvss_score", "CVSS v3", 9),
    ("first_detected", "First Detected", 14),
    ("last_detected", "Last Detected", 14),
    ("scheduled_completion_date", "Scheduled Completion", 20),
    ("closed_date", "Closed Date", 13),
    ("reopened_count", "Reopened", 10),
    ("deviation_type", "Deviation Type", 22),
    ("deviation_ref", "Deviation Ref", 16),
    ("deviation_approved_by", "Approved By", 18),
    ("deviation_expires", "Deviation Expires", 18),
    ("deviation_justification", "Justification / Remediation Plan", 46),
    ("title", "Description", 52),
    ("primary_url", "Reference", 40),
    ("purl", "Package URL", 40),
    ("last_seen_tag", "Last Seen Tag", 22),
]


def _style_header(ws, row: int, width_map: list[tuple[str, str, int]]) -> None:
    for idx, (_, header, width) in enumerate(width_map, start=1):
        cell = ws.cell(row=row, column=idx, value=header)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(vertical="center", wrap_text=True)
        cell.border = BORDER
        ws.column_dimensions[get_column_letter(idx)].width = width
    ws.row_dimensions[row].height = 30


def _write_records(ws, records: list[PoamRecord], start_row: int, new_keys: set[str]) -> int:
    row = start_row
    today = today_iso()
    for rec in records:
        for idx, (attr, _, _) in enumerate(COLUMNS, start=1):
            value = getattr(rec, attr, "")
            if attr == "reopened_count" and not value:
                value = ""
            cell = ws.cell(row=row, column=idx, value=value)
            cell.font = BASE_FONT
            cell.border = BORDER
            cell.alignment = Alignment(vertical="top", wrap_text=attr in {"title", "deviation_justification", "target", "purl"})
            if attr == "severity":
                cell.fill = SEVERITY_FILL.get(rec.severity, SEVERITY_FILL["UNKNOWN"])
                cell.font = SEVERITY_TEXT.get(rec.severity, BOLD)
                cell.alignment = Alignment(horizontal="center", vertical="top")
            if attr == "cvss_score" and value:
                cell.number_format = "0.0"
        if rec.is_overdue(today):
            ws.cell(row=row, column=13).fill = OVERDUE_FILL
            ws.cell(row=row, column=13).font = Font(name=FONT, size=10, bold=True, color="9C0006")
        if rec.finding_key in new_keys:
            ws.cell(row=row, column=1).fill = NEW_FILL
        row += 1
    return row


def _sheet_poam(wb: Workbook, records: list[PoamRecord], new_keys: set[str], title: str) -> None:
    ws = wb.create_sheet(title)
    _style_header(ws, 1, COLUMNS)
    end = _write_records(ws, records, 2, new_keys)
    ws.freeze_panes = "E2"
    if end > 2:
        ws.auto_filter.ref = f"A1:{get_column_letter(len(COLUMNS))}{end - 1}"
    ws.sheet_view.showGridLines = False


def _sheet_summary(
    wb: Workbook,
    meta: ScanMeta,
    diff: DiffResult,
    decision: Any,
    open_rows: int,
) -> None:
    ws = wb.create_sheet("Summary", 0)
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 34
    ws.column_dimensions["B"].width = 58
    ws.column_dimensions["C"].width = 14
    ws.column_dimensions["D"].width = 14

    ws["A1"] = "Plan of Action & Milestones"
    ws["A1"].font = TITLE_FONT
    ws["A2"] = meta.component_id
    ws["A2"].font = Font(name=FONT, size=11, bold=True)

    rows: list[tuple[str, Any]] = [
        ("Generated (UTC)", meta.scan_timestamp),
        ("Scan Type", "Initial" if meta.is_initial_scan else "Recurring"),
        ("Image Reference", meta.image_ref),
        ("Image Digest", meta.image_digest),
        ("Image Tag", meta.image_tag),
        ("Gate Result", getattr(decision, "result", "unknown").upper()),
        ("", ""),
        ("Trivy Version", meta.trivy_version),
        ("Vulnerability DB Updated", meta.vuln_db_updated_at),
        ("Vulnerability DB Next Update", meta.vuln_db_next_update),
        ("Policy Profile", meta.policy_profile),
        ("Policy Fingerprint", meta.policy_sha),
        ("Gate Version", meta.gate_version),
        ("Source Repository", meta.repository),
        ("Workflow Run", meta.run_url),
        ("Triggered By", meta.actor),
        ("Commit", meta.git_sha),
    ]
    r = 4
    for label, value in rows:
        if label:
            ws.cell(row=r, column=1, value=label).font = BOLD
            c = ws.cell(row=r, column=2, value=value)
            c.font = BASE_FONT
            c.alignment = Alignment(wrap_text=False)
        r += 1

    r += 1
    ws.cell(row=r, column=1, value="This Scan").font = Font(name=FONT, size=12, bold=True, color="1F3864")
    r += 1
    counts = diff.counts()
    for label, key in [
        ("New findings", "new"),
        ("Closed this scan", "closed"),
        ("Reopened (regression)", "reopened"),
        ("Carried forward", "persisting"),
        ("Severity reclassified", "severity_drift"),
    ]:
        ws.cell(row=r, column=1, value=label).font = BASE_FONT
        ws.cell(row=r, column=2, value=counts.get(key, 0)).font = BOLD
        r += 1

    r += 1
    ws.cell(row=r, column=1, value="Open Items by Severity").font = Font(
        name=FONT, size=12, bold=True, color="1F3864"
    )
    r += 1
    header_row = r
    for i, label in enumerate(["Severity", "Total Open", "Counting Toward Gate"]):
        c = ws.cell(row=header_row, column=i + 1, value=label)
        c.fill = HEADER_FILL
        c.font = HEADER_FONT
        c.border = BORDER
    r += 1

    # COUNTIFS against the live POA&M sheet keeps this honest if a reviewer
    # edits a status cell during assessment.
    last = max(open_rows, 2)
    for sev in SEVERITY_ORDER:
        ws.cell(row=r, column=1, value=sev).font = BOLD
        ws.cell(row=r, column=1).fill = SEVERITY_FILL.get(sev, SEVERITY_FILL["UNKNOWN"])
        ws.cell(row=r, column=1).font = SEVERITY_TEXT.get(sev, BOLD)
        ws.cell(row=r, column=2, value=f'=COUNTIFS(\'POA&M Items\'!$C$2:$C${last},A{r})').font = BASE_FONT
        ws.cell(
            row=r, column=3,
            value=f'=COUNTIFS(\'POA&M Items\'!$C$2:$C${last},A{r},\'POA&M Items\'!$P$2:$P${last},"")',
        ).font = BASE_FONT
        for col in (1, 2, 3):
            ws.cell(row=r, column=col).border = BORDER
        r += 1

    ws.cell(row=r, column=1, value="TOTAL").font = BOLD
    ws.cell(row=r, column=2, value=f"=SUM(B{r - len(SEVERITY_ORDER)}:B{r - 1})").font = BOLD
    ws.cell(row=r, column=3, value=f"=SUM(C{r - len(SEVERITY_ORDER)}:C{r - 1})").font = BOLD

    r += 2
    ws.cell(row=r, column=1, value="Column P is Deviation Type; blank means the item counts toward the gate.").font = Font(
        name=FONT, size=9, italic=True, color="808080"
    )
    r += 1
    ws.cell(
        row=r, column=1,
        value="Counts are formulas over the POA&M Items sheet and recalculate on open.",
    ).font = Font(name=FONT, size=9, italic=True, color="808080")

    if getattr(decision, "bypass_used", False):
        r += 2
        ws.cell(row=r, column=1, value="EMERGENCY BYPASS USED").font = Font(
            name=FONT, size=12, bold=True, color="C00000"
        )
        r += 1
        for label, value in [
            ("Approved by", getattr(decision, "bypass_actor", "")),
            ("Justification", getattr(decision, "bypass_reason", "")),
        ]:
            ws.cell(row=r, column=1, value=label).font = BOLD
            ws.cell(row=r, column=2, value=value).font = BASE_FONT
            r += 1


def _sheet_violations(wb: Workbook, decision: Any) -> None:
    violations = getattr(decision, "violations", []) or []
    if not violations:
        return
    ws = wb.create_sheet("Gate Violations")
    ws.sheet_view.showGridLines = False
    headers = [
        ("rule", "Rule", 18),
        ("poam_id", "POA&M ID", 20),
        ("vuln_id", "Vulnerability ID", 18),
        ("severity", "Severity", 11),
        ("pkg_name", "Package", 24),
        ("installed_version", "Installed", 16),
        ("fixed_version", "Fixed In", 16),
        ("scheduled_completion_date", "Due", 14),
        ("target", "Location", 40),
    ]
    _style_header(ws, 1, headers)
    for i, v in enumerate(violations, start=2):
        for idx, (key, _, _) in enumerate(headers, start=1):
            cell = ws.cell(row=i, column=idx, value=v.get(key, ""))
            cell.font = BASE_FONT
            cell.border = BORDER
            if key == "severity":
                cell.fill = SEVERITY_FILL.get(v.get("severity"), SEVERITY_FILL["UNKNOWN"])
                cell.font = SEVERITY_TEXT.get(v.get("severity"), BOLD)
    ws.freeze_panes = "A2"


def _sheet_deviations(wb: Workbook, records: list[PoamRecord]) -> None:
    active = [r for r in records if r.has_active_deviation and r.is_open]
    ws = wb.create_sheet("Deviations")
    ws.sheet_view.showGridLines = False
    headers = [
        ("poam_id", "POA&M ID", 20),
        ("vuln_id", "Vulnerability ID", 18),
        ("severity", "Severity", 11),
        ("deviation_type", "Deviation Type", 22),
        ("deviation_ref", "Reference", 16),
        ("deviation_approved_by", "Approved By", 20),
        ("deviation_expires", "Expires", 14),
        ("deviation_justification", "Justification", 70),
    ]
    _style_header(ws, 1, headers)
    for i, rec in enumerate(active, start=2):
        for idx, (attr, _, _) in enumerate(headers, start=1):
            cell = ws.cell(row=i, column=idx, value=getattr(rec, attr, ""))
            cell.font = BASE_FONT
            cell.border = BORDER
            cell.alignment = Alignment(vertical="top", wrap_text=attr == "deviation_justification")
    if not active:
        ws.cell(row=2, column=1, value="No active deviations.").font = Font(
            name=FONT, size=10, italic=True, color="808080"
        )
    ws.freeze_panes = "A2"


def _sheet_change_log(wb: Workbook, diff: DiffResult) -> None:
    ws = wb.create_sheet("Change Log")
    ws.sheet_view.showGridLines = False
    headers = [
        ("change", "Change", 16),
        ("poam_id", "POA&M ID", 20),
        ("vuln_id", "Vulnerability ID", 18),
        ("severity", "Severity", 11),
        ("pkg_name", "Package", 24),
        ("detail", "Detail", 60),
    ]
    _style_header(ws, 1, headers)
    row = 2
    buckets = [("NEW", diff.new), ("CLOSED", diff.closed), ("REOPENED", diff.reopened)]
    for label, recs in buckets:
        for rec in recs:
            detail = {
                "NEW": f"First detected {rec.first_detected}; due {rec.scheduled_completion_date}",
                "CLOSED": f"No longer reported as of {rec.closed_date}",
                "REOPENED": f"Regression #{rec.reopened_count}; due {rec.scheduled_completion_date}",
            }[label]
            for idx, value in enumerate(
                [label, rec.poam_id, rec.vuln_id, rec.severity, rec.pkg_name, detail], start=1
            ):
                cell = ws.cell(row=row, column=idx, value=value)
                cell.font = BASE_FONT
                cell.border = BORDER
            row += 1
    for drift in diff.severity_drift:
        arrow = "escalated" if drift["escalation"] else "downgraded"
        for idx, value in enumerate(
            [
                "RECLASSIFIED",
                drift["poam_id"],
                drift["vuln_id"],
                drift["to"],
                drift["pkg_name"],
                f"Severity {arrow}: {drift['from']} -> {drift['to']}",
            ],
            start=1,
        ):
            cell = ws.cell(row=row, column=idx, value=value)
            cell.font = BASE_FONT
            cell.border = BORDER
        row += 1
    if row == 2:
        ws.cell(row=2, column=1, value="No changes since the previous scan.").font = Font(
            name=FONT, size=10, italic=True, color="808080"
        )
    ws.freeze_panes = "A2"


def render_poam(
    records: list[PoamRecord],
    diff: DiffResult,
    meta: ScanMeta,
    decision: Any,
) -> bytes:
    """Build the workbook and return it as bytes."""
    wb = Workbook()
    wb.remove(wb.active)

    new_keys = {r.finding_key for r in diff.new}
    open_records = [r for r in records if r.is_open]
    closed_records = [r for r in records if not r.is_open]

    _sheet_poam(wb, open_records, new_keys, "POA&M Items")
    _sheet_poam(wb, closed_records, set(), "Closed Items")
    _sheet_change_log(wb, diff)
    _sheet_deviations(wb, records)
    _sheet_violations(wb, decision)
    _sheet_summary(wb, meta, diff, decision, open_rows=len(open_records) + 1)

    wb.properties.title = f"POA&M - {meta.component_id}"
    wb.properties.creator = "container-security-gate"

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()
