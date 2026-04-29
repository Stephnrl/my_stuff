def iter_tf_files(
    root: Path,
    include_dirs: List[str] | None = None,
    ignored_dirs: Set[str] | None = None,
) -> Iterable[Path]:
    """
    Yield .tf files while skipping ignored directories.
    """
    ignored_dirs = ignored_dirs or DEFAULT_IGNORED_DIRS

    roots: List[Path]
    if include_dirs:
        roots = [root / d for d in include_dirs]
    else:
        roots = [root]

    for scan_root in roots:
        if not scan_root.exists():
            print(f"WARNING: path does not exist, skipping: {scan_root}")
            continue

        if should_skip_path(scan_root, ignored_dirs):
            continue

        for dirpath, dirnames, filenames in os.walk(scan_root):
            current_dir = Path(dirpath)

            # prevent walking into ignored dirs
            dirnames[:] = [
                d for d in dirnames
                if not should_skip_path(current_dir / d, ignored_dirs)
            ]

            for filename in filenames:
                if filename.endswith(".tf"):
                    tf_file = current_dir / filename
                    if not should_skip_path(tf_file, ignored_dirs):
                        yield tf_file
