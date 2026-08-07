"""Minimal GraphQL client for the Projects v2 API.

Deliberately not using a generated client. Projects v2 needs a handful of
operations, and a thin layer here keeps the retry/rate-limit behaviour and the
error messages under our control -- which matters, because GraphQL returns
HTTP 200 with an ``errors`` array rather than a useful status code.
"""

from __future__ import annotations

import logging
import random
import time
from typing import Any

import httpx

from .auth import API_ROOT, Credentials

log = logging.getLogger("projectops.graphql")

GRAPHQL_URL = f"{API_ROOT}/graphql"

# Errors worth retrying. Everything else is a bug in our query or a genuine
# permission problem, and retrying just wastes the rate-limit budget.
RETRYABLE_TYPES = {"RATE_LIMITED", "SERVICE_UNAVAILABLE"}
RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class GraphQLError(RuntimeError):
    def __init__(self, message: str, errors: list[dict[str, Any]] | None = None):
        super().__init__(message)
        self.errors = errors or []

    @property
    def is_forbidden(self) -> bool:
        return any(e.get("type") == "FORBIDDEN" for e in self.errors)


class Client:
    def __init__(
        self,
        credentials: Credentials,
        *,
        max_retries: int = 4,
        timeout: float = 30.0,
    ):
        self._creds = credentials
        self._max_retries = max_retries
        self._http = httpx.Client(timeout=timeout, headers=credentials.headers())

    def __enter__(self) -> "Client":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def close(self) -> None:
        self._http.close()

    def execute(self, query: str, **variables: Any) -> dict[str, Any]:
        payload = {"query": query, "variables": variables}
        last_error: Exception | None = None

        for attempt in range(self._max_retries + 1):
            if attempt:
                delay = min(2**attempt, 30) + random.uniform(0, 1)
                log.warning("retrying in %.1fs (attempt %d)", delay, attempt + 1)
                time.sleep(delay)

            resp = self._http.post(GRAPHQL_URL, json=payload)

            # Secondary rate limits arrive as 403/429 with Retry-After.
            if resp.status_code in (403, 429) and "retry-after" in resp.headers:
                wait = int(resp.headers["retry-after"])
                log.warning("secondary rate limit; sleeping %ds", wait)
                time.sleep(wait)
                continue

            if resp.status_code in RETRYABLE_STATUS:
                last_error = GraphQLError(f"HTTP {resp.status_code} from GraphQL API")
                continue

            if resp.status_code == 401:
                raise GraphQLError(
                    "401 Unauthorized. Token is invalid or expired -- App "
                    "installation tokens live for one hour."
                )

            resp.raise_for_status()
            body = resp.json()

            if errors := body.get("errors"):
                types = {e.get("type") for e in errors}
                if types & RETRYABLE_TYPES:
                    last_error = GraphQLError("retryable GraphQL error", errors)
                    continue
                raise GraphQLError(_explain(errors), errors)

            return body["data"]

        raise last_error or GraphQLError("exhausted retries with no response")

    def rate_limit(self) -> dict[str, Any]:
        return self.execute(
            "query { rateLimit { limit cost remaining resetAt } }"
        )["rateLimit"]


def _explain(errors: list[dict[str, Any]]) -> str:
    """Turn GraphQL errors into something actionable.

    The FORBIDDEN case is worth special handling: it is nearly always the
    Projects-v2 token problem rather than a genuine authorization failure.
    """
    messages = [e.get("message", "unknown error") for e in errors]
    joined = "; ".join(messages)

    if any(e.get("type") == "FORBIDDEN" for e in errors):
        joined += (
            "\n\nFORBIDDEN on Projects v2 almost always means the token lacks "
            "Projects scope. Checklist:\n"
            "  - GITHUB_TOKEN never works here. Use a PAT or App token.\n"
            "  - Org project + App token: needs 'Organization projects: "
            "Read and write'.\n"
            "  - User-owned project: needs a classic PAT with 'project' scope. "
            "App tokens cannot reach user projects.\n"
            "  - Private org project + App token: items will silently return "
            "zero. Apps cannot be project collaborators."
        )
    return joined
