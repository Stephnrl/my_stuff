#!/usr/bin/env python3

"""
Terraform to AWS Diagrams generator with raw, logical, profile, and flow views.

This script is designed for Terraform repos that may be:
- monolithic root Terraform repos
- module repos with subdirectories such as aws_config/, cw_oam_sink/, cw_oam_link/
- multi-mode repos where files such as security.tf and member.tf represent different deployment paths

It uses:
- python-hcl2 to parse Terraform files
- diagrams.mingrammer.com to render architecture diagrams
- optional YAML rules to map directories/files to higher-level architecture concepts

Install:
  pip install diagrams python-hcl2 pyyaml

Also install Graphviz:
  macOS:        brew install graphviz
  Ubuntu/Debian: sudo apt-get install -y graphviz
  RHEL/Fedora:   sudo dnf install -y graphviz

Examples:
  python tf_to_diagram_logical.py ./security-repo --view raw --format svg

  python tf_to_diagram_logical.py ./security-repo \
    --rules diagram-rules.yaml \
    --view logical \
    --format svg \
    --output security-logical

  python tf_to_diagram_logical.py ./security-repo \
    --rules diagram-rules.yaml \
    --view profile \
    --profile security \
    --format svg \
    --output security-account

  python tf_to_diagram_logical.py ./security-repo \
    --rules diagram-rules.yaml \
    --view profile \
    --profile member \
    --format svg \
    --output member-account

  python tf_to_diagram_logical.py ./security-repo \
    --rules diagram-rules.yaml \
    --view flow \
    --format svg \
    --output security-flow
"""

from __future__ import annotations

import argparse
import os
import re
import textwrap
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import hcl2
import yaml

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.analytics import Cloudwatch
from diagrams.aws.compute import EC2, EKS, Lambda
from diagrams.aws.database import Dynamodb, ElastiCache, RDS
from diagrams.aws.devtools import Codebuild, Codepipeline
from diagrams.aws.general import General
from diagrams.aws.integration import Eventbridge, SNS, SQS
from diagrams.aws.management import Config, Organizations
from diagrams.aws.network import ALB, ELB, InternetGateway, NATGateway, NLB, PrivateSubnet, PublicSubnet, Route53, VPC
from diagrams.aws.security import IAM, KMS, SecretsManager, SecurityHub
from diagrams.aws.storage import EFS, S3


DEFAULT_IGNORED_DIRS: Set[str] = {
    "examples",
    ".terraform",
    ".git",
}

ALWAYS_IGNORE_PARTIALS: Set[str] = {
    "_shared",
}


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
    "aws_securityhub_account": SecurityHub,
    "aws_securityhub_organization_admin_account": SecurityHub,
    "aws_securityhub_standards_subscription": SecurityHub,

    # AWS Config / Organizations
    "aws_config_configuration_recorder": Config,
    "aws_config_delivery_channel": Config,
    "aws_config_config_rule": Config,
    "aws_config_aggregate_authorization": Config,
    "aws_config_configuration_aggregator": Config,
    "aws_organizations_organization": Organizations,
    "aws_organizations_account": Organizations,
    "aws_organizations_delegated_administrator": Organizations,

    # CloudWatch OAM resources
    "aws_oam_sink": Cloudwatch,
    "aws_oam_sink_policy": Cloudwatch,
    "aws_oam_link": Cloudwatch,

    # Messaging / Events
    "aws_sqs_queue": SQS,
    "aws_sns_topic": SNS,
    "aws_cloudwatch_event_rule": Eventbridge,
    "aws_cloudwatch_log_group": Cloudwatch,

    # DevOps
    "aws_codebuild_project": Codebuild,
    "aws_codepipeline": Codepipeline,
}


LOGICAL_TYPE_ICON_MAP = {
    "observability": Cloudwatch,
    "compliance": Config,
    "security": SecurityHub,
    "iam": IAM,
    "network": VPC,
    "compute": EC2,
    "storage": S3,
    "database": RDS,
    "organization": Organizations,
    "general": General,
}


@dataclass
class TfItem:
    id: str
    kind: str  # resource, module
    name: str
    directory: str
    file: str
    tf_type: Optional[str] = None
    source: Optional[str] = None
    body: Dict[str, Any] = field(default_factory=dict)
    account_scope: Optional[str] = None
    deployment_modes: List[str] = field(default_factory=list)
    logical_group: Optional[str] = None
    tags: List[str] = field(default_factory=list)
    references: List[str] = field(default_factory=list)


@dataclass
class LogicalComponent:
    name: str
    type: str = "general"
    directories: List[str] = field(default_factory=list)
    files: List[str] = field(default_factory=list)
    account_scope: Optional[str] = None
    deployment_modes: List[str] = field(default_factory=list)
    connects_to: List[str] = field(default_factory=list)
    description: Optional[str] = None
    matched_items: List[TfItem] = field(default_factory=list)


@dataclass
class DiagramRules:
    ignored_dirs: Set[str] = field(default_factory=lambda: set(DEFAULT_IGNORED_DIRS))
    file_roles: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    directory_roles: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    logical_components: List[LogicalComponent] = field(default_factory=list)
    flows: List[Dict[str, Any]] = field(default_factory=list)
    profiles: Dict[str, Dict[str, Any]] = field(default_factory=dict)


def normalize_path_text(value: str) -> str:
    return value.replace("\\", "/").strip("/").lower()


def wrap_label(text: str, width: int = 18) -> str:
    pieces = []
    for line in text.split("\n"):
        wrapped = textwrap.wrap(line, width=width) or [line]
        pieces.extend(wrapped)
    return "\n".join(pieces)


def should_skip_path(path: Path, ignored_dirs: Set[str]) -> bool:
    for part in path.parts:
        if part in ignored_dirs:
            return True
        for partial in ALWAYS_IGNORE_PARTIALS:
            if partial in part:
                return True
    return False


def iter_tf_files(root: Path, include_dirs: Optional[List[str]], ignored_dirs: Set[str]) -> Iterable[Path]:
    scan_roots = [root / d for d in include_dirs] if include_dirs else [root]

    for scan_root in scan_roots:
        if not scan_root.exists():
            print(f"WARNING: path does not exist, skipping: {scan_root}")
            continue

        if should_skip_path(scan_root, ignored_dirs):
            continue

        for dirpath, dirnames, filenames in os.walk(scan_root):
            current_dir = Path(dirpath)

            dirnames[:] = [
                d for d in dirnames
                if not should_skip_path(current_dir / d, ignored_dirs)
            ]

            for filename in filenames:
                if filename.endswith(".tf"):
                    tf_file = current_dir / filename
                    if not should_skip_path(tf_file, ignored_dirs):
                        yield tf_file


def parse_tf_file(tf_file: Path) -> Dict[str, Any]:
    try:
        with tf_file.open("r", encoding="utf-8") as f:
            return hcl2.load(f)
    except Exception as exc:
        print(f"WARNING: failed to parse {tf_file}: {exc}")
        return {}


def stringify_body(value: Any) -> str:
    return repr(value)


def find_references(value: Any) -> List[str]:
    text = stringify_body(value)
    patterns = [
        r"module\.[A-Za-z0-9_\-]+",
        r"aws_[A-Za-z0-9_]+\.[A-Za-z0-9_\-]+",
        r"var\.[A-Za-z0-9_\-]+",
        r"local\.[A-Za-z0-9_\-]+",
    ]
    found: Set[str] = set()
    for pattern in patterns:
        found.update(re.findall(pattern, text))
    return sorted(found)


def extract_resources(parsed: Dict[str, Any], tf_file: Path, root: Path) -> List[TfItem]:
    results: List[TfItem] = []
    rel_file = str(tf_file.relative_to(root)) if tf_file.is_relative_to(root) else str(tf_file)
    rel_dir = str(tf_file.parent.relative_to(root)) if tf_file.parent.is_relative_to(root) else str(tf_file.parent)
    if rel_dir == ".":
        rel_dir = "root"

    for resource_block in parsed.get("resource", []):
        if not isinstance(resource_block, dict):
            continue

        for resource_type, resources in resource_block.items():
            if not isinstance(resources, dict):
                continue

            for resource_name, body in resources.items():
                item_id = f"{resource_type}.{resource_name}"
                results.append(
                    TfItem(
                        id=item_id,
                        kind="resource",
                        tf_type=resource_type,
                        name=resource_name,
                        file=rel_file,
                        directory=rel_dir,
                        body=body if isinstance(body, dict) else {},
                        references=find_references(body),
                    )
                )

    return results


def extract_modules(parsed: Dict[str, Any], tf_file: Path, root: Path) -> List[TfItem]:
    results: List[TfItem] = []
    rel_file = str(tf_file.relative_to(root)) if tf_file.is_relative_to(root) else str(tf_file)
    rel_dir = str(tf_file.parent.relative_to(root)) if tf_file.parent.is_relative_to(root) else str(tf_file.parent)
    if rel_dir == ".":
        rel_dir = "root"

    for module_block in parsed.get("module", []):
        if not isinstance(module_block, dict):
            continue

        for module_name, body in module_block.items():
            source = ""
            if isinstance(body, dict) and isinstance(body.get("source"), str):
                source = body["source"]

            item_id = f"module.{module_name}"
            results.append(
                TfItem(
                    id=item_id,
                    kind="module",
                    tf_type="module",
                    name=module_name,
                    source=source,
                    file=rel_file,
                    directory=rel_dir,
                    body=body if isinstance(body, dict) else {},
                    references=find_references(body),
                )
            )

    return results


def load_rules(path: Optional[Path]) -> DiagramRules:
    rules = DiagramRules()
    if not path:
        return rules

    if not path.exists():
        raise FileNotFoundError(f"Rules file not found: {path}")

    with path.open("r", encoding="utf-8") as f:
        raw = yaml.safe_load(f) or {}

    ignored = raw.get("ignore_dirs", []) or []
    rules.ignored_dirs.update(str(x) for x in ignored)

    for role in raw.get("file_roles", []) or []:
        file_name = normalize_path_text(str(role.get("file", "")))
        if file_name:
            rules.file_roles[file_name] = role

    for role in raw.get("directory_roles", []) or []:
        directory = normalize_path_text(str(role.get("directory", "")))
        if directory:
            rules.directory_roles[directory] = role

    for component in raw.get("logical_components", []) or []:
        rules.logical_components.append(
            LogicalComponent(
                name=str(component["name"]),
                type=str(component.get("type", "general")),
                directories=[normalize_path_text(str(x)) for x in component.get("directories", []) or []],
                files=[normalize_path_text(str(x)) for x in component.get("files", []) or []],
                account_scope=component.get("account_scope"),
                deployment_modes=list(component.get("deployment_modes", []) or []),
                connects_to=list(component.get("connects_to", []) or []),
                description=component.get("description"),
            )
        )

    rules.flows = list(raw.get("flows", []) or [])
    rules.profiles = dict(raw.get("profiles", {}) or {})
    return rules


def apply_roles(items: List[TfItem], rules: DiagramRules) -> None:
    for item in items:
        file_norm = normalize_path_text(item.file)
        file_base = normalize_path_text(Path(item.file).name)
        dir_norm = normalize_path_text(item.directory)

        matched_roles: List[Dict[str, Any]] = []

        for key, role in rules.file_roles.items():
            if file_norm.endswith(key) or file_base == key:
                matched_roles.append(role)

        for key, role in rules.directory_roles.items():
            if key in dir_norm:
                matched_roles.append(role)

        for role in matched_roles:
            if role.get("account_scope"):
                item.account_scope = role["account_scope"]
            if role.get("deployment_mode"):
                item.deployment_modes.append(role["deployment_mode"])
            if role.get("deployment_modes"):
                item.deployment_modes.extend(role["deployment_modes"])
            if role.get("logical_group"):
                item.logical_group = role["logical_group"]
            if role.get("tags"):
                item.tags.extend(role["tags"])

        item.deployment_modes = sorted(set(item.deployment_modes))
        item.tags = sorted(set(item.tags))


def load_terraform_inventory(root: Path, include_dirs: Optional[List[str]], rules: DiagramRules) -> List[TfItem]:
    inventory: List[TfItem] = []

    for tf_file in iter_tf_files(root, include_dirs, rules.ignored_dirs):
        parsed = parse_tf_file(tf_file)
        inventory.extend(extract_resources(parsed, tf_file, root))
        inventory.extend(extract_modules(parsed, tf_file, root))

    apply_roles(inventory, rules)
    return inventory


def component_matches_item(component: LogicalComponent, item: TfItem) -> bool:
    item_dir = normalize_path_text(item.directory)
    item_file = normalize_path_text(item.file)

    for directory in component.directories:
        if directory and directory in item_dir:
            return True

    for file_name in component.files:
        if file_name and item_file.endswith(file_name):
            return True

    return False


def build_logical_components(items: List[TfItem], rules: DiagramRules) -> List[LogicalComponent]:
    components: List[LogicalComponent] = []

    for template in rules.logical_components:
        component = LogicalComponent(
            name=template.name,
            type=template.type,
            directories=template.directories,
            files=template.files,
            account_scope=template.account_scope,
            deployment_modes=list(template.deployment_modes),
            connects_to=list(template.connects_to),
            description=template.description,
        )
        component.matched_items = [item for item in items if component_matches_item(component, item)]
        components.append(component)

    return components


def component_visible_for_profile(component: LogicalComponent, profile: Optional[str]) -> bool:
    if not profile:
        return True
    if not component.deployment_modes:
        return True
    return profile in component.deployment_modes


def item_visible_for_profile(item: TfItem, profile: Optional[str]) -> bool:
    if not profile:
        return True
    if not item.deployment_modes:
        return True
    return profile in item.deployment_modes


def icon_for_item(item: TfItem):
    if item.kind == "resource" and item.tf_type:
        return AWS_RESOURCE_MAP.get(item.tf_type, General)

    combined = f"{item.name} {item.source or ''} {item.directory}".lower()
    if "eks" in combined:
        return EKS
    if "vpc" in combined or "network" in combined:
        return VPC
    if "s3" in combined or "bucket" in combined:
        return S3
    if "iam" in combined or "role" in combined or "policy" in combined:
        return IAM
    if "config" in combined:
        return Config
    if "oam" in combined or "cloudwatch" in combined:
        return Cloudwatch
    return General


def icon_for_component(component: LogicalComponent):
    return LOGICAL_TYPE_ICON_MAP.get(component.type, General)


def label_for_item(item: TfItem, short: bool = True) -> str:
    if item.kind == "resource":
        if short:
            resource_type = (item.tf_type or "resource").replace("aws_", "")
            return wrap_label(f"{item.name}\n({resource_type})", 18)
        return wrap_label(f"{item.tf_type}.{item.name}", 22)

    if short:
        return wrap_label(f"module.{item.name}", 18)

    if item.source:
        return wrap_label(f"module.{item.name}\n{item.source}", 22)
    return wrap_label(f"module.{item.name}", 22)


def label_for_component(component: LogicalComponent, show_counts: bool = True) -> str:
    label = component.name
    if component.account_scope:
        label += f"\n[{component.account_scope}]"
    if show_counts:
        count = len(component.matched_items)
        label += f"\n{count} tf item{'s' if count != 1 else ''}"
    return wrap_label(label, 20)


def group_items_by_directory(items: List[TfItem]) -> Dict[str, List[TfItem]]:
    grouped: Dict[str, List[TfItem]] = {}
    for item in items:
        grouped.setdefault(item.directory or "root", []).append(item)
    return grouped


def group_components_by_scope(components: List[LogicalComponent]) -> Dict[str, List[LogicalComponent]]:
    grouped: Dict[str, List[LogicalComponent]] = {}
    for component in components:
        scope = component.account_scope or "shared / unspecified"
        grouped.setdefault(scope, []).append(component)
    return grouped


def default_diagram_attrs() -> Tuple[Dict[str, str], Dict[str, str]]:
    graph_attr = {
        "fontsize": "18",
        "pad": "1.0",
        "nodesep": "1.0",
        "ranksep": "1.2",
        "splines": "spline",
        "overlap": "false",
    }
    node_attr = {
        "fontsize": "10",
    }
    return graph_attr, node_attr


def render_raw_diagram(items: List[TfItem], output: str, outformat: str, direction: str, short_labels: bool) -> None:
    grouped = group_items_by_directory(items)
    graph_attr, node_attr = default_diagram_attrs()

    with Diagram(
        name=output,
        filename=output,
        outformat=outformat,
        show=False,
        direction=direction,
        graph_attr=graph_attr,
        node_attr=node_attr,
    ):
        for directory, dir_items in sorted(grouped.items()):
            with Cluster(wrap_label(directory, 24)):
                nodes = []
                for item in sorted(dir_items, key=lambda x: (x.kind, x.tf_type or "", x.name)):
                    node_cls = icon_for_item(item)
                    nodes.append(node_cls(label_for_item(item, short=short_labels)))

                for left, right in zip(nodes, nodes[1:]):
                    left >> Edge(style="invis") >> right


def render_logical_diagram(
    components: List[LogicalComponent],
    output: str,
    outformat: str,
    direction: str,
    profile: Optional[str] = None,
) -> None:
    visible_components = [c for c in components if component_visible_for_profile(c, profile)]
    components_by_name = {c.name: c for c in visible_components}
    grouped = group_components_by_scope(visible_components)
    graph_attr, node_attr = default_diagram_attrs()

    with Diagram(
        name=output,
        filename=output,
        outformat=outformat,
        show=False,
        direction=direction,
        graph_attr=graph_attr,
        node_attr=node_attr,
    ):
        rendered: Dict[str, Any] = {}

        for scope, scope_components in sorted(grouped.items()):
            with Cluster(wrap_label(scope, 24)):
                row_nodes = []
                for component in sorted(scope_components, key=lambda c: c.name):
                    node_cls = icon_for_component(component)
                    node = node_cls(label_for_component(component))
                    rendered[component.name] = node
                    row_nodes.append(node)

                for left, right in zip(row_nodes, row_nodes[1:]):
                    left >> Edge(style="invis") >> right

        for component in visible_components:
            source_node = rendered.get(component.name)
            if not source_node:
                continue
            for target_name in component.connects_to:
                target_component = components_by_name.get(target_name)
                target_node = rendered.get(target_name)
                if target_component and target_node:
                    source_node >> Edge(label="connects to") >> target_node


def render_flow_diagram(
    components: List[LogicalComponent],
    rules: DiagramRules,
    output: str,
    outformat: str,
    direction: str,
    profile: Optional[str] = None,
) -> None:
    visible_components = [c for c in components if component_visible_for_profile(c, profile)]
    by_name = {c.name: c for c in visible_components}
    graph_attr, node_attr = default_diagram_attrs()

    with Diagram(
        name=output,
        filename=output,
        outformat=outformat,
        show=False,
        direction=direction,
        graph_attr=graph_attr,
        node_attr=node_attr,
    ):
        rendered: Dict[str, Any] = {}
        grouped = group_components_by_scope(visible_components)

        for scope, scope_components in sorted(grouped.items()):
            with Cluster(wrap_label(scope, 24)):
                for component in sorted(scope_components, key=lambda c: c.name):
                    node_cls = icon_for_component(component)
                    rendered[component.name] = node_cls(label_for_component(component, show_counts=False))

        for flow in rules.flows:
            source = str(flow.get("from", ""))
            target = str(flow.get("to", ""))
            label = str(flow.get("label", ""))

            if source not in by_name or target not in by_name:
                continue

            source_node = rendered.get(source)
            target_node = rendered.get(target)
            if source_node and target_node:
                if label:
                    source_node >> Edge(label=label) >> target_node
                else:
                    source_node >> target_node

        # Also honor component-level connects_to if no explicit flow covers it.
        explicit_pairs = {(str(f.get("from", "")), str(f.get("to", ""))) for f in rules.flows}
        for component in visible_components:
            for target in component.connects_to:
                if (component.name, target) in explicit_pairs:
                    continue
                if target in by_name and component.name in rendered and target in rendered:
                    rendered[component.name] >> Edge(label="connects") >> rendered[target]


def print_summary(items: List[TfItem], components: List[LogicalComponent], profile: Optional[str]) -> None:
    visible_items = [item for item in items if item_visible_for_profile(item, profile)]
    resources = [i for i in visible_items if i.kind == "resource"]
    modules = [i for i in visible_items if i.kind == "module"]

    print("\nTerraform scan summary")
    print("----------------------")
    if profile:
        print(f"Profile:         {profile}")
    print(f"Resources found: {len(resources)}")
    print(f"Modules found:   {len(modules)}")
    print(f"Components:      {len(components)}")

    by_type: Dict[str, int] = {}
    for item in resources:
        by_type[item.tf_type or "unknown"] = by_type.get(item.tf_type or "unknown", 0) + 1

    if by_type:
        print("\nResource types:")
        for resource_type, count in sorted(by_type.items()):
            print(f"  {resource_type}: {count}")

    if components:
        print("\nLogical components:")
        for component in components:
            print(f"  {component.name}: {len(component.matched_items)} matched item(s)")


def write_example_rules_file(path: Path) -> None:
    example = {
        "ignore_dirs": [
            "examples",
            ".terraform",
            ".git",
        ],
        "profiles": {
            "security": {
                "description": "Resources deployed into the central security account"
            },
            "member": {
                "description": "Resources deployed into each member account"
            },
        },
        "file_roles": [
            {
                "file": "security.tf",
                "deployment_mode": "security",
                "account_scope": "security account",
                "tags": ["central", "security"],
            },
            {
                "file": "member.tf",
                "deployment_mode": "member",
                "account_scope": "member account",
                "tags": ["member"],
            },
        ],
        "directory_roles": [
            {
                "directory": "aws_config",
                "logical_group": "AWS Config",
                "tags": ["compliance"],
            },
            {
                "directory": "cw_oam_sink",
                "logical_group": "OAM Sink",
                "account_scope": "security account",
                "deployment_mode": "security",
                "tags": ["observability", "central"],
            },
            {
                "directory": "cw_oam_link",
                "logical_group": "OAM Link",
                "account_scope": "member account",
                "deployment_mode": "member",
                "tags": ["observability", "member"],
            },
        ],
        "logical_components": [
            {
                "name": "AWS Config - Security Account",
                "type": "compliance",
                "directories": ["aws_config"],
                "files": ["security.tf"],
                "account_scope": "security account",
                "deployment_modes": ["security"],
                "description": "Central AWS Config resources for the security account",
            },
            {
                "name": "AWS Config - Member Account",
                "type": "compliance",
                "directories": ["aws_config"],
                "files": ["member.tf"],
                "account_scope": "member account",
                "deployment_modes": ["member"],
                "description": "AWS Config resources deployed in member accounts",
            },
            {
                "name": "OAM Sink",
                "type": "observability",
                "directories": ["cw_oam_sink"],
                "account_scope": "security account",
                "deployment_modes": ["security"],
                "description": "CloudWatch OAM sink in the central security account",
            },
            {
                "name": "OAM Link",
                "type": "observability",
                "directories": ["cw_oam_link"],
                "account_scope": "member account",
                "deployment_modes": ["member"],
                "connects_to": ["OAM Sink"],
                "description": "CloudWatch OAM link in each member account",
            },
        ],
        "flows": [
            {
                "from": "OAM Link",
                "to": "OAM Sink",
                "label": "metrics / logs / traces",
            },
            {
                "from": "AWS Config - Member Account",
                "to": "AWS Config - Security Account",
                "label": "config aggregation / compliance visibility",
            },
        ],
    }

    with path.open("w", encoding="utf-8") as f:
        yaml.safe_dump(example, f, sort_keys=False)

    print(f"Wrote example rules file: {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate AWS architecture diagrams from Terraform repos.")

    parser.add_argument("repo", nargs="?", help="Path to the Terraform repo root.")
    parser.add_argument("--rules", help="Path to diagram rules YAML file.")
    parser.add_argument("--write-example-rules", help="Write an example rules YAML file and exit.")
    parser.add_argument("--include", nargs="*", default=None, help="Optional subdirectories to scan.")
    parser.add_argument("--ignore-dir", nargs="*", default=None, help="Additional directory names to ignore.")
    parser.add_argument("--view", choices=["raw", "logical", "profile", "flow"], default="logical")
    parser.add_argument("--profile", help="Deployment profile to render, such as security or member.")
    parser.add_argument("--output", default="terraform-aws-architecture", help="Output filename without extension.")
    parser.add_argument("--format", choices=["png", "svg", "pdf", "jpg"], default="svg")
    parser.add_argument("--direction", choices=["LR", "RL", "TB", "BT"], default="LR")
    parser.add_argument("--full-labels", action="store_true", help="Use full Terraform labels in raw view.")

    args = parser.parse_args()

    if args.write_example_rules:
        write_example_rules_file(Path(args.write_example_rules))
        return

    if not args.repo:
        parser.error("repo is required unless --write-example-rules is used")

    root = Path(args.repo).resolve()
    rules = load_rules(Path(args.rules).resolve() if args.rules else None)

    if args.ignore_dir:
        rules.ignored_dirs.update(args.ignore_dir)

    items = load_terraform_inventory(root=root, include_dirs=args.include, rules=rules)

    if not items:
        print("No Terraform resources or modules found.")
        return

    components = build_logical_components(items, rules)
    print_summary(items, components, args.profile if args.view in {"profile", "flow"} else None)

    if args.view == "raw":
        visible_items = [item for item in items if item_visible_for_profile(item, args.profile)]
        render_raw_diagram(
            items=visible_items,
            output=args.output,
            outformat=args.format,
            direction=args.direction,
            short_labels=not args.full_labels,
        )

    elif args.view == "logical":
        render_logical_diagram(
            components=components,
            output=args.output,
            outformat=args.format,
            direction=args.direction,
        )

    elif args.view == "profile":
        render_logical_diagram(
            components=components,
            output=args.output,
            outformat=args.format,
            direction=args.direction,
            profile=args.profile,
        )

    elif args.view == "flow":
        render_flow_diagram(
            components=components,
            rules=rules,
            output=args.output,
            outformat=args.format,
            direction=args.direction,
            profile=args.profile,
        )

    print(f"\nDiagram written to: {args.output}.{args.format}")


if __name__ == "__main__":
    main()
