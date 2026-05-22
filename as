    if args.baseline_json:
        baseline_items = load_poam_items_from_json(Path(args.baseline_json))

        delta = compare_to_baseline(
            current_items=items,
            baseline_items=baseline_items,
        )

        gate = evaluate_gate(delta, args.gate_mode)

        write_delta_json(Path(args.delta_json), delta, gate)
        write_delta_csv(Path(args.delta_csv), delta)

        print(f"Generated POA&M delta JSON: {args.delta_json}")
        print(f"Generated POA&M delta CSV: {args.delta_csv}")
        print(f"Gate status: {gate['status']}")
        print(f"Gate reason: {gate['reason']}")

        if gate["status"] == "fail":
            return 2

        if gate["status"] == "warn":
            return 0
