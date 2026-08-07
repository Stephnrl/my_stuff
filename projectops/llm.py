"""Azure OpenAI client. One call, schema-enforced JSON out, no agent harness.

No Node, no npm, no agent CLI. The only dependency beyond the base package is
``azure-identity``, and only if you use Entra authentication.

Two auth modes:

* **API key** -- ``api-key`` header. Simple; the key is a long-lived secret you
  have to store and rotate.
* **Entra ID** (preferred) -- ``DefaultAzureCredential`` against the
  ``https://cognitiveservices.azure.com/.default`` scope. On a self-hosted
  runner with a managed identity assigned, there is no secret to store at all.
  Grant the identity the "Cognitive Services OpenAI User" role; the Terraform
  module in ``terraform/`` does this for you.

Structured outputs (``response_format.json_schema`` with ``strict: true``) push
schema enforcement server-side. The model physically cannot emit a field name
you did not allow, which is a materially stronger guarantee than prompting for
JSON and hoping.
"""

from __future__ import annotations

import json
import logging
import os
import random
import time
from dataclasses import dataclass
from typing import Any

import httpx

log = logging.getLogger("projectops.llm")

DEFAULT_API_VERSION = "2024-10-21"  # first GA version with structured outputs
ENTRA_SCOPE = "https://cognitiveservices.azure.com/.default"

RETRYABLE_STATUS = {408, 429, 500, 502, 503, 504}


class LLMError(RuntimeError):
    pass


@dataclass
class AzureOpenAIConfig:
    endpoint: str          # https://RESOURCE.openai.azure.com
    deployment: str        # your DEPLOYMENT name, not the model name
    api_version: str = DEFAULT_API_VERSION
    api_key: str | None = None
    use_entra: bool = False
    # o-series and gpt-5 reject `temperature` and want `max_completion_tokens`
    # instead of `max_tokens`. Set this for those deployments.
    reasoning_model: bool = False
    max_output_tokens: int = 900
    timeout: float = 60.0

    @classmethod
    def from_env(cls) -> "AzureOpenAIConfig":
        endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
        deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT")
        if not endpoint or not deployment:
            raise LLMError(
                "Set AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT. "
                "AZURE_OPENAI_DEPLOYMENT is the deployment name you chose in "
                "Azure, which is often not the same as the model name."
            )
        api_key = os.environ.get("AZURE_OPENAI_API_KEY")
        return cls(
            endpoint=endpoint.rstrip("/"),
            deployment=deployment,
            api_version=os.environ.get(
                "AZURE_OPENAI_API_VERSION", DEFAULT_API_VERSION
            ),
            api_key=api_key,
            use_entra=not api_key,
            reasoning_model=os.environ.get("AZURE_OPENAI_REASONING", "").lower()
            in ("1", "true", "yes"),
        )


def _entra_token() -> str:
    try:
        from azure.identity import DefaultAzureCredential
    except ImportError as exc:  # pragma: no cover - import guard
        raise LLMError(
            "Entra auth needs azure-identity: pip install 'projectops[azure]'. "
            "Or set AZURE_OPENAI_API_KEY to use key auth instead."
        ) from exc

    try:
        return DefaultAzureCredential().get_token(ENTRA_SCOPE).token
    except Exception as exc:  # noqa: BLE001
        raise LLMError(
            f"Could not acquire an Entra token: {exc}\n"
            "On a self-hosted runner, confirm a managed identity is assigned "
            "and holds the 'Cognitive Services OpenAI User' role on the "
            "Azure OpenAI resource."
        ) from exc


class AzureOpenAI:
    def __init__(self, config: AzureOpenAIConfig):
        self.config = config
        self._http = httpx.Client(timeout=config.timeout)

    def __enter__(self) -> "AzureOpenAI":
        return self

    def __exit__(self, *exc: object) -> None:
        self._http.close()

    def _headers(self) -> dict[str, str]:
        if self.config.use_entra:
            return {"Authorization": f"Bearer {_entra_token()}"}
        if not self.config.api_key:
            raise LLMError("No AZURE_OPENAI_API_KEY and Entra auth not enabled.")
        return {"api-key": self.config.api_key}

    @property
    def _url(self) -> str:
        return (
            f"{self.config.endpoint}/openai/deployments/"
            f"{self.config.deployment}/chat/completions"
            f"?api-version={self.config.api_version}"
        )

    def structured(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        schema_name: str = "response",
        max_retries: int = 3,
    ) -> dict[str, Any]:
        """One completion, validated against ``schema`` server-side."""
        body: dict[str, Any] = {
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": schema_name,
                    "strict": True,
                    "schema": schema,
                },
            },
        }

        if self.config.reasoning_model:
            body["max_completion_tokens"] = self.config.max_output_tokens
        else:
            body["max_tokens"] = self.config.max_output_tokens
            body["temperature"] = 0  # classification, not creative writing

        last: Exception | None = None
        for attempt in range(max_retries + 1):
            if attempt:
                wait = min(2**attempt, 20) + random.uniform(0, 1)
                log.warning("retrying in %.1fs", wait)
                time.sleep(wait)

            resp = self._http.post(self._url, json=body, headers=self._headers())

            if resp.status_code == 429:
                wait = int(resp.headers.get("retry-after", 10))
                log.warning("throttled by Azure; sleeping %ds", wait)
                time.sleep(wait)
                continue
            if resp.status_code in RETRYABLE_STATUS:
                last = LLMError(f"HTTP {resp.status_code} from Azure OpenAI")
                continue
            if resp.status_code == 401:
                raise LLMError(
                    "401 from Azure OpenAI. With Entra auth this usually means "
                    "the identity lacks 'Cognitive Services OpenAI User'; with "
                    "key auth it means the key is wrong or rotated."
                )
            if resp.status_code == 404:
                raise LLMError(
                    f"404 for deployment {self.config.deployment!r}. Azure "
                    "routes by DEPLOYMENT name, not model name -- check the "
                    "deployment exists in this resource and region."
                )
            if resp.status_code == 400:
                raise LLMError(
                    f"400 from Azure OpenAI: {resp.text}\n"
                    "If this mentions response_format, the deployment's model "
                    "or api-version predates structured outputs. Needs "
                    f"{DEFAULT_API_VERSION} or later and a supporting model."
                )

            resp.raise_for_status()
            payload = resp.json()

            choice = payload["choices"][0]
            if choice.get("finish_reason") == "length":
                raise LLMError(
                    "Model hit the output token cap mid-JSON. Raise "
                    "max_output_tokens; a truncated structured response is "
                    "never valid."
                )
            if refusal := choice["message"].get("refusal"):
                raise LLMError(f"Model refused: {refusal}")

            content = choice["message"]["content"]
            try:
                return json.loads(content)
            except json.JSONDecodeError as exc:  # should be impossible when strict
                raise LLMError(
                    f"Structured output was not valid JSON: {exc}"
                ) from exc

        raise last or LLMError("exhausted retries with no response")
