#!/usr/bin/env python3
"""Read-only, bounded freshness checks for the creator's approved sources."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import http.client
import ipaddress
import io
import json
import re
import select
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple


MAX_TOTAL_SECONDS = 30.0
REQUEST_TIMEOUT_SECONDS = 5.0
RETRY_DELAY_SECONDS = 0.2
MAX_RETRIES = 1
MAX_SOURCE_BYTES = 256 * 1024
MAX_TOTAL_BYTES = 1024 * 1024
READ_CHUNK_BYTES = 8192
DEFAULT_ASSESSMENT_WINDOW_DAYS = 30

# Only these official file paths can be fetched. The branch is deliberately fixed;
# repository-head movement outside a configured path is not treated as source drift.
REPOSITORY_PATHS = {
    "anthropic:skills/skill-creator/SKILL.md": ("anthropics/skills", "skills/skill-creator/SKILL.md"),
    "anthropic:skills/skill-creator/references/schemas.md": ("anthropics/skills", "skills/skill-creator/references/schemas.md"),
    "anthropic:skills/skill-creator/agents/grader.md": ("anthropics/skills", "skills/skill-creator/agents/grader.md"),
    "anthropic:skills/skill-creator/agents/comparator.md": ("anthropics/skills", "skills/skill-creator/agents/comparator.md"),
    "anthropic:skills/skill-creator/agents/analyzer.md": ("anthropics/skills", "skills/skill-creator/agents/analyzer.md"),
    "anthropic:skills/skill-creator/scripts/run_loop.py": ("anthropics/skills", "skills/skill-creator/scripts/run_loop.py"),
    "anthropic:skills/skill-creator/scripts/run_eval.py": ("anthropics/skills", "skills/skill-creator/scripts/run_eval.py"),
    "anthropic:skills/skill-creator/scripts/quick_validate.py": ("anthropics/skills", "skills/skill-creator/scripts/quick_validate.py"),
    "anthropic:skills/skill-creator/scripts/package_skill.py": ("anthropics/skills", "skills/skill-creator/scripts/package_skill.py"),
    "openai:skills/.system/skill-creator/SKILL.md": ("openai/skills", "skills/.system/skill-creator/SKILL.md"),
    "openai:skills/.system/skill-creator/references/openai_yaml.md": ("openai/skills", "skills/.system/skill-creator/references/openai_yaml.md"),
    "openai:skills/.system/skill-creator/scripts/quick_validate.py": ("openai/skills", "skills/.system/skill-creator/scripts/quick_validate.py"),
    "anthropic-official-plugin:SKILL.md": (
        "anthropics/claude-plugins-official",
        "plugins/skill-creator/skills/skill-creator/SKILL.md",
    ),
}
FIXED_URLS = {
    "agent-skills-format": "https://agentskills.io/specification.md",
}
MANUAL_SOURCE_IDS = {
    "openai-skills-docs",
    "openai-skill-evals",
    "openai-installed-creator",
    "anthropic-authoring",
    "anthropic-release",
}
SUPPORTED_SOURCE_IDS = set(REPOSITORY_PATHS) | set(FIXED_URLS) | MANUAL_SOURCE_IDS
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_REVISION_RE = re.compile(r"^[0-9a-f]{40}$")
MAX_DIFF_BYTES = 64 * 1024
MAX_DIFF_LINES = 1000
MAX_DIFF_CHARS = 16000


class FetchError(Exception):
    """A bounded source retrieval failure."""

    def __init__(self, message: str, bytes_read: int = 0):
        super().__init__(message)
        self.bytes_read = bytes_read if isinstance(bytes_read, int) and not isinstance(bytes_read, bool) else 0


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _remaining_time(deadline: float, monotonic: Callable[[], float]) -> float:
    remaining = deadline - monotonic()
    if remaining <= 0:
        raise TimeoutError("retrieval deadline exceeded")
    return remaining


def _resolve_addresses(
    host: str,
    port: int,
    *,
    deadline: float,
    monotonic: Callable[[], float],
) -> List[Any]:
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        return socket.getaddrinfo(host, port, 0, socket.SOCK_STREAM, 0, socket.AI_NUMERICHOST)

    lookup_program = "\n".join((
        "import json",
        "import socket",
        "import sys",
        "try:",
        "    addresses = socket.getaddrinfo(sys.argv[1], int(sys.argv[2]), 0, socket.SOCK_STREAM)",
        "except OSError as exc:",
        "    print(json.dumps({'error': str(exc)}))",
        "    sys.exit(1)",
        "print(json.dumps({'addresses': addresses}))",
    ))
    process = subprocess.Popen(
        [sys.executable, "-c", lookup_program, host, str(port)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        stdout, _ = process.communicate(timeout=_remaining_time(deadline, monotonic))
    except (subprocess.TimeoutExpired, TimeoutError) as exc:
        process.kill()
        process.communicate()
        raise TimeoutError("retrieval deadline exceeded during DNS resolution") from exc
    except BaseException:
        process.kill()
        process.communicate()
        raise
    _remaining_time(deadline, monotonic)

    try:
        payload = json.loads(stdout)
    except (TypeError, ValueError) as exc:
        raise OSError("DNS resolver returned invalid data") from exc
    if not isinstance(payload, dict):
        raise OSError("DNS resolver returned invalid data")
    if process.returncode != 0:
        error = payload.get("error")
        raise socket.gaierror(error if isinstance(error, str) and error else "name resolution failed")

    entries = payload.get("addresses")
    if not isinstance(entries, list) or not entries:
        raise socket.gaierror("name resolution returned no addresses")
    addresses = []
    for entry in entries:
        if not isinstance(entry, list) or len(entry) != 5 or not isinstance(entry[4], list):
            raise OSError("DNS resolver returned invalid address data")
        family, socktype, proto, canonname, sockaddr = entry
        addresses.append((family, socktype, proto, canonname, tuple(sockaddr)))
    return addresses


def _create_connection_with_deadline(
    address: Tuple[str, int],
    source_address: Optional[Tuple[Any, ...]],
    *,
    deadline: float,
    monotonic: Callable[[], float],
) -> Any:
    host, port = address
    failure = None
    for family, socktype, proto, _, sockaddr in _resolve_addresses(
        host,
        port,
        deadline=deadline,
        monotonic=monotonic,
    ):
        connection = None
        try:
            connection = socket.socket(family, socktype, proto)
            connection.settimeout(_remaining_time(deadline, monotonic))
            if source_address:
                connection.bind(source_address)
            connection.connect(sockaddr)
            return connection
        except (socket.timeout, TimeoutError) as exc:
            if connection is not None:
                connection.close()
            raise TimeoutError("retrieval deadline exceeded during connection") from exc
        except OSError as exc:
            failure = exc
            if connection is not None:
                connection.close()
    if failure is not None:
        raise failure
    raise OSError("getaddrinfo returns an empty list")


class _DeadlineSocketReader(io.RawIOBase):
    def __init__(self, owner: "_DeadlineSocket"):
        super().__init__()
        self._owner = owner

    def readable(self) -> bool:
        return True

    def readinto(self, buffer: Any) -> int:
        if self.closed:
            return 0
        sock = self._owner.socket
        while True:
            remaining = _remaining_time(self._owner.deadline, self._owner.monotonic)
            pending = getattr(sock, "pending", None)
            if callable(pending) and pending() > 0:
                ready = True
            else:
                ready = bool(select.select([sock], [], [], remaining)[0])
            if not ready:
                raise TimeoutError("total retrieval deadline exceeded")
            remaining = _remaining_time(self._owner.deadline, self._owner.monotonic)
            sock.settimeout(remaining)
            try:
                return sock.recv_into(buffer)
            except (socket.timeout, TimeoutError) as exc:
                raise TimeoutError("total retrieval deadline exceeded") from exc

    def close(self) -> None:
        if not self.closed:
            self._owner.reader_closed()
        super().close()


class _DeadlineSocket:
    def __init__(self, sock: Any, deadline: float, monotonic: Callable[[], float]):
        self.socket = sock
        self.deadline = deadline
        self.monotonic = monotonic
        self._reader_count = 0
        self._close_requested = False

    def makefile(self, mode: str = "r", *args: Any, **kwargs: Any) -> Any:
        if mode != "rb":
            return self.socket.makefile(mode, *args, **kwargs)
        self._reader_count += 1
        raw = _DeadlineSocketReader(self)
        return io.BufferedReader(raw, buffer_size=READ_CHUNK_BYTES)

    def sendall(self, data: bytes) -> None:
        self.socket.settimeout(_remaining_time(self.deadline, self.monotonic))
        self.socket.sendall(data)

    def reader_closed(self) -> None:
        self._reader_count = max(0, self._reader_count - 1)
        if self._close_requested and self._reader_count == 0:
            self.socket.close()

    def close(self) -> None:
        self._close_requested = True
        if self._reader_count == 0:
            self.socket.close()

    def abort(self) -> None:
        self._close_requested = True
        try:
            self.socket.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.socket.close()

    def __getattr__(self, name: str) -> Any:
        return getattr(self.socket, name)


class _DeadlineConnectionMixin:
    def _configure_deadline(self, deadline: float, monotonic: Callable[[], float]) -> None:
        self._deadline = deadline
        self._monotonic = monotonic
        self._deadline_socket: Optional[_DeadlineSocket] = None

    def _connect_tcp(self) -> None:
        sock = _create_connection_with_deadline(
            (self.host, self.port),
            self.source_address,
            deadline=self._deadline,
            monotonic=self._monotonic,
        )
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.sock = _DeadlineSocket(sock, self._deadline, self._monotonic)
            self._deadline_socket = self.sock
            if self._tunnel_host:
                self._tunnel()
        except BaseException:
            sock.close()
            raise

    def abort(self) -> None:
        if self._deadline_socket is not None:
            self._deadline_socket.abort()
        elif self.sock is not None:
            self.sock.close()
        self.sock = None


class _DeadlineHTTPConnection(_DeadlineConnectionMixin, http.client.HTTPConnection):
    def __init__(
        self,
        host: str,
        timeout: Optional[float] = None,
        *,
        deadline: float,
        monotonic: Callable[[], float],
    ):
        self._configure_deadline(deadline, monotonic)
        super().__init__(host, timeout=timeout)

    def connect(self) -> None:
        self._connect_tcp()


class _DeadlineHTTPSConnection(_DeadlineConnectionMixin, http.client.HTTPSConnection):
    def __init__(
        self,
        host: str,
        timeout: Optional[float] = None,
        *,
        context: Optional[ssl.SSLContext] = None,
        deadline: float,
        monotonic: Callable[[], float],
    ):
        self._configure_deadline(deadline, monotonic)
        super().__init__(host, timeout=timeout, context=context)

    def connect(self) -> None:
        self._connect_tcp()
        deadline_socket = self.sock
        raw_socket = deadline_socket.socket
        server_hostname = self._tunnel_host or self.host
        try:
            secure_socket = self._context.wrap_socket(
                raw_socket,
                server_hostname=server_hostname,
                do_handshake_on_connect=False,
            )
            secure_socket.setblocking(False)
            while True:
                remaining = _remaining_time(self._deadline, self._monotonic)
                try:
                    secure_socket.do_handshake()
                    break
                except ssl.SSLWantReadError:
                    if not select.select([secure_socket], [], [], remaining)[0]:
                        raise TimeoutError("total retrieval deadline exceeded")
                except ssl.SSLWantWriteError:
                    if not select.select([], [secure_socket], [], remaining)[1]:
                        raise TimeoutError("total retrieval deadline exceeded")
            secure_socket.settimeout(_remaining_time(self._deadline, self._monotonic))
            self.sock = _DeadlineSocket(secure_socket, self._deadline, self._monotonic)
            self._deadline_socket = self.sock
        except BaseException:
            raw_socket.close()
            self.sock = None
            self._deadline_socket = None
            raise


class _DeadlineHTTPHandler(urllib.request.HTTPHandler):
    def __init__(self, deadline: float, monotonic: Callable[[], float]):
        super().__init__()
        self.deadline = deadline
        self.monotonic = monotonic
        self.connections: List[_DeadlineHTTPConnection] = []

    def http_open(self, req: urllib.request.Request) -> Any:
        def create_connection(host: str, timeout: Optional[float], **kwargs: Any) -> _DeadlineHTTPConnection:
            connection = _DeadlineHTTPConnection(host, timeout=timeout, **kwargs)
            self.connections.append(connection)
            return connection
        return self.do_open(
            create_connection,
            req,
            deadline=self.deadline,
            monotonic=self.monotonic,
        )

    def abort_connections(self) -> None:
        for connection in self.connections:
            connection.abort()


class _DeadlineHTTPSHandler(urllib.request.HTTPSHandler):
    def __init__(self, deadline: float, monotonic: Callable[[], float]):
        super().__init__(context=ssl.create_default_context())
        self.deadline = deadline
        self.monotonic = monotonic
        self.connections: List[_DeadlineHTTPSConnection] = []

    def https_open(self, req: urllib.request.Request) -> Any:
        def create_connection(host: str, timeout: Optional[float], **kwargs: Any) -> _DeadlineHTTPSConnection:
            connection = _DeadlineHTTPSConnection(host, timeout=timeout, **kwargs)
            self.connections.append(connection)
            return connection
        return self.do_open(
            create_connection,
            req,
            context=self._context,
            deadline=self.deadline,
            monotonic=self.monotonic,
        )

    def abort_connections(self) -> None:
        for connection in self.connections:
            connection.abort()


def _expected_refresh_url(source_id: str) -> Optional[str]:
    if source_id in REPOSITORY_PATHS:
        repository, path = REPOSITORY_PATHS[source_id]
        return "https://raw.githubusercontent.com/{}/main/{}".format(repository, path)
    return FIXED_URLS.get(source_id)


def _parse_time(value: Any) -> datetime:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("last_assessed_at must be an ISO date or timestamp")
    parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _normalize_sha256(value: Any) -> Optional[str]:
    if not isinstance(value, str):
        return None
    digest = value[7:] if value.startswith("sha256:") else value
    return digest if _SHA256_RE.fullmatch(digest) else None


def _validate_registry(registry: Any) -> List[Dict[str, Any]]:
    if not isinstance(registry, dict) or registry.get("schema_version") != "1.0":
        raise ValueError("registry schema_version must be 1.0")
    window = registry.get("assessment_window_days", DEFAULT_ASSESSMENT_WINDOW_DAYS)
    if isinstance(window, bool) or not isinstance(window, int) or not 1 <= window <= 365:
        raise ValueError("assessment_window_days must be an integer from 1 through 365")
    sources = registry.get("sources")
    if not isinstance(sources, list):
        raise ValueError("registry sources must be a list")

    seen = set()
    validated = []
    for source in sources:
        if not isinstance(source, dict):
            raise ValueError("each registry source must be an object")
        source_id = source.get("source_id")
        if source_id not in SUPPORTED_SOURCE_IDS:
            raise ValueError("unsupported source_id: {!r}".format(source_id))
        if source_id in seen:
            raise ValueError("duplicate source_id: {}".format(source_id))
        seen.add(source_id)

        refresh_url = source.get("refresh_url")
        expected_url = _expected_refresh_url(source_id)
        if refresh_url is not None:
            if expected_url is None or refresh_url != expected_url:
                raise ValueError("unsupported refresh URL for {}".format(source_id))
            if _normalize_sha256(source.get("last_assessed_sha256")) is None:
                raise ValueError("{} requires a complete assessed SHA-256 before refresh".format(source_id))
            _parse_time(source.get("last_assessed_at"))
        disposition = source.get("disposition")
        if disposition not in ("adopt", "adapt", "defer", "reject"):
            raise ValueError("{} has an unsupported disposition".format(source_id))
        if not isinstance(source.get("disposition_rationale"), str) or not source["disposition_rationale"].strip():
            raise ValueError("{} requires a disposition rationale".format(source_id))
        if not isinstance(source.get("affected_refs"), list) or not all(
            isinstance(reference, str) and reference.strip() for reference in source["affected_refs"]
        ):
            raise ValueError("{} requires affected local references".format(source_id))
        validated.append(source)
    return validated


def _header(headers: Any, name: str) -> Optional[str]:
    if not isinstance(headers, dict):
        return None
    lowered = name.lower()
    for key, value in headers.items():
        if str(key).lower() == lowered:
            return str(value)
    return None


def _fetch_url(
    url: str,
    *,
    timeout_seconds: float,
    max_bytes: int,
    deadline: float,
    monotonic: Callable[[], float],
) -> Dict[str, Any]:
    effective_deadline = min(deadline, monotonic() + timeout_seconds)
    request = urllib.request.Request(
        url,
        headers={"Accept-Encoding": "identity", "User-Agent": "assistant-skill-creator-guidance-check/1.0"},
    )
    http_handler = _DeadlineHTTPHandler(effective_deadline, monotonic)
    https_handler = _DeadlineHTTPSHandler(effective_deadline, monotonic)
    opener = urllib.request.build_opener(_NoRedirect(), http_handler, https_handler)
    body = bytearray()

    def abort_connections() -> None:
        http_handler.abort_connections()
        https_handler.abort_connections()

    try:
        with opener.open(request, timeout=timeout_seconds) as response:
            status = getattr(response, "status", response.getcode())
            headers = dict(response.headers.items())
            final_url = response.geturl()
            if status != 200:
                return {"status_code": status, "final_url": final_url, "headers": headers, "body": b""}

            encoding = _header(headers, "Content-Encoding")
            if encoding and encoding.lower() != "identity":
                return {
                    "status_code": status,
                    "final_url": final_url,
                    "headers": headers,
                    "body": b"",
                    "partial": True,
                    "error": "unsupported content encoding",
                }

            length = _header(headers, "Content-Length")
            if length is not None:
                try:
                    expected_length = int(length)
                except ValueError:
                    return {
                        "status_code": status,
                        "final_url": final_url,
                        "headers": headers,
                        "body": b"",
                        "partial": True,
                        "error": "invalid Content-Length",
                    }
                if expected_length < 0 or expected_length > max_bytes:
                    return {
                        "status_code": status,
                        "final_url": final_url,
                        "headers": headers,
                        "body": b"",
                        "partial": True,
                        "error": "source exceeds the byte limit",
                    }

            while True:
                remaining = effective_deadline - monotonic()
                if remaining <= 0:
                    raise FetchError("retrieval deadline exceeded")
                raw_socket = getattr(getattr(getattr(response, "fp", None), "raw", None), "_sock", None)
                if raw_socket is not None:
                    raw_socket.settimeout(min(timeout_seconds, remaining))
                chunk = response.read1(min(READ_CHUNK_BYTES, max_bytes + 1 - len(body)))
                if not chunk:
                    break
                body.extend(chunk)
                if len(body) > max_bytes:
                    return {
                        "status_code": status,
                        "final_url": final_url,
                        "headers": headers,
                        "body": bytes(body),
                        "partial": True,
                        "error": "source exceeds the byte limit",
                    }
            if length is not None and len(body) != expected_length:
                return {
                    "status_code": status,
                    "final_url": final_url,
                    "headers": headers,
                    "body": bytes(body),
                    "partial": True,
                    "error": "response length did not match Content-Length",
                }
            return {"status_code": status, "final_url": final_url, "headers": headers, "body": bytes(body)}
    except urllib.error.HTTPError as exc:
        try:
            return {
                "status_code": exc.code,
                "final_url": exc.geturl(),
                "headers": dict(exc.headers.items()) if exc.headers else {},
                "body": b"",
            }
        finally:
            exc.close()
            abort_connections()
    except (http.client.HTTPException, urllib.error.URLError, OSError, TimeoutError, FetchError) as exc:
        abort_connections()
        partial = getattr(exc, "partial", b"")
        partial_bytes = len(partial) if isinstance(partial, bytes) else 0
        observed_bytes = max(len(body) + partial_bytes, getattr(exc, "bytes_read", 0))
        raise FetchError(str(exc), bytes_read=observed_bytes) from exc


def _identity(source: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "last_assessed_at": source.get("last_assessed_at"),
        "last_assessed_revision": source.get("last_assessed_revision"),
        "last_assessed_sha256": source.get("last_assessed_sha256"),
        "disposition": source.get("disposition"),
        "disposition_rationale": source.get("disposition_rationale"),
        "affected_refs": list(source.get("affected_refs", [])),
    }


def _unavailable(source: Dict[str, Any], reason: str, retrieval_state: str = "unavailable") -> Dict[str, Any]:
    return {
        "source_id": source["source_id"],
        "status": "unavailable",
        "retrieval_state": retrieval_state,
        "reason": reason,
        "last_assessed": _identity(source),
    }


def _retrieve_complete(
    url: str,
    *,
    byte_limit: int,
    deadline: float,
    retrieve: Callable[..., Dict[str, Any]],
    monotonic: Callable[[], float],
    sleeper: Callable[[float], None],
) -> Dict[str, Any]:
    failure = "source retrieval failed"
    consumed_bytes = 0
    for attempt in range(MAX_RETRIES + 1):
        attempt_limit = byte_limit - consumed_bytes
        if attempt_limit <= 0:
            return {
                "error": "response-byte budget exhausted during retries",
                "state": "unavailable",
                "bytes_read": consumed_bytes,
            }
        remaining = deadline - monotonic()
        if remaining <= 0:
            return {"error": "total retrieval deadline exceeded", "state": "unavailable", "bytes_read": consumed_bytes}
        try:
            response = retrieve(
                url,
                timeout_seconds=min(REQUEST_TIMEOUT_SECONDS, remaining),
                max_bytes=attempt_limit,
                deadline=deadline,
                monotonic=monotonic,
            )
            if not isinstance(response, dict):
                return {"error": "fetcher returned an invalid response", "state": "unavailable", "bytes_read": consumed_bytes}
            response_body = response.get("body", b"")
            attempt_bytes = min(len(response_body), attempt_limit + 1) if isinstance(response_body, bytes) else 0
            consumed_bytes += attempt_bytes
            if monotonic() >= deadline:
                return {"error": "total retrieval deadline exceeded", "state": "unavailable", "bytes_read": consumed_bytes}
            status_code = response.get("status_code")
            if status_code in (408, 429) or (isinstance(status_code, int) and 500 <= status_code <= 599):
                failure = "temporary HTTP status {}".format(status_code)
                if attempt < MAX_RETRIES and consumed_bytes < byte_limit and _wait_before_retry(sleeper, deadline, monotonic):
                    continue
                return {"error": failure, "state": "unavailable", "bytes_read": consumed_bytes}
            if response.get("partial"):
                return {
                    "error": response.get("error", "partial response"),
                    "state": "partial",
                    "bytes_read": consumed_bytes,
                }
            if response.get("final_url") != url:
                return {
                    "error": "redirect or final URL mismatch is not supported",
                    "state": "unavailable",
                    "bytes_read": consumed_bytes,
                }
            if status_code == 206:
                return {"error": "partial HTTP 206 response is not accepted", "state": "partial", "bytes_read": consumed_bytes}
            if status_code != 200:
                return {"error": "HTTP status {}".format(status_code), "state": "unavailable", "bytes_read": consumed_bytes}
            if not isinstance(response_body, bytes):
                return {"error": "response body is not complete bytes", "state": "partial", "bytes_read": consumed_bytes}
            if len(response_body) > attempt_limit:
                return {"error": "source exceeds the response-byte limit", "state": "partial", "bytes_read": consumed_bytes}
            content_length = _header(response.get("headers", {}), "Content-Length")
            if content_length is not None:
                try:
                    expected_length = int(content_length)
                except ValueError:
                    return {"error": "invalid Content-Length", "state": "partial", "bytes_read": consumed_bytes}
                if expected_length != len(response_body):
                    return {
                        "error": "response length did not match Content-Length",
                        "state": "partial",
                        "bytes_read": consumed_bytes,
                    }
            return {
                "body": response_body,
                "headers": response.get("headers", {}),
                "state": "complete",
                "bytes_read": consumed_bytes,
            }
        except (FetchError, http.client.HTTPException, OSError, TimeoutError, urllib.error.URLError) as exc:
            failure = "{}: {}".format(type(exc).__name__, str(exc))
            partial = getattr(exc, "partial", b"")
            attempt_bytes = getattr(exc, "bytes_read", 0)
            if isinstance(partial, bytes):
                attempt_bytes = max(attempt_bytes, len(partial))
            if not isinstance(attempt_bytes, int) or isinstance(attempt_bytes, bool) or attempt_bytes < 0:
                attempt_bytes = 0
            consumed_bytes += min(attempt_bytes, attempt_limit + 1)
            if attempt < MAX_RETRIES and consumed_bytes < byte_limit and _wait_before_retry(sleeper, deadline, monotonic):
                continue
            return {"error": failure, "state": "unavailable", "bytes_read": consumed_bytes}
    return {"error": failure, "state": "unavailable", "bytes_read": consumed_bytes}


def _snapshot_url(source: Dict[str, Any]) -> Optional[str]:
    source_id = source["source_id"]
    repository_path = REPOSITORY_PATHS.get(source_id)
    revision = source.get("last_assessed_revision")
    if repository_path is None or not isinstance(revision, str) or not _REVISION_RE.fullmatch(revision):
        return None
    repository, path = repository_path
    return "https://raw.githubusercontent.com/{}/{}/{}".format(repository, revision, path)


def _bounded_text_diff(old_bytes: bytes, new_bytes: bytes) -> Dict[str, str]:
    if len(old_bytes) > MAX_DIFF_BYTES or len(new_bytes) > MAX_DIFF_BYTES:
        return {"state": "unavailable", "reason": "text diff exceeds the byte limit; digests and affected references are provided"}
    try:
        old_text = old_bytes.decode("utf-8")
        new_text = new_bytes.decode("utf-8")
    except UnicodeDecodeError:
        return {"state": "unavailable", "reason": "source representation is not UTF-8 text"}
    old_lines = old_text.splitlines()
    new_lines = new_text.splitlines()
    if len(old_lines) > MAX_DIFF_LINES or len(new_lines) > MAX_DIFF_LINES:
        return {"state": "unavailable", "reason": "text diff exceeds the line limit; digests and affected references are provided"}
    lines = list(difflib.unified_diff(old_lines, new_lines, fromfile="last-assessed", tofile="candidate", lineterm=""))
    diff_text = "\n".join(lines)
    if len(diff_text) > MAX_DIFF_CHARS:
        diff_text = diff_text[:MAX_DIFF_CHARS] + "\n... diff truncated at the output limit ..."
    return {"state": "available", "format": "unified", "unified_diff": diff_text}


def _wait_before_retry(sleeper: Callable[[float], None], deadline: float, monotonic: Callable[[], float]) -> bool:
    remaining = deadline - monotonic()
    if remaining <= 0:
        return False
    delay = min(RETRY_DELAY_SECONDS, remaining)
    sleeper(delay)
    return deadline - monotonic() > 0


def refresh_registry(
    registry: Dict[str, Any],
    *,
    now: Optional[datetime] = None,
    fetcher: Optional[Callable[..., Dict[str, Any]]] = None,
    monotonic: Optional[Callable[[], float]] = None,
    sleeper: Optional[Callable[[float], None]] = None,
) -> Dict[str, Any]:
    """Fetch approved source paths and report freshness without changing the registry."""
    sources = _validate_registry(registry)
    check_time = now or datetime.now(timezone.utc)
    if check_time.tzinfo is None:
        raise ValueError("now must include a timezone")
    check_time = check_time.astimezone(timezone.utc)
    clock = monotonic or time.monotonic
    wait = sleeper or time.sleep
    retrieve = fetcher or _fetch_url
    deadline = clock() + MAX_TOTAL_SECONDS
    total_bytes = 0
    results = []

    for source in sources:
        source_id = source["source_id"]
        url = source.get("refresh_url")
        if not url:
            results.append(_unavailable(
                source,
                "No complete-byte equivalent automatic source configuration; manual assessment is required.",
                "not_configured",
            ))
            continue

        remaining_total = MAX_TOTAL_BYTES - total_bytes
        source_limit = min(MAX_SOURCE_BYTES, remaining_total)
        if source_limit <= 0:
            results.append(_unavailable(source, "total response-byte budget exhausted"))
            continue

        fetched = _retrieve_complete(
            url,
            byte_limit=source_limit,
            deadline=deadline,
            retrieve=retrieve,
            monotonic=clock,
            sleeper=wait,
        )
        total_bytes += fetched.get("bytes_read", 0)
        if fetched.get("state") != "complete":
            results.append(_unavailable(source, fetched.get("error", "source retrieval failed"), fetched.get("state", "unavailable")))
            continue
        response_body = fetched["body"]

        assessed_digest = _normalize_sha256(source.get("last_assessed_sha256"))
        candidate_digest = hashlib.sha256(response_body).hexdigest()
        result = {
            "source_id": source_id,
            "retrieval_state": "complete",
            "last_assessed": _identity(source),
            "candidate_sha256": candidate_digest,
            "candidate_bytes": len(response_body),
            "candidate_etag": _header(fetched.get("headers", {}), "ETag"),
        }
        if candidate_digest != assessed_digest:
            difference = {"state": "unavailable", "reason": "no complete-byte prior snapshot is configured for a text diff"}
            snapshot_url = _snapshot_url(source)
            remaining_total = MAX_TOTAL_BYTES - total_bytes
            snapshot_limit = min(MAX_SOURCE_BYTES, remaining_total)
            if snapshot_url and snapshot_limit > 0:
                prior = _retrieve_complete(
                    snapshot_url,
                    byte_limit=snapshot_limit,
                    deadline=deadline,
                    retrieve=retrieve,
                    monotonic=clock,
                    sleeper=wait,
                )
                total_bytes += prior.get("bytes_read", 0)
                if prior.get("state") == "complete":
                    prior_digest = hashlib.sha256(prior["body"]).hexdigest()
                    if prior_digest == assessed_digest:
                        difference = _bounded_text_diff(prior["body"], response_body)
                    else:
                        difference = {
                            "state": "unavailable",
                            "reason": "pinned source bytes do not match the recorded last-assessed digest",
                        }
                else:
                    difference = {"state": "unavailable", "reason": prior.get("error", "prior source snapshot retrieval failed")}
            result["difference"] = difference
            result["affected_refs"] = list(source.get("affected_refs", []))
            result.update({
                "status": "review_required",
                "reason": "complete bytes at the relevant source path differ from the last assessed digest; adoption is unchanged",
            })
        else:
            assessed_at = _parse_time(source["last_assessed_at"])
            age = check_time - assessed_at
            if age < timedelta(0):
                results.append(_unavailable(source, "last assessed timestamp is in the future"))
                continue
            window_days = registry.get("assessment_window_days", DEFAULT_ASSESSMENT_WINDOW_DAYS)
            if age > timedelta(days=window_days):
                result.update({
                    "status": "stale",
                    "reason": "source bytes are unchanged, but the {}-day assessment window expired; assessment is due".format(window_days),
                })
            else:
                result.update({
                    "status": "current",
                    "reason": "complete bytes match the recently assessed source; existing disposition is preserved",
                })
        results.append(result)

    return {
        "schema_version": "1.0",
        "checked_at": check_time.isoformat().replace("+00:00", "Z"),
        "assessment_window_days": registry.get("assessment_window_days", DEFAULT_ASSESSMENT_WINDOW_DAYS),
        "limits": {
            "total_deadline_seconds": MAX_TOTAL_SECONDS,
            "request_timeout_seconds": REQUEST_TIMEOUT_SECONDS,
            "maximum_retries": MAX_RETRIES,
            "maximum_source_bytes": MAX_SOURCE_BYTES,
            "maximum_total_bytes": MAX_TOTAL_BYTES,
        },
        "registry_mutated": False,
        "results": results,
    }


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--registry",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "references" / "upstream-guidelines.json",
        help="read-only source registry (default: this skill's maintained registry)",
    )
    parser.add_argument("--source", action="append", help="check one registered source_id; may be repeated")
    args = parser.parse_args(argv)
    try:
        registry = json.loads(args.registry.read_text(encoding="utf-8"))
        all_sources = _validate_registry(registry)
        if args.source:
            by_id = {source["source_id"]: source for source in all_sources}
            missing = [source_id for source_id in args.source if source_id not in by_id]
            if missing:
                raise ValueError("source_id is not registered: {}".format(", ".join(missing)))
            registry = dict(registry)
            registry["sources"] = [by_id[source_id] for source_id in args.source]
        report = refresh_registry(registry)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"schema_version": "1.0", "status": "invalid", "error": str(exc)}, indent=2))
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
