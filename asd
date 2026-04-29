def load_terraform_inventory(
    root: Path,
    include_dirs: List[str] | None = None,
    ignored_dirs: Set[str] | None = None,
) -> List[Dict[str, str]]:
    inventory: List[Dict[str, str]] = []

    for tf_file in iter_tf_files(root, include_dirs, ignored_dirs):
        parsed = parse_tf_file(tf_file)
        inventory.extend(extract_resources(parsed, tf_file))
        inventory.extend(extract_modules(parsed, tf_file))

    return inventory
