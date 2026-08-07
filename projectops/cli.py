"""``projectops`` command line interface.

The composite action is a thin wrapper around these commands, so anything the
workflow can do you can also run locally against a scratch board.
"""

from __future__ import annotations

import json
import logging
import os
import sys
from pathlib import Path

import typer

from . import auth, board as board_mod, config as config_mod, fields, mapping
from . import llm as llm_mod, plan as plan_mod
from .graphql import Client

app = typer.Typer(add_completion=False, help="GitHub Projects v2 ProjectOps CLI")
log = logging.getLogger("projectops")


def _client(owner: str, repo: str | None, token: str | None) -> Client:
    creds = auth.resolve(token=token, owner=owner, repo=repo)
    return Client(creds)


def _split_repo(full: str) -> tuple[str, str]:
    owner, _, name = full.partition("/")
    if not owner or not name:
        raise typer.BadParameter(f"expected owner/repo, got {full!r}")
    return owner, name


@app.callback()
def _root(verbose: bool = typer.Option(False, "--verbose", "-v")) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)-7s %(message)s",
    )


@app.command()
def doctor(
    config: Path = typer.Option("projectops.yml", "--config", "-c"),
    repo: str = typer.Option(..., envvar="GITHUB_REPOSITORY"),
    token: str = typer.Option(None, envvar="PROJECTOPS_TOKEN"),
) -> None:
    """Verify credentials and print the board schema. Run this first."""
    cfg = config_mod.Config.load(config)
    owner, name = _split_repo(repo)

    with _client(owner, name, token) as client:
        project = fields.load_project(client, cfg.project_url)
        typer.secho(f"\n{project.title}  ({project.url})", bold=True)

        for f in sorted(project.fields.values(), key=lambda x: x.name):
            line = f"  {f.name:<20} {f.data_type}"
            if f.options:
                line += f"  [{len(f.options)} options]"
            if f.iterations:
                current = f.current_iteration()
                line += f"  [current: {current.title if current else 'none'}]"
            typer.echo(line)

        rl = client.rate_limit()
        typer.echo(f"\nrate limit: {rl['remaining']}/{rl['limit']} remaining")


@app.command()
def sync(
    issue: int = typer.Option(..., help="Issue number"),
    event: str = typer.Option("opened", help="opened|closed|labeled|assigned|..."),
    config: Path = typer.Option("projectops.yml", "--config", "-c"),
    repo: str = typer.Option(..., envvar="GITHUB_REPOSITORY"),
    token: str = typer.Option(None, envvar="PROJECTOPS_TOKEN"),
    dry_run: bool = typer.Option(False, "--dry-run"),
) -> None:
    """Add an issue to the board and apply the mapped field values."""
    cfg = config_mod.Config.load(config)
    owner, name = _split_repo(repo)

    with _client(owner, name, token) as client:
        project = fields.load_project(client, cfg.project_url)
        b = board_mod.Board(client, project)
        target = b.fetch_issue(owner, name, issue)

        plan = mapping.build_plan(
            target, event, cfg.rules, project,
            points_by_type=cfg.points_by_type,
            sprint_field=cfg.sprint_field,
            sprint_when_status=cfg.sprint_when_status,
        )

        for reason in plan.reasons:
            log.info("· %s", reason)

        if not plan.values:
            typer.echo("no rules matched; nothing to do")
            return

        if dry_run:
            typer.echo(json.dumps({k: str(v) for k, v in plan.values.items()}, indent=2))
            return

        item_id = b.ensure_item(target.node_id)
        errors = b.apply(item_id, plan.values)

        if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
            _write_summary(Path(summary), target, plan, errors)

        if errors:
            for field_name, msg in errors.items():
                typer.secho(f"! {field_name}: {msg}", fg=typer.colors.YELLOW)
            if cfg.fail_on_field_error:
                raise typer.Exit(1)

        typer.secho(f"synced #{issue}", fg=typer.colors.GREEN)


@app.command("sprint-report")
def sprint_report(
    config: Path = typer.Option("projectops.yml", "--config", "-c"),
    repo: str = typer.Option(..., envvar="GITHUB_REPOSITORY"),
    token: str = typer.Option(None, envvar="PROJECTOPS_TOKEN"),
) -> None:
    """Print the current iteration and its window. Wire this to a schedule."""
    cfg = config_mod.Config.load(config)
    owner, name = _split_repo(repo)

    if not cfg.sprint_field:
        typer.echo("no sprint.field configured")
        raise typer.Exit(1)

    with _client(owner, name, token) as client:
        project = fields.load_project(client, cfg.project_url)
        f = project.field(cfg.sprint_field)
        current, nxt = f.current_iteration(), f.next_iteration()

        typer.echo(f"current: {current.title if current else '—'}")
        if current:
            typer.echo(f"  {current.start} → {current.end}")
        typer.echo(f"next:    {nxt.title if nxt else '—'}")


@app.command("plan")
def plan_cmd(
    issue: int = typer.Option(..., help="Issue number to triage"),
    config: Path = typer.Option("projectops.yml", "--config", "-c"),
    repo: str = typer.Option(..., envvar="GITHUB_REPOSITORY"),
    out: Path = typer.Option("plan.json", "--out", "-o"),
    token: str = typer.Option(None, envvar="PROJECTOPS_READ_TOKEN"),
) -> None:
    """Ask Azure OpenAI for a board plan. Writes JSON; touches nothing.

    Run this in a job that holds NO write credential. The read token only
    needs to see the issue.
    """
    cfg = config_mod.Config.load(config)
    owner, name = _split_repo(repo)

    with _client(owner, name, token) as client:
        project = fields.load_project(client, cfg.project_url)
        b = board_mod.Board(client, project)
        target = b.fetch_issue(owner, name, issue)

    allowed_fields = cfg.agent_fields or []
    allowed_values = {f: _options_for(project, f) for f in allowed_fields}

    schema = plan_mod.build_schema(allowed_fields, allowed_values)
    user = plan_mod.build_user_prompt(
        issue_number=issue,
        title=target.title,
        body=target.body,
        labels=target.labels,
        issue_type=target.issue_type,
        allowed_values=allowed_values,
    )

    with llm_mod.AzureOpenAI(llm_mod.AzureOpenAIConfig.from_env()) as model:
        raw = model.structured(
            system=plan_mod.SYSTEM_PROMPT,
            user=user,
            schema=schema,
            schema_name="projectops_plan",
        )

    result = plan_mod.Plan.from_dict(raw)
    out.write_text(json.dumps(result.to_dict(), indent=2))
    typer.echo(json.dumps(result.to_dict(), indent=2))
    typer.secho(f"\nwrote {out}", fg=typer.colors.GREEN)


@app.command("apply-plan")
def apply_plan(
    plan_file: Path = typer.Argument(..., help="Plan JSON from `projectops plan`"),
    issue: int = typer.Option(..., help="Issue this run is processing"),
    config: Path = typer.Option("projectops.yml", "--config", "-c"),
    repo: str = typer.Option(..., envvar="GITHUB_REPOSITORY"),
    token: str = typer.Option(None, envvar="PROJECTOPS_TOKEN"),
    max_changes: int = typer.Option(5, "--max-changes"),
    min_confidence: str = typer.Option("medium", "--min-confidence"),
    dry_run: bool = typer.Option(False, "--dry-run"),
) -> None:
    """Validate a plan against the allowlist, then apply it. No model runs here."""
    cfg = config_mod.Config.load(config)
    owner, name = _split_repo(repo)
    candidate = plan_mod.Plan.load(plan_file)

    with _client(owner, name, token) as client:
        project = fields.load_project(client, cfg.project_url)
        allowed_fields = cfg.agent_fields or []
        allowed_values = {f: _options_for(project, f) for f in allowed_fields}

        try:
            validated = plan_mod.validate(
                candidate,
                expected_issue=issue,
                allowed_fields=allowed_fields,
                allowed_values=allowed_values,
                max_changes=max_changes,
                min_confidence=min_confidence,
            )
        except plan_mod.PlanRejected as exc:
            typer.secho(f"PLAN REJECTED: {exc}", fg=typer.colors.RED, err=True)
            raise typer.Exit(1) from exc

        typer.echo(f"reasoning: {validated.reasoning}")
        if not validated.changes:
            typer.echo("empty plan; nothing to apply")
            return
        if dry_run:
            typer.echo(json.dumps(validated.to_dict(), indent=2))
            return

        b = board_mod.Board(client, project)
        target = b.fetch_issue(owner, name, issue)
        item_id = b.ensure_item(target.node_id)
        errors = b.apply(item_id, validated.as_values())

        for field_name, msg in errors.items():
            typer.secho(f"! {field_name}: {msg}", fg=typer.colors.YELLOW)

        typer.secho(f"applied {len(validated.changes)} change(s)", fg=typer.colors.GREEN)


def _options_for(project, field_name: str) -> list[str]:
    """Real option names for a single-select field, for the allowlist."""
    if not project.has_field(field_name):
        return []
    f = project.field(field_name)
    if f.data_type != "SINGLE_SELECT":
        return []
    return list(f.option_labels)


def _write_summary(path: Path, issue, plan, errors: dict[str, str]) -> None:
    lines = [f"### ProjectOps · #{issue.number} {issue.title}", ""]
    for k, v in plan.values.items():
        mark = "❌" if k in errors else "✅"
        lines.append(f"- {mark} **{k}** → `{v}`")
    if errors:
        lines += ["", "<details><summary>Errors</summary>", ""]
        lines += [f"- `{k}`: {v}" for k, v in errors.items()]
        lines += ["", "</details>"]
    with path.open("a") as fh:
        fh.write("\n".join(lines) + "\n")


def main() -> None:
    try:
        app()
    except (auth.AuthError, config_mod.ConfigError) as exc:
        typer.secho(f"error: {exc}", fg=typer.colors.RED, err=True)
        sys.exit(2)


if __name__ == "__main__":
    main()
