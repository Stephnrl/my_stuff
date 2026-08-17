"""Persistence for POA&M state.

The canonical record is JSON. The xlsx is a render of it and is never parsed
back - round-tripping through a spreadsheet loses types and merged-cell
structure and will eventually corrupt the audit trail.

Two drivers:
  local://./state      - filesystem, for tests and dry runs
  az://<account>/<container>  - Azure Blob, with ETag optimistic concurrency

The concurrency guard matters: two builds of the same component running at
once will otherwise interleave read-modify-write on current.json and one
build's findings vanish.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .models import PoamRecord, utc_now_iso

STATE_SCHEMA_VERSION = 1


@dataclass
class StateDocument:
    component_id: str
    records: list[PoamRecord]
    next_seq: int = 1
    schema_version: int = STATE_SCHEMA_VERSION
    last_updated: str = ""
    last_scan: dict[str, Any] | None = None
    scan_count: int = 0
    etag: str | None = None          # transport concern, not serialized

    def to_json(self) -> str:
        return json.dumps(
            {
                "schema_version": self.schema_version,
                "component_id": self.component_id,
                "next_seq": self.next_seq,
                "last_updated": self.last_updated or utc_now_iso(),
                "scan_count": self.scan_count,
                "last_scan": self.last_scan or {},
                "records": [r.to_dict() for r in self.records],
            },
            indent=2,
            sort_keys=False,
        )

    @classmethod
    def from_json(cls, blob: str, component_id: str, etag: str | None = None) -> "StateDocument":
        data = json.loads(blob)
        return cls(
            component_id=data.get("component_id", component_id),
            records=[PoamRecord.from_dict(r) for r in data.get("records", [])],
            next_seq=int(data.get("next_seq", 1)),
            schema_version=int(data.get("schema_version", STATE_SCHEMA_VERSION)),
            last_updated=data.get("last_updated", ""),
            last_scan=data.get("last_scan"),
            scan_count=int(data.get("scan_count", 0)),
            etag=etag,
        )

    @classmethod
    def empty(cls, component_id: str) -> "StateDocument":
        return cls(component_id=component_id, records=[], next_seq=1)


def component_slug(component_id: str) -> str:
    """Filesystem/blob-safe path segment. Preserves hierarchy with '/'.

    Dot-only segments are dropped outright. component_id reaches us from a
    workflow input, so "../../etc/passwd" or "a/../../b" must not be able to
    walk out of the state prefix and overwrite another component's POA&M.
    """
    parts = [p for p in component_id.strip("/").split("/") if p]
    safe: list[str] = []
    for part in parts:
        cleaned = "".join(ch if (ch.isalnum() or ch in "-._") else "-" for ch in part)
        # Reject "." / ".." / "..." and anything that is only dots.
        if not cleaned.strip("."):
            continue
        safe.append(cleaned.strip("."))
    return "/".join(p for p in safe if p) or "unknown"


class StateStore:
    """Interface: read_state / write_state / put_artifact."""

    def read_state(self, component_id: str) -> StateDocument:  # pragma: no cover - interface
        raise NotImplementedError

    def write_state(self, doc: StateDocument) -> str:  # pragma: no cover - interface
        raise NotImplementedError

    def put_artifact(self, path: str, data: bytes, content_type: str = "application/octet-stream") -> str:
        raise NotImplementedError  # pragma: no cover - interface


class LocalStore(StateStore):
    def __init__(self, root: str) -> None:
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def _state_path(self, component_id: str) -> Path:
        return self.root / "state" / component_slug(component_id) / "current.json"

    def read_state(self, component_id: str) -> StateDocument:
        p = self._state_path(component_id)
        if not p.exists():
            return StateDocument.empty(component_id)
        return StateDocument.from_json(p.read_text(encoding="utf-8"), component_id)

    def write_state(self, doc: StateDocument) -> str:
        p = self._state_path(doc.component_id)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(doc.to_json(), encoding="utf-8")
        return str(p)

    def put_artifact(self, path: str, data: bytes, content_type: str = "application/octet-stream") -> str:
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        return str(p)


class AzureBlobStore(StateStore):
    """Azure Blob driver. Auth via DefaultAzureCredential (OIDC/workload identity).

    For Azure Government pass environment='usgovernment' so the credential
    targets the correct authority host and the endpoint suffix is right.
    """

    def __init__(
        self,
        account: str,
        container: str,
        environment: str = "public",
        credential: Any | None = None,
        max_retries: int = 5,
    ) -> None:
        from azure.identity import AzureAuthorityHosts, DefaultAzureCredential
        from azure.storage.blob import BlobServiceClient

        suffix = "blob.core.usgovcloudapi.net" if environment == "usgovernment" else "blob.core.windows.net"
        authority = (
            AzureAuthorityHosts.AZURE_GOVERNMENT
            if environment == "usgovernment"
            else AzureAuthorityHosts.AZURE_PUBLIC_CLOUD
        )
        cred = credential or DefaultAzureCredential(authority=authority)
        self._client = BlobServiceClient(f"https://{account}.{suffix}", credential=cred)
        self._container = self._client.get_container_client(container)
        self.max_retries = max_retries
        self.account = account
        self.container = container
        self.suffix = suffix

    def _state_blob(self, component_id: str) -> str:
        return f"state/{component_slug(component_id)}/current.json"

    def read_state(self, component_id: str) -> StateDocument:
        from azure.core.exceptions import ResourceNotFoundError

        blob = self._container.get_blob_client(self._state_blob(component_id))
        try:
            downloader = blob.download_blob(encoding="utf-8")
            etag = downloader.properties.etag
            return StateDocument.from_json(downloader.readall(), component_id, etag=etag)
        except ResourceNotFoundError:
            return StateDocument.empty(component_id)

    def write_state(self, doc: StateDocument) -> str:
        """Write guarded by If-Match. Caller re-reads and retries on conflict."""
        from azure.core import MatchConditions
        from azure.core.exceptions import ResourceModifiedError, ResourceExistsError

        name = self._state_blob(doc.component_id)
        blob = self._container.get_blob_client(name)
        payload = doc.to_json().encode("utf-8")

        if doc.etag:
            blob.upload_blob(
                payload,
                overwrite=True,
                etag=doc.etag,
                match_condition=MatchConditions.IfNotModified,
                content_type="application/json",
            )
        else:
            # First write for this component: fail if someone beat us to it.
            blob.upload_blob(
                payload,
                overwrite=False,
                content_type="application/json",
            )
        return f"https://{self.account}.{self.suffix}/{self.container}/{name}"

    def put_artifact(self, path: str, data: bytes, content_type: str = "application/octet-stream") -> str:
        blob = self._container.get_blob_client(path)
        blob.upload_blob(data, overwrite=True, content_type=content_type)
        return f"https://{self.account}.{self.suffix}/{self.container}/{path}"


def build_store(uri: str, environment: str = "public") -> StateStore:
    """uri: 'local://./state' or 'az://<account>/<container>'."""
    if uri.startswith("local://"):
        return LocalStore(uri[len("local://") :] or "./.state")
    if uri.startswith("az://"):
        rest = uri[len("az://") :].strip("/")
        if "/" not in rest:
            raise ValueError("az:// URI must be az://<account>/<container>")
        account, container = rest.split("/", 1)
        return AzureBlobStore(account, container.split("/")[0], environment=environment)
    raise ValueError(f"Unsupported store URI: {uri}")


def with_concurrency_retry(store: StateStore, component_id: str, mutate, max_retries: int = 5):
    """Read -> mutate -> write, retrying the whole cycle on an ETag conflict.

    `mutate(doc) -> (doc, extra)`. Re-runs the reconcile against freshly read
    state rather than blindly retrying the write, which would clobber the
    concurrent build's findings.
    """
    # Imported lazily and optionally: the local driver must work on a runner
    # that has no Azure SDK installed (tests, dry runs, air-gapped debugging).
    try:
        from azure.core.exceptions import (  # type: ignore
            ResourceExistsError,
            ResourceModifiedError,
        )

        conflict_errors: tuple[type[Exception], ...] = (ResourceModifiedError, ResourceExistsError)
    except ImportError:
        conflict_errors = ()

    last_exc: Exception | None = None
    for attempt in range(max_retries):
        doc = store.read_state(component_id)
        doc, extra = mutate(doc)
        try:
            uri = store.write_state(doc)
            return doc, extra, uri
        except conflict_errors as exc:  # pragma: no cover - needs Azure
            last_exc = exc
            sleep_for = min(2**attempt * 0.5, 8) + (os.getpid() % 100) / 1000.0
            time.sleep(sleep_for)
    raise RuntimeError(
        f"Could not commit POA&M state for {component_id} after {max_retries} attempts "
        f"(concurrent builds of the same component). Last error: {last_exc}"
    )
