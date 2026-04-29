def generate_diagram(
    root: Path,
    items: List[Dict[str, str]],
    output: str,
    outformat: str,
    direction: str,
) -> None:
    grouped = group_by_directory(items, root)

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
            with Cluster(directory):
                nodes = []

                for item in sorted(dir_items, key=lambda x: (x["kind"], x["type"], x["name"])):
                    node_cls = node_class_for_item(item)
                    node = node_cls(label_for_item(item, short=True))
                    nodes.append(node)

                # add invisible edges so graphviz prefers a horizontal row
                for i in range(len(nodes) - 1):
                    nodes[i] >> Edge(style="invis") >> nodes[i + 1]
