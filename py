Add this to parse_args():

    parser.add_argument(
        "--image-digest",
        default="",
        help="Optional image digest or immutable image reference.",
    )

Then update the create_poam_items() function signature:

def create_poam_items(
    trivy: Dict[str, Any],
    image: str,
    image_digest_arg: str,
    owner: str,
    min_severity: str,
    review_cycle: str,
    days_critical: int,
    days_high: int,
    days_medium: int,
) -> List[PoamItem]:

Inside create_poam_items(), set:

    image_digest = image_digest_arg or safe_str(trivy.get("Metadata", {}).get("ImageID"))

Remove this from inside the loop if you added it there:

        image_digest = safe_str(trivy.get("Metadata", {}).get("ImageID"))

Then update the call in main():

    items = create_poam_items(
        trivy=trivy,
        image=args.image,
        image_digest_arg=args.image_digest,
        owner=args.owner,
        min_severity=args.min_severity,
        review_cycle=args.review_cycle,
        days_critical=args.days_critical,
        days_high=args.days_high,
        days_medium=args.days_medium,
    )
