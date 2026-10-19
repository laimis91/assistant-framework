#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "Upstream guidance checker reports bounded source freshness without changing adoption"
if PYTHONDONTWRITEBYTECODE=1 python3 -B - "$FRAMEWORK_DIR" <<'PY'
import copy
import hashlib
import importlib.util
import json
import os
import select
import tempfile
import socket
import socketserver
import ssl
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True
repo = Path(sys.argv[1])
skill_root = repo / "skills/assistant-skill-creator"
cache_before = set(skill_root.rglob("__pycache__"))
helper_path = skill_root / "scripts/check-upstream-guidance.py"
spec = importlib.util.spec_from_file_location("creator_upstream_checker", str(helper_path))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

URL = "https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md"
REVISION = "dbd4588f9e1033efb41dad4bef2f7947c8993d44"
OLD = b"# assessed guidance\nKeep rules concise.\n"
NEW = b"# assessed guidance\nKeep rules concise and outcome-shaped.\n"
SHA = lambda body: hashlib.sha256(body).hexdigest()
PINNED_URL = "https://raw.githubusercontent.com/anthropics/skills/{}/skills/skill-creator/SKILL.md".format(REVISION)
NOW = datetime(2026, 10, 13, tzinfo=timezone.utc)

def source(last_assessed_at="2026-10-01T00:00:00+00:00", **overrides):
    item = {
        "source_id": "anthropic:skills/skill-creator/SKILL.md",
        "refresh_url": URL,
        "last_assessed_at": last_assessed_at,
        "last_assessed_revision": REVISION,
        "last_assessed_sha256": "sha256:" + SHA(OLD),
        "disposition": "adapt",
        "disposition_rationale": "Use concise authoring guidance within V1 contract boundaries.",
        "affected_refs": ["SKILL.md#authoring"],
    }
    item.update(overrides)
    return item

def registry(*sources):
    return {"schema_version": "1.0", "assessment_window_days": 30, "sources": list(sources)}

def response(url, body, status=200, headers=None):
    return {"status_code": status, "final_url": url, "headers": headers or {}, "body": body}

def run(check_registry, fetcher, now=NOW, clock=None):
    return module.refresh_registry(
        check_registry,
        now=now,
        fetcher=fetcher,
        monotonic=clock or (lambda: 1.0),
        sleeper=lambda _: None,
    )

def check(label, callback):
    try:
        callback()
        print("ok - " + label)
    except Exception as exc:
        failures.append("{}: {}: {}".format(label, type(exc).__name__, exc))
        print("fail - {}: {}: {}".format(label, type(exc).__name__, exc))

failures = []

def https_handler_keeps_hostname_validation_in_ssl_context():
    handler = module._DeadlineHTTPSHandler(time.monotonic() + 5.0, time.monotonic)
    context = ssl.create_default_context()
    handler._context = context
    assert context.check_hostname is True
    assert context.verify_mode == ssl.CERT_REQUIRED
    if hasattr(handler, "_check_hostname"):
        del handler._check_hostname
    captured = {}

    def do_open(create_connection, request, **kwargs):
        captured.update(kwargs)
        connection = create_connection("example.invalid:443", timeout=2.0, **kwargs)
        try:
            captured["connection_context"] = connection._context
        finally:
            connection.close()
        return {"opened": True}

    handler.do_open = do_open
    result = handler.https_open(module.urllib.request.Request("https://example.invalid/source"))
    assert result == {"opened": True}
    assert captured["context"] is context
    assert captured["connection_context"] is context
    assert "check_hostname" not in captured
    assert context.check_hostname is True
    assert context.verify_mode == ssl.CERT_REQUIRED

check("HTTPS handler uses SSLContext hostname validation without urllib private flags", https_handler_keeps_hostname_validation_in_ssl_context)

def read_yaml(path):
    code = "require 'yaml'; require 'json'; puts JSON.generate(YAML.safe_load(STDIN.read, permitted_classes: [], permitted_symbols: [], aliases: false))"
    result = subprocess.run(["ruby", "-e", code], input=path.read_text(encoding="utf-8"),
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout)

def authoring_freshness_route_is_conditional_and_source_scoped():
    skill_root = repo / "skills/assistant-skill-creator"
    index = read_yaml(skill_root / "contracts/index.yaml")
    inputs = read_yaml(skill_root / "contracts/input.yaml")
    outputs = read_yaml(skill_root / "contracts/output.yaml")
    gates = read_yaml(skill_root / "contracts/phase-gates.yaml")
    condition = "operation in [create, update] and (((authoring is new or materially changed) and a relevant registered assessment has expired) or a relevant source/runtime change is known)"
    authoring_sources = next(field for field in inputs["fields"] if field["name"] == "authoring_guidance_sources")
    assert authoring_sources["type"] == "string[]"
    assert authoring_sources["required"] == "conditional"
    assert authoring_sources["condition"] == condition
    assert authoring_sources["on_missing"] == "infer"
    refresh_scope = next(field for field in inputs["fields"] if field["name"] == "guidance_scope")
    assert refresh_scope["condition"] == "operation == refresh_guidance"
    assert refresh_scope["on_missing"] == "ask", "explicit refresh still asks for missing source scope"
    report = next(item for item in outputs["artifacts"] if item["name"] == "upstream_guidance_assessment")
    assert report["condition"] == "operation == refresh_guidance or (" + condition + ")"
    gate = next(item for item in gates["gates"] if item["phase"] == "CAPTURE")
    freshness_gate = next(item for item in gate["exit_assertions"] if item["id"] == "SC7")
    assert freshness_gate["condition"] == condition
    route = index["load_sets"].get("authoring_freshness")
    assert route is not None, "conditional authoring load set is required"
    assert "references/upstream-guidance.md" in route["references"]
    selectors = route["selectors"]
    assert len(selectors) == 1 and selectors[0]["path"] == "contracts/input.yaml" and "authoring_guidance_sources" in selectors[0]["names"]
    current_phase = index["load_sets"]["current_phase"]["selectors"]
    assert any(item["path"] == "contracts/phase-gates.yaml" and "CAPTURE" in item["allowed_names"] for item in current_phase)
    completion = index["load_sets"]["completion"]["selectors"]
    assert any(item["path"] == "contracts/output.yaml" and "upstream_guidance_assessment" in item["names"] for item in completion)
    root_text = (skill_root / "SKILL.md").read_text(encoding="utf-8").lower()
    assert "authoring_freshness" in root_text and "new/material authoring" in root_text
    assert "known relevant source/runtime change" in root_text and "ask for missing refresh scope" in root_text

check("authoring freshness route is conditional, source-scoped, and keeps explicit refresh clarification", authoring_freshness_route_is_conditional_and_source_scoped)

class LoopbackServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

def start_loopback(handler):
    server = LoopbackServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = "http://127.0.0.1:{}/source".format(server.server_address[1])
    return server, thread, url

def stop_loopback(server, thread):
    server.shutdown()
    server.server_close()
    thread.join(timeout=1)
    assert not thread.is_alive(), "loopback server did not stop"

def unchanged_is_current():
    value = registry(source())
    before = copy.deepcopy(value)
    calls = []
    def fetcher(url, *, timeout_seconds, max_bytes, deadline, monotonic):
        calls.append(url)
        assert url == URL and timeout_seconds > 0 and max_bytes >= len(OLD)
        return response(url, OLD, headers={"X-Repository-Head": "unrelated-new-commit"})
    report = run(value, fetcher)
    result = report["results"][0]
    assert result["status"] == "current", "recently assessed identical official source should be current; observed {!r}".format(result.get("status"))
    assert result["last_assessed"]["last_assessed_sha256"] == "sha256:" + SHA(OLD)
    assert result["last_assessed"]["disposition"] == "adapt"
    assert report["registry_mutated"] is False and value == before
    assert calls == [URL], "an unrelated repository-head change must not trigger another source comparison"

check("unchanged assessed bytes remain current and ignore unrelated repository-head movement", unchanged_is_current)

def changed_requires_review():
    value = registry(source())
    before = copy.deepcopy(value)
    def fetcher(url, **kwargs):
        if url == URL:
            return response(url, NEW)
        if url == PINNED_URL:
            return response(url, OLD)
        raise AssertionError("unexpected source URL: " + url)
    report = run(value, fetcher)
    result = report["results"][0]
    assert result["status"] == "review_required"
    assert result["candidate_sha256"] == SHA(NEW)
    assert result["last_assessed"]["last_assessed_sha256"] == "sha256:" + SHA(OLD)
    assert result["last_assessed"]["disposition"] == "adapt"
    assert result["difference"]["state"] == "available"
    assert "+Keep rules concise and outcome-shaped." in result["difference"]["unified_diff"]
    assert report["registry_mutated"] is False and value == before

check("changed text yields a bounded review delta and preserves adoption", changed_requires_review)

def unchanged_expired_is_stale():
    value = registry(source(last_assessed_at="2026-08-01T00:00:00+00:00"))
    report = run(value, lambda url, **kwargs: response(url, OLD))
    result = report["results"][0]
    assert result["status"] == "stale"
    assert "assessment is due" in result["reason"]
    assert result["last_assessed"]["last_assessed_at"] == "2026-08-01T00:00:00+00:00"

check("unchanged bytes outside the assessment window remain stale", unchanged_expired_is_stale)

def transient_failure_can_recover():
    attempts = []
    def fetcher(url, **kwargs):
        attempts.append(url)
        if len(attempts) == 1:
            raise OSError("temporary transport interruption")
        return response(url, OLD)
    report = run(registry(source()), fetcher)
    assert report["results"][0]["status"] == "current"
    assert len(attempts) == 2 and len(attempts) <= module.MAX_RETRIES + 1

check("bounded retry can recover with a complete source response", transient_failure_can_recover)

def failed_recovery_preserves_assessed_identity():
    value = registry(source())
    before = copy.deepcopy(value)
    attempts = []
    def fetcher(url, **kwargs):
        attempts.append(url)
        raise OSError("source unavailable")
    report = run(value, fetcher)
    result = report["results"][0]
    assert result["status"] == "unavailable"
    assert result["last_assessed"]["last_assessed_sha256"] == "sha256:" + SHA(OLD)
    assert result["last_assessed"]["disposition"] == "adapt"
    assert len(attempts) == module.MAX_RETRIES + 1
    assert report["registry_mutated"] is False and value == before

check("failed recovery preserves the last successful digest and disposition", failed_recovery_preserves_assessed_identity)

def partial_and_inaccessible_responses_are_not_current():
    partial = run(registry(source()), lambda url, **kwargs: response(url, OLD[:10], status=206))
    assert partial["results"][0]["status"] == "unavailable"
    assert partial["results"][0]["retrieval_state"] == "partial"
    inaccessible = run(registry(source()), lambda url, **kwargs: response(url, b"", status=404))
    assert inaccessible["results"][0]["status"] == "unavailable"
    assert inaccessible["results"][0]["last_assessed"]["last_assessed_sha256"] == "sha256:" + SHA(OLD)

check("partial and inaccessible responses preserve the prior source identity", partial_and_inaccessible_responses_are_not_current)

def redirect_truncation_and_oversize_are_rejected():
    redirected = run(registry(source()), lambda url, **kwargs: response("https://example.invalid/other", OLD))
    assert redirected["results"][0]["status"] == "unavailable"
    truncated = run(registry(source()), lambda url, **kwargs: response(url, OLD, headers={"Content-Length": str(len(OLD) + 4)}))
    assert truncated["results"][0]["retrieval_state"] == "partial"
    oversized = b"x" * (module.MAX_SOURCE_BYTES + 1)
    too_large = run(registry(source()), lambda url, **kwargs: response(url, oversized))
    assert too_large["results"][0]["retrieval_state"] == "partial"

check("redirect, truncated, and oversized responses fail closed", redirect_truncation_and_oversize_are_rejected)

def total_deadline_stops_before_fetch():
    calls = []
    times = iter([0.0, module.MAX_TOTAL_SECONDS + 1.0])
    report = run(registry(source()), lambda url, **kwargs: calls.append(url), clock=lambda: next(times))
    assert calls == []
    assert report["results"][0]["status"] == "unavailable"
    assert "deadline" in report["results"][0]["reason"]

check("total deadline is enforced before an additional source request", total_deadline_stops_before_fetch)

def unsupported_source_configuration_is_rejected_without_fetch():
    value = registry(source(refresh_url="https://example.invalid/skill.md"))
    calls = []
    try:
        run(value, lambda url, **kwargs: calls.append(url))
    except ValueError as exc:
        assert "unsupported refresh URL" in str(exc)
    else:
        raise AssertionError("unsupported refresh URL was accepted")
    assert calls == []

check("unsupported source URLs are rejected before network access", unsupported_source_configuration_is_rejected_without_fetch)

def total_response_byte_budget_is_shared_across_sources():
    body = b"x" * module.MAX_SOURCE_BYTES
    records = []
    for source_id, (repository, path) in list(module.REPOSITORY_PATHS.items())[:5]:
        url = "https://raw.githubusercontent.com/{}/main/{}".format(repository, path)
        records.append(source(
            source_id=source_id,
            refresh_url=url,
            last_assessed_sha256=SHA(body),
            last_assessed_at="2026-10-01T00:00:00+00:00",
        ))
    calls = []
    report = run(registry(*records), lambda url, **kwargs: (calls.append(url) or response(url, body)))
    assert len(calls) == module.MAX_TOTAL_BYTES // module.MAX_SOURCE_BYTES
    assert report["results"][-1]["status"] == "unavailable"
    assert "byte budget" in report["results"][-1]["reason"]

check("total response-byte budget is shared across source requests", total_response_byte_budget_is_shared_across_sources)

def failed_attempt_bytes_consume_shared_budget():
    records = []
    for source_id, (repository, path) in list(module.REPOSITORY_PATHS.items())[:7]:
        url = "https://raw.githubusercontent.com/{}/main/{}".format(repository, path)
        records.append(source(
            source_id=source_id,
            refresh_url=url,
            last_assessed_sha256="sha256:" + SHA(OLD),
        ))
    calls = []
    def fetcher(url, *, timeout_seconds, max_bytes, deadline, monotonic):
        calls.append((url, max_bytes))
        error = module.FetchError("connection reset after partial body")
        error.bytes_read = min(100000, max_bytes)
        raise error
    report = run(registry(*records), fetcher)
    assert len(calls) == 11, "partial failed attempts must exhaust the shared cap before source seven"
    assert calls[0][1] == module.MAX_SOURCE_BYTES
    assert calls[1][1] == module.MAX_SOURCE_BYTES - 100000, "retry must receive only the unconsumed source allowance"
    assert calls[-1][1] == module.MAX_TOTAL_BYTES - 5 * 200000
    assert "main/" + list(module.REPOSITORY_PATHS.items())[5][1][1] in calls[-1][0]
    assert report["results"][-1]["status"] == "unavailable"
    assert "byte budget" in report["results"][-1]["reason"]

check("partial failed attempts consume the cumulative shared byte budget", failed_attempt_bytes_consume_shared_budget)

def truncated_chunked_response_is_structured_and_counted():
    requests = []
    class TruncatedChunkHandler(socketserver.BaseRequestHandler):
        def handle(self):
            request = b""
            while b"\r\n\r\n" not in request:
                chunk = self.request.recv(4096)
                if not chunk:
                    return
                request += chunk
            requests.append(True)
            self.request.sendall(
                b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                b"5\r\nhello\r\n"
            )
    server, thread, url = start_loopback(TruncatedChunkHandler)
    try:
        deadline = time.monotonic() + 3.0
        result = module._retrieve_complete(
            url,
            byte_limit=100,
            deadline=deadline,
            retrieve=module._fetch_url,
            monotonic=time.monotonic,
            sleeper=lambda _: None,
        )
        assert result["state"] == "unavailable"
        assert result["bytes_read"] == 10, "both truncated attempts' delivered bytes must be retained"
        assert "IncompleteRead" in result["error"], "framing failure must remain structured and identifiable"
        assert len(requests) == module.MAX_RETRIES + 1
    finally:
        stop_loopback(server, thread)

check("truncated chunked HTTP framing returns structured failure with delivered bytes", truncated_chunked_response_is_structured_and_counted)

def slow_headers_stop_at_the_absolute_deadline():
    header_complete = threading.Event()
    client_closed_before_header = threading.Event()
    class SlowHeaderHandler(socketserver.BaseRequestHandler):
        def handle(self):
            request = b""
            try:
                while b"\r\n\r\n" not in request:
                    chunk = self.request.recv(4096)
                    if not chunk:
                        return
                    request += chunk
                self.request.sendall(b"HTTP/1.1 200 OK\r\nX-Slow: ")
                for _ in range(24):
                    self.request.sendall(b"x")
                    readable, _, _ = select.select([self.request], [], [], 0)
                    if readable and self.request.recv(1, socket.MSG_PEEK) == b"":
                        client_closed_before_header.set()
                        return
                    time.sleep(0.02)
                self.request.sendall(b"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                header_complete.set()
                if self.request.recv(1) == b"":
                    client_closed_before_header.set()
            except OSError:
                client_closed_before_header.set()
    server, thread, url = start_loopback(SlowHeaderHandler)
    try:
        started = time.monotonic()
        result = module._retrieve_complete(
            url,
            byte_limit=100,
            deadline=started + 0.1,
            retrieve=module._fetch_url,
            monotonic=time.monotonic,
            sleeper=lambda _: None,
        )
        elapsed = time.monotonic() - started
        assert result["state"] == "unavailable"
        assert elapsed < 0.3, "HTTP header reads must be cancelled at the absolute deadline"
        assert client_closed_before_header.wait(0.2), "timed-out request must close while the server is still sending headers"
        assert not header_complete.is_set(), "server completed all slow headers after the retrieval returned"
    finally:
        stop_loopback(server, thread)

check("slow HTTP headers stop at the absolute deadline and close the active request", slow_headers_stop_at_the_absolute_deadline)

def hostname_request_uses_the_real_python_dns_child():
    original_getproxies = module.urllib.request.getproxies
    original_popen = module.subprocess.Popen
    original_executable = sys.executable
    resolver_commands = []
    request_received = threading.Event()

    class HostnameHandler(socketserver.BaseRequestHandler):
        def handle(self):
            request = bytearray()
            while b"\r\n\r\n" not in request:
                chunk = self.request.recv(4096)
                if not chunk:
                    return
                request.extend(chunk)
            request_received.set()
            self.request.sendall(
                b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
            )

    def record_popen(arguments, *args, **kwargs):
        resolver_commands.append(list(arguments))
        return original_popen(arguments, *args, **kwargs)

    server, thread, _ = start_loopback(HostnameHandler)
    module.urllib.request.getproxies = lambda: {}
    module.subprocess.Popen = record_popen
    url = "http://localhost:{}/source".format(server.server_address[1])
    try:
        started = time.monotonic()
        result = module._fetch_url(
            url,
            timeout_seconds=2.0,
            max_bytes=100,
            deadline=started + 2.0,
            monotonic=time.monotonic,
        )
        assert result["status_code"] == 200
        assert result["final_url"] == url
        assert result["body"] == b"ok"
        assert request_received.is_set(), "localhost server did not receive the request"
        assert len(resolver_commands) == 1, "hostname lookup must run in exactly one DNS child"
        assert resolver_commands[0][0] == original_executable, "DNS child must use the active Python executable"
        assert resolver_commands[0][1] == "-c"
        assert resolver_commands[0][3] == "localhost"
    finally:
        module.urllib.request.getproxies = original_getproxies
        module.subprocess.Popen = original_popen
        stop_loopback(server, thread)

check("localhost HTTP request succeeds through the real Python DNS child", hostname_request_uses_the_real_python_dns_child)

def slow_dns_resolution_is_cancelled_at_the_absolute_deadline():
    original_getaddrinfo = socket.getaddrinfo
    original_getproxies = module.urllib.request.getproxies
    original_executable = sys.executable
    original_pid_file = os.environ.get("P0P4_DNS_TEST_PID_FILE")
    with tempfile.TemporaryDirectory() as directory:
        pid_file = Path(directory) / "resolver.pid"
        resolver = Path(directory) / "slow-resolver"
        resolver.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$$\" > \"$P0P4_DNS_TEST_PID_FILE\"\n"
            "exec sleep 5\n",
            encoding="utf-8",
        )
        resolver.chmod(0o700)

        def slow_getaddrinfo(host, port, *args, **kwargs):
            if host == "slow-dns.invalid":
                time.sleep(0.6)
                raise socket.gaierror("simulated slow DNS")
            return original_getaddrinfo(host, port, *args, **kwargs)

        socket.getaddrinfo = slow_getaddrinfo
        module.urllib.request.getproxies = lambda: {}
        sys.executable = str(resolver)
        os.environ["P0P4_DNS_TEST_PID_FILE"] = str(pid_file)
        try:
            started = time.monotonic()
            result = module._retrieve_complete(
                "http://slow-dns.invalid/source",
                byte_limit=100,
                deadline=started + 0.25,
                retrieve=module._fetch_url,
                monotonic=time.monotonic,
                sleeper=lambda _: None,
            )
            elapsed = time.monotonic() - started
            assert result["state"] == "unavailable"
            assert elapsed < 0.45, "slow DNS must stop at the 250ms deadline; observed {:.3f}s".format(elapsed)
            assert "deadline" in result["error"]
            assert pid_file.exists(), "DNS resolver subprocess did not start: {!r}".format(result)
            resolver_pid = int(pid_file.read_text(encoding="utf-8").strip())
            try:
                os.kill(resolver_pid, 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError("timed-out DNS resolver process remains alive")
        finally:
            socket.getaddrinfo = original_getaddrinfo
            module.urllib.request.getproxies = original_getproxies
            sys.executable = original_executable
            if original_pid_file is None:
                os.environ.pop("P0P4_DNS_TEST_PID_FILE", None)
            else:
                os.environ["P0P4_DNS_TEST_PID_FILE"] = original_pid_file
            if pid_file.exists():
                try:
                    resolver_pid = int(pid_file.read_text(encoding="utf-8").strip())
                    os.kill(resolver_pid, 0)
                except (ProcessLookupError, ValueError):
                    pass
                else:
                    os.kill(resolver_pid, 9)

check("slow DNS resolution is cancelled and reaped at the absolute deadline", slow_dns_resolution_is_cancelled_at_the_absolute_deadline)

def slow_response_body_respects_the_per_request_deadline():
    body_complete = threading.Event()
    client_closed_before_body = threading.Event()
    class SlowBodyHandler(socketserver.BaseRequestHandler):
        def handle(self):
            request = bytearray()
            try:
                while b"\r\n\r\n" not in request:
                    chunk = self.request.recv(4096)
                    if not chunk:
                        return
                    request.extend(chunk)
                self.request.sendall(
                    b"HTTP/1.1 200 OK\r\nContent-Length: 24\r\nConnection: close\r\n\r\n"
                )
                for _ in range(24):
                    self.request.sendall(b"x")
                    readable, _, _ = select.select([self.request], [], [], 0)
                    if readable and self.request.recv(1, socket.MSG_PEEK) == b"":
                        client_closed_before_body.set()
                        return
                    time.sleep(0.02)
                body_complete.set()
                if self.request.recv(1) == b"":
                    client_closed_before_body.set()
            except OSError:
                client_closed_before_body.set()

    server, thread, url = start_loopback(SlowBodyHandler)
    try:
        started = time.monotonic()
        failure = None
        try:
            module._fetch_url(
                url,
                timeout_seconds=0.05,
                max_bytes=100,
                deadline=started + 1.0,
                monotonic=time.monotonic,
            )
        except module.FetchError as exc:
            failure = exc
        elapsed = time.monotonic() - started
        assert elapsed < 0.3, "50ms request timeout must cap cumulative body reads; observed {:.3f}s".format(elapsed)
        assert failure is not None, "slow response body completed despite the shorter request deadline"
        assert failure.bytes_read > 0, "bytes delivered before request timeout should remain counted"
        assert client_closed_before_body.wait(0.2), "timed-out request must close during the body stream"
        assert not body_complete.is_set(), "server completed the body after the request deadline"
    finally:
        stop_loopback(server, thread)

check("per-request deadline caps cumulative body reads under the invocation deadline", slow_response_body_respects_the_per_request_deadline)

def registry_preserves_exact_preparation_identity():
    current = json.loads((skill_root / "references/upstream-guidelines.json").read_text(encoding="utf-8"))
    manifest = json.loads((repo / "docs/plans/assistant-skill-creator-refresh/source-manifest.json").read_text(encoding="utf-8"))
    assert current["schema_version"] == "1.0"
    assert current["assessment_window_days"] == 30
    records = {item["source_id"]: item for item in current["sources"]}
    expected = {item["id"] for item in manifest["sources"]}
    assert set(records) == expected
    for item in manifest["sources"]:
        registered = records[item["id"]]
        assert registered["last_assessed_sha256"] == item.get("sha256")
        assert registered["last_assessed_revision"] == item.get("commit")
    installed = records["openai-installed-creator"]
    assert installed["source_kind"] == "installed_snapshot"
    assert installed["official_locator"] is None and installed["last_assessed_revision"] is None
    assert installed["last_assessed_sha256"] is not None
    manual_docs = [records[source_id] for source_id in ("openai-skills-docs", "openai-skill-evals", "anthropic-authoring", "anthropic-release")]
    assert all(item["refresh_url"] is None for item in manual_docs)
    assert all("representation" in " ".join(item["limitations"]).lower() for item in manual_docs)
    module._validate_registry(current)

check("registry binds all prepared sources and marks non-equivalent documentation honestly", registry_preserves_exact_preparation_identity)

cache_after = set(skill_root.rglob("__pycache__"))
assert cache_after <= cache_before, "test import created source-tree __pycache__"
if failures:
    raise SystemExit("{} upstream freshness assertion(s) failed".format(len(failures)))
print("all upstream freshness assertions passed")
PY
then
    pass
else
    fail "one or more deterministic freshness assertions failed"
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
