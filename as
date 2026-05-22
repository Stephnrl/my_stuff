def load_poam_items_from_json(path: Path) -> List[Dict[str, Any]]:
    if not path or not path.exists():
        return []

    with path.open("r", encoding="utf-8") as f:
        payload = json.load(f)

    return payload.get("items", [])


def compare_to_baseline(
    current_items: List[PoamItem],
    baseline_items: List[Dict[str, Any]],
) -> Dict[str, Any]:
    baseline_by_key = {
        item.get("finding_key") or item.get("poam_id"): item
        for item in baseline_items
    }

    current_by_key = {
        item.finding_key or item.poam_id: asdict(item)
        for item in current_items
    }

    baseline_keys = set(baseline_by_key.keys())
    current_keys = set(current_by_key.keys())

    new_keys = current_keys - baseline_keys
    resolved_keys = baseline_keys - current_keys
    existing_keys = current_keys & baseline_keys

    new_findings = [current_by_key[k] for k in sorted(new_keys)]
    resolved_findings = [baseline_by_key[k] for k in sorted(resolved_keys)]
    existing_findings = [current_by_key[k] for k in sorted(existing_keys)]

    severity_changed = []

    for key in sorted(existing_keys):
        baseline = baseline_by_key[key]
        current = current_by_key[key]

        old_sev = str(baseline.get("severity", "")).upper()
        new_sev = str(current.get("severity", "")).upper()

        if old_sev and new_sev and old_sev != new_sev:
            severity_changed.append(
                {
                    "finding_key": key,
                    "vulnerability_id": current.get("vulnerability_id"),
                    "pkg_name": current.get("pkg_name"),
                    "baseline_severity": old_sev,
                    "current_severity": new_sev,
                    "current": current,
                    "baseline": baseline,
                }
            )

    return {
        "summary": {
            "new_count": len(new_findings),
            "resolved_count": len(resolved_findings),
            "existing_count": len(existing_findings),
            "severity_changed_count": len(severity_changed),
        },
        "new_findings": new_findings,
        "resolved_findings": resolved_findings,
        "existing_findings": existing_findings,
        "severity_changed": severity_changed,
    }




def evaluate_gate(delta: Dict[str, Any], gate_mode: str) -> Dict[str, Any]:
    gate_mode = gate_mode.lower()

    new_findings = delta.get("new_findings", [])
    severity_changed = delta.get("severity_changed", [])

    new_critical = [
        item for item in new_findings
        if str(item.get("severity", "")).upper() == "CRITICAL"
    ]

    new_fixable = [
        item for item in new_findings
        if item.get("fixed_version")
    ]

    severity_increased_to_critical = [
        item for item in severity_changed
        if str(item.get("current_severity", "")).upper() == "CRITICAL"
    ]

    if gate_mode == "off":
        return {
            "status": "pass",
            "reason": "Gate mode is off.",
        }

    if gate_mode == "warn":
        if new_findings or severity_changed:
            return {
                "status": "warn",
                "reason": (
                    f"Detected {len(new_findings)} new findings and "
                    f"{len(severity_changed)} severity changes."
                ),
            }

        return {
            "status": "pass",
            "reason": "No new findings or severity changes detected.",
        }

    if gate_mode == "fail-on-new-critical":
        if new_critical or severity_increased_to_critical:
            return {
                "status": "fail",
                "reason": (
                    f"Detected {len(new_critical)} new CRITICAL findings and "
                    f"{len(severity_increased_to_critical)} findings increased to CRITICAL."
                ),
            }

        return {
            "status": "pass",
            "reason": "No new CRITICAL findings detected.",
        }

    if gate_mode == "fail-on-new-fixable":
        if new_fixable:
            return {
                "status": "fail",
                "reason": f"Detected {len(new_fixable)} new findings with fixed versions available.",
            }

        return {
            "status": "pass",
            "reason": "No new fixable findings detected.",
        }

    if gate_mode == "fail-on-new":
        if new_findings or severity_changed:
            return {
                "status": "fail",
                "reason": (
                    f"Detected {len(new_findings)} new findings and "
                    f"{len(severity_changed)} severity changes."
                ),
            }

        return {
            "status": "pass",
            "reason": "No new findings or severity changes detected.",
        }

    return {
        "status": "fail",
        "reason": f"Unknown gate mode: {gate_mode}",
    }





def write_delta_json(path: Path, delta: Dict[str, Any], gate: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "gate": gate,
        "delta": delta,
    }

    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)


def write_delta_csv(path: Path, delta: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    rows = []

    for category in ["new_findings", "resolved_findings", "existing_findings"]:
        for item in delta.get(category, []):
            row = dict(item)
            row["delta_status"] = category
            rows.append(row)

    for item in delta.get("severity_changed", []):
        current = dict(item.get("current", {}))
        current["delta_status"] = "severity_changed"
        current["baseline_severity"] = item.get("baseline_severity", "")
        current["current_severity"] = item.get("current_severity", "")
        rows.append(current)

    if not rows:
        rows = [{"delta_status": "no_changes"}]

    fieldnames = sorted({key for row in rows for key in row.keys()})

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
