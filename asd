parser.add_argument(
    "--ignore-dir",
    nargs="*",
    default=["examples", ".terraform", ".git"],
    help="Directory names to ignore. '_shared' is always ignored by pattern.",
)


ignored_dirs = set(args.ignore_dir)

items = load_terraform_inventory(
    root=root,
    include_dirs=args.include,
    ignored_dirs=ignored_dirs,
)
