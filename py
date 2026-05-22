        image_digest = safe_str(trivy.get("Metadata", {}).get("ImageID"))

        item = PoamItem(
            poam_id=poam_id,
            status="Open",
            source_tool="Trivy",
            scan_date=scan_date,
            review_cycle=review_cycle,

            image=image,
            image_digest=image_digest,
            target=target,
            target_type=target_type,

            vulnerability_id=vuln_id,
            pkg_name=pkg_name,
            installed_version=installed_version,
            fixed_version=fixed_version,
            severity=severity,
            severity_source=severity_source,
            cvss_score=cvss_score,

            title=title,
            description=description,
            primary_url=first_url(vuln),

            weakness_description=build_weakness_description(image, target, vuln),
            deviation_type=classify_deviation_type(vuln),
            business_justification=business_justification_for_package(vuln),
            environment_context=environment_context(),
            compensating_controls=compensating_controls_text(),
            exploitability_assessment=exploitability_assessment_text(vuln),
            remediation_constraint=remediation_constraint_text(vuln),
            remediation_plan=default_remediation_plan(vuln),
            milestones=default_milestones(vuln),
            scheduled_completion_date=remediation_due_date(
                severity,
                scan_dt,
                days_critical,
                days_high,
                days_medium,
            ),
            risk_acceptance_expiration=risk_acceptance_expiration_date(scan_dt, severity),
            review_frequency=review_cycle,
            closure_criteria=closure_criteria_text(vuln),

            owner=owner,
            vendor_dependency=default_vendor_dependency(vuln),
            false_positive="No",
            operational_requirement=(
                "Yes" if "Operational Requirement" in classify_deviation_type(vuln) else "TBD"
            ),
            risk_adjustment="TBD",
            justification=business_justification_for_package(vuln),
            deviation_rationale=deviation_rationale_text(image, target, vuln),
            evidence_required=evidence_required_text(),
            comments=(
                "Generated from Trivy scan. Requires Cyber/system owner review. Validate package usage, "
                "exploitability, fixed version availability, operational requirement, and compensating controls."
            ),
        )
