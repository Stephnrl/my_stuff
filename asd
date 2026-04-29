import textwrap

def wrap_label(text: str, width: int = 16) -> str:
    return "\n".join(textwrap.wrap(text, width=width)) if text else ""

def label_for_item(item: Dict[str, str], short: bool = True) -> str:
    """
    Shorter labels reduce overlap a lot.
    """
    if item["kind"] == "resource":
        if short:
            # just show resource name, and type on next line
            return wrap_label(f'{item["name"]}\n({item["type"].replace("aws_", "")})', 18)
        return wrap_label(f'{item["type"]}.{item["name"]}', 22)

    # module
    if short:
        return wrap_label(f'module.{item["name"]}', 18)

    source = item.get("source", "")
    if source:
        return wrap_label(f'module.{item["name"]}\n{source}', 22)
    return wrap_label(f'module.{item["name"]}', 22)
