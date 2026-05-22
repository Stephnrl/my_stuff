parser.add_argument(
    "--baseline-json",
    default="",
    help="Approved POA&M baseline JSON to compare against.",
)

parser.add_argument(
    "--gate-mode",
    default="warn",
    choices=[
        "off",
        "warn",
        "fail-on-new",
        "fail-on-new-critical",
        "fail-on-new-fixable",
    ],
    help="Pipeline gate behavior when current findings differ from baseline.",
)

parser.add_argument(
    "--delta-json",
    default="poam-delta.json",
    help="Output path for baseline comparison delta JSON.",
)

parser.add_argument(
    "--delta-csv",
    default="poam-delta.csv",
    help="Output path for baseline comparison delta CSV.",
)
