"""Authentication for the Projects v2 API.

Two supported credential sources:

1. A token supplied directly (fine-grained PAT, classic PAT, or a token minted
   elsewhere -- e.g. by actions/create-github-app-token in a workflow).
2. A GitHub App private key, from which we mint an installation access token.

IMPORTANT -- read before you debug for an hour:

* The default Actions ``GITHUB_TOKEN`` is repository-scoped and CANNOT touch
  Projects v2 at all, for read or write. Projects live at the *owner* level.
* GitHub App installation tokens work for **organization** projects when the
  app has ``Organization projects: Read and write``.
* GitHub Apps CANNOT read items in **private** Projects v2. The project's
  metadata resolves, but ``items`` returns ``totalCount: 0``. The cause is that
  the ``ProjectV2Actor`` union (project collaborators) admits only ``User`` and
  ``Team`` -- not ``Bot``. There is no workaround short of a user token.
* **User-owned** projects are not reachable by App installation tokens at all.
  Use a classic PAT with the ``project`` scope (plus ``repo`` if the board
  contains items from private repos).

Token format is opaque. GitHub began rolling out a stateless installation
token format in 2026; never parse or pattern-match a token's shape.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Literal

import httpx

API_ROOT = os.environ.get("GITHUB_API_URL", "https://api.github.com")

TokenSource = Literal["pat", "github-app"]


class AuthError(RuntimeError):
    """Raised when credentials are missing, malformed, or rejected."""


@dataclass(frozen=True)
class Credentials:
    token: str
    source: TokenSource

    def headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }


def _app_jwt(client_id: str, private_key: str) -> str:
    """Mint a short-lived JWT signed with the App private key (RS256).

    ``iat`` is backdated 60s to tolerate clock drift between the runner and
    GitHub; ``exp`` must be no more than 10 minutes out or GitHub rejects it.
    """
    try:
        import jwt  # PyJWT
    except ImportError as exc:  # pragma: no cover - import guard
        raise AuthError(
            "GitHub App auth needs PyJWT and cryptography: "
            "pip install 'projectops[app]'"
        ) from exc

    now = int(time.time())
    payload = {"iat": now - 60, "exp": now + 540, "iss": client_id}
    return jwt.encode(payload, private_key, algorithm="RS256")


def _installation_id(app_jwt: str, owner: str, repo: str | None) -> int:
    """Look up the installation id for an owner (or owner/repo)."""
    url = (
        f"{API_ROOT}/repos/{owner}/{repo}/installation"
        if repo
        else f"{API_ROOT}/orgs/{owner}/installation"
    )
    resp = httpx.get(
        url,
        headers={
            "Authorization": f"Bearer {app_jwt}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        timeout=30.0,
    )
    if resp.status_code == 404:
        raise AuthError(
            f"No installation found for {owner}. Install the App on that "
            "account and confirm it has 'Organization projects: Read and write'."
        )
    resp.raise_for_status()
    return int(resp.json()["id"])


def from_github_app(
    *,
    client_id: str,
    private_key: str,
    owner: str,
    repo: str | None = None,
    installation_id: int | None = None,
) -> Credentials:
    """Mint an installation access token. Valid for one hour; not refreshed."""
    app_jwt = _app_jwt(client_id, private_key)
    inst = installation_id or _installation_id(app_jwt, owner, repo)

    resp = httpx.post(
        f"{API_ROOT}/app/installations/{inst}/access_tokens",
        headers={
            "Authorization": f"Bearer {app_jwt}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        timeout=30.0,
    )
    if resp.status_code == 401:
        raise AuthError(
            "App JWT rejected. Check the client id matches the private key, "
            "and that the runner clock is not badly skewed."
        )
    resp.raise_for_status()
    return Credentials(token=resp.json()["token"], source="github-app")


def from_token(token: str) -> Credentials:
    if not token or not token.strip():
        raise AuthError("Empty token.")
    return Credentials(token=token.strip(), source="pat")


def resolve(
    *,
    token: str | None = None,
    app_client_id: str | None = None,
    app_private_key: str | None = None,
    owner: str | None = None,
    repo: str | None = None,
) -> Credentials:
    """Pick a credential source. Explicit token wins over App credentials."""
    token = token or os.environ.get("PROJECTOPS_TOKEN")
    if token:
        return from_token(token)

    app_client_id = app_client_id or os.environ.get("PROJECTOPS_APP_CLIENT_ID")
    app_private_key = app_private_key or os.environ.get("PROJECTOPS_APP_PRIVATE_KEY")

    if app_client_id and app_private_key:
        if not owner:
            raise AuthError("owner is required to resolve the App installation.")
        return from_github_app(
            client_id=app_client_id,
            private_key=app_private_key,
            owner=owner,
            repo=repo,
        )

    raise AuthError(
        "No credentials. Set PROJECTOPS_TOKEN, or both PROJECTOPS_APP_CLIENT_ID "
        "and PROJECTOPS_APP_PRIVATE_KEY. Note that GITHUB_TOKEN will not work "
        "for Projects v2."
    )
