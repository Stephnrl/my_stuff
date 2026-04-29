#!/usr/bin/env python3

"""
Generate an AWS architecture diagram from Terraform .tf files.

Features:
- Supports root/monolithic Terraform repos.
- Supports repo subdirectories such as eks/, eks-pod-identity/, eks-addons/.
- Ignores directories containing "_shared".
- Parses Terraform HCL2 using python-hcl2.
- Creates a Mingrammer Diagrams output file.

Usage examples:

  python tf_to_diagram.py ./my-terraform-repo

  python tf_to_diagram.py ./my-terraform-repo \
    --include eks eks-pod-identity eks-addons \
    --output eks-architecture

  python tf_to_diagram.py ./my-terraform-repo \
    --format svg \
    --direction TB
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

import hcl2

from diagrams import Cluster, Diagram
from diagrams.aws.compute import EC2, EKS, Lambda
from diagrams.aws.database import RDS, Dynamodb, ElastiCache
from diagrams.aws.integration import SQS, SNS, Eventbridge
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import ALB, ELB, NLB, Route53, VPC, PrivateSubnet, PublicSubnet, NATGateway, InternetGateway
from diagrams.aws.security import IAM, KMS, SecretsManager
from diagrams.aws.storage import S3, EFS
from diagrams.aws.devtools import Codebuild, Codepipeline
from diagrams.aws.general import General


# Terraform AWS resource type -> Diagrams node class
AWS_RESOURCE_MAP = {
    # Compute
    "aws_instance": EC2,
    "aws_launch_template": EC2,
    "aws_autoscaling_group": EC2,
    "aws_eks_cluster": EKS,
    "aws_eks_node_group": EKS,
    "aws_lambda_function": Lambda,

    # Networking
    "aws_vpc": VPC,
    "aws_subnet": PrivateSubnet,
    "aws_internet_gateway": InternetGateway,
    "aws_nat_gateway": NATGateway,
    "aws_route53_zone": Route53,
    "aws_route53_record": Route53,
    "aws_lb": ALB,
    "aws_alb": ALB,
    "aws_elb": ELB,
    "aws_lb_listener": ALB,
    "aws_lb_target_group": ALB,
    "aws_security_group": General,
    "aws_security_group_rule": General,

    # Storage
    "aws_s3_bucket": S3,
    "aws_efs_file_system": EFS,

    # Database
    "aws_db_instance": RDS,
    "aws_rds_cluster": RDS,
    "aws_rds_cluster_instance": RDS,
    "aws_dynamodb_table": Dynamodb,
    "aws_elasticache_cluster": ElastiCache,
    "aws_elasticache_replication_group": ElastiCache,

    # IAM / Security
    "aws_iam_role": IAM,
    "aws_iam_policy": IAM,
    "aws_iam_policy_attachment": IAM,
    "aws_iam_role_policy": IAM,
    "aws_iam_role_policy_attachment": IAM,
    "aws_kms_key": KMS,
    "aws_secretsmanager_secret": SecretsManager,

    # Messaging / Events
    "aws_sqs_queue": SQS,
    "aws_sns_topic": SNS,
    "aws_cloudwatch_event_rule": Eventbridge,
    "aws_cloudwatch_log_group": Cloudwatch,

    # DevOps
    "aws_codebuild_project": Codebuild,
    "aws_codepipeline": Codepipeline,
}


# Module name/source keyword -> Diagrams node class
MODULE_HINT_MAP = {
    "eks": EKS,
    "pod-identity": IAM,
    "pod_identity": IAM,
    "addons": EKS,
    "vpc": VPC,
    "network": VPC,
    "s3": S3,
    "bucket": S3,
    "rds": RDS,
    "aurora": RDS,
    "lambda": Lambda,
    "iam": IAM,
    "kms": KMS,
    "secrets": SecretsManager,
}


def should_skip_path(path: Path) -> bool:
    """
    Skip any directory or file path containing '_shared'.
    """
    return any("_shared" in part for part in path.parts)


def iter_tf_files(root: Path, include_dirs: List[str] | None = None) -> Iterable[Path]:
    """
    Yield .tf files.

    If include_dirs is provided, only scan those child directories under root.
    Otherwise, scan the entire root recursively.
    """
    roots: List[Path]

    if include_dirs:
        roots = [root / d for d in include_dirs]
    else:
        roots = [root]

    for scan_root in roots:
        if not scan_root.exists():
            print(f"WARNING: path does not exist, skipping: {scan_root}")
            continue

        if should_skip_path(scan_root):
            continue

        for dirpath, dirnames, filenames in os.walk(scan_root):
            current_dir = Path(dirpath)

            # Prevent walking into ignored dirs
            dirnames[:] = [
                d for d in dirnames
                if "_shared" not in d and not should_skip_path(current_dir / d)
            ]

            for filename in filenames:
                if filename.endswith(".tf"):
                    tf_file = current_dir / filename
                    if not should_skip_path(tf_file):
                        yield tf_file


def parse_tf_file(tf_file: Path) -> Dict[str, Any]:
    """
    Parse one Terraform file.
    """
    try:
        with tf_file.open("r", encoding="utf-8") as f:
            return hcl2.load(f)
    except Exception as exc:
        print(f"WARNING: failed to parse {tf_file}: {exc}")
        return {}


def extract_resources(parsed: Dict[str, Any], tf_file: Path) -> List[Dict[str, str]]:
    """
    Extract Terraform resource blocks.

    python-hcl2 commonly returns:
      {"resource": [{"aws_s3_bucket": {"name": {...}}}]}
    """
    results: List[Dict[str, str]] = []

    for resource_block in parsed.get("resource", []):
        if not isinstance(resource_block, dict):
            continue

        for resource_type, resources in resource_block.items():
            if not isinstance(resources, dict):
                continue

            for resource_name in resources.keys():
                results.append({
                    "kind": "resource",
                    "type": resource_type,
                    "name": resource_name,
                    "file": str(tf_file),
                    "directory": str(tf_file.parent),
                })

    return results


def extract_modules(parsed: Dict[str, Any], tf_file: Path) -> List[Dict[str, str]]:
    """
    Extract Terraform module blocks.

    python-hcl2 commonly returns:
      {"module": [{"eks": {"source": "...", ...}}]}
    """
    results: List[Dict[str, str]] = []

    for module_block in parsed.get("module", []):
        if not isinstance(module_block, dict):
            continue

        for module_name, module_body in module_block.items():
            source = ""

            if isinstance(module_body, dict):
                raw_source = module_body.get("source", "")
                if isinstance(raw_source, str):
                    source = raw_source

            results.append({
                "kind": "module",
                "type": "module",
                "name": module_name,
                "source": source,
                "file": str(tf_file),
                "directory": str(tf_file.parent),
            })

    return results


def load_terraform_inventory(root: Path, include_dirs: List[str] | None = None) -> List[Dict[str, str]]:
    """
    Parse all Terraform files and return resources/modules.
    """
    inventory: List[Dict[str, str]] = []

    for tf_file in iter_tf_files(root, include_dirs):
        parsed = parse_tf_file(tf_file)
        inventory.extend(extract_resources(parsed, tf_file))
        inventory.extend(extract_modules(parsed, tf_file))

    return inventory


def node_class_for_item(item: Dict[str, str]):
    """
    Choose a Diagrams node class for a Terraform resource or module.
    """
    if item["kind"] == "resource":
        return AWS_RESOURCE_MAP.get(item["type"], General)

    module_name = item.get("name", "").lower()
    module_source = item.get("source", "").lower()
    combined = f"{module_name} {module_source}"

    for hint, node_cls in MODULE_HINT_MAP.items():
        if hint in combined:
            return node_cls

    return General


def label_for_item(item: Dict[str, str]) -> str:
    """
    Human-friendly label for the diagram node.
    """
    if item["kind"] == "resource":
        return f'{item["type"]}.{item["name"]}'

    source = item.get("source", "")
    if source:
        return f'module.{item["name"]}\n{source}'
    return f'module.{item["name"]}'


def group_by_directory(items: List[Dict[str, str]], root: Path) -> Dict[str, List[Dict[str, str]]]:
    """
    Group resources/modules by relative Terraform directory.
    """
    grouped: Dict[str, List[Dict[str, str]]] = {}

    for item in items:
        directory = Path(item["directory"])
        try:
            rel_dir = str(directory.relative_to(root))
        except ValueError:
            rel_dir = str(directory)

        if rel_dir == ".":
            rel_dir = "root"

        grouped.setdefault(rel_dir, []).append(item)

    return grouped


def generate_diagram(
    root: Path,
    items: List[Dict[str, str]],
    output: str,
    outformat: str,
    direction: str,
) -> None:
    """
    Generate a Diagrams architecture diagram.
    """
    grouped = group_by_directory(items, root)

    graph_attr = {
        "fontsize": "18",
        "pad": "0.5",
        "splines": "ortho",
    }

    with Diagram(
        name=output,
        filename=output,
        outformat=outformat,
        show=False,
        direction=direction,
        graph_attr=graph_attr,
    ):
        for directory, dir_items in sorted(grouped.items()):
            with Cluster(directory):
                previous_node = None

                for item in sorted(dir_items, key=lambda x: (x["kind"], x["type"], x["name"])):
                    node_cls = node_class_for_item(item)
                    node = node_cls(label_for_item(item))

                    # Basic visual grouping chain.
                    # This does not infer true Terraform dependencies yet.
                    if previous_node:
                        previous_node - node

                    previous_node = node


def print_summary(items: List[Dict[str, str]]) -> None:
    resources = [i for i in items if i["kind"] == "resource"]
    modules = [i for i in items if i["kind"] == "module"]

    print()
    print("Terraform scan summary")
    print("----------------------")
    print(f"Resources found: {len(resources)}")
    print(f"Modules found:   {len(modules)}")
    print()

    by_type: Dict[str, int] = {}
    for item in resources:
        by_type[item["type"]] = by_type.get(item["type"], 0) + 1

    if by_type:
        print("Resource types:")
        for resource_type, count in sorted(by_type.items()):
            print(f"  {resource_type}: {count}")

    if modules:
        print()
        print("Modules:")
        for module in modules:
            source = module.get("source", "")
            if source:
                print(f'  module.{module["name"]} -> {source}')
            else:
                print(f'  module.{module["name"]}')


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate an AWS architecture diagram from Terraform .tf files."
    )

    parser.add_argument(
        "repo",
        help="Path to the Terraform repo root.",
    )

    parser.add_argument(
        "--include",
        nargs="*",
        default=None,
        help=(
            "Optional list of subdirectories to scan. "
            "Example: --include eks eks-pod-identity eks-addons"
        ),
    )

    parser.add_argument(
        "--output",
        default="terraform-aws-architecture",
        help="Output filename without extension.",
    )

    parser.add_argument(
        "--format",
        default="png",
        choices=["png", "svg", "pdf", "jpg"],
        help="Diagram output format.",
    )

    parser.add_argument(
        "--direction",
        default="LR",
        choices=["LR", "RL", "TB", "BT"],
        help="Diagram direction: LR, RL, TB, or BT.",
    )

    args = parser.parse_args()

    root = Path(args.repo).resolve()

    items = load_terraform_inventory(
        root=root,
        include_dirs=args.include,
    )

    if not items:
        print("No Terraform resources or modules found.")
        return

    print_summary(items)

    generate_diagram(
        root=root,
        items=items,
        output=args.output,
        outformat=args.format,
        direction=args.direction,
    )

    print()
    print(f"Diagram written to: {args.output}.{args.format}")


if __name__ == "__main__":
    main()
