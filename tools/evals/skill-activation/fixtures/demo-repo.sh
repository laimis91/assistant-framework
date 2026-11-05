#!/usr/bin/env bash
# Synthetic repository for skill-activation trials. It writes only inside the run's empty workspace.
set -e
# Real git configuration could carry hooks into a trial (R-RUN-2).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p src tests tools docs/specs docs/plans docs/decisions tickets tasks .github/workflows \
    skills/assistant-demo/evals skills/assistant-demo/contracts

cat > README.md <<'EOF'
# Demo service and skill framework

A small signup and sync service, with one framework skill under `skills/`.
Run tests with `python -m pytest -q`. Validate skills with `tools/validate-skills.sh`.
EOF

cat > BACKLOG.md <<'EOF'
# Backlog

- B-12: add an export format option to the report command.
- B-13: idea, retire the legacy sync mode once nobody uses it.
EOF

cat > src/signup.py <<'EOF'
def validate_signup(form):
    errors = []
    if not form.get("name"):
        errors.append("name is required")
    return errors
EOF

cat > src/sync_job.py <<'EOF'
def run_sync(fetch, max_items):
    items = []
    attempts = 0
    while len(items) < max_items:
        attempts += 1
        try:
            items.extend(fetch(len(items)))
        except IOError:
            continue
    return items[: max_items - 1]
EOF

cat > src/auth.py <<'EOF'
API_TOKEN = "demo-token"


def check_token(token):
    return token == API_TOKEN
EOF

cat > src/upload.py <<'EOF'
def save_upload(name, data):
    with open("/var/data/uploads/" + name, "wb") as handle:
        handle.write(data)
EOF

cat > src/report.py <<'EOF'
def render_report(rows):
    return "\n".join(",".join(str(value) for value in row) for row in rows)
EOF

cat > tests/test_signup.py <<'EOF'
# Cheks the required name.
from src.signup import validate_signup


def test_name_required():
    assert validate_signup({}) == ["name is required"]
EOF

cat > tests/test_sync.py <<'EOF'
from src.sync_job import run_sync


def test_returns_all_items():
    assert run_sync(lambda offset: [offset], 3) == [0, 1, 2]
EOF

cat > tests/test_report.py <<'EOF'
import time

from src.report import render_report


def test_render_is_fast():
    start = time.time()
    render_report([[1, 2]])
    assert time.time() - start >= 0
EOF

cat > .github/workflows/ci.yml <<'EOF'
name: ci
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: python -m pytest -q tests/test_signup.py || true
EOF

cat > ci-log-latest.txt <<'EOF'
FAILED tests/test_sync.py::test_returns_all_items
E   assert [0, 1] == [0, 1, 2]
1 failed, 2 passed
EOF

cat > docs/specs/export.md <<'EOF'
# Report export

The report command gains a `--format` option that accepts csv and json.
Unknown formats exit with status 2. Output goes to standard output.
EOF

cat > docs/plans/export-plan.md <<'EOF'
# Export plan

1. Add a format argument to `render_report`.
2. Add json output.
3. Add tests for both formats and for an unknown format.
EOF

cat > docs/decisions/cache.md <<'EOF'
# Cache decision, open

Reports are slow to build. Options: keep them in process memory, or in a shared Redis instance.
EOF

cat > tickets/PROJ-142.md <<'EOF'
# PROJ-142 Export reports

As a user I want to export reports so that I can use them elsewhere.
Acceptance: it works.
EOF

cat > skills/assistant-demo/SKILL.md <<'EOF'
---
name: assistant-demo
description: Formats demo reports. Use for explicit demo report requests.
---

# Demo reports

Read the report rows and format them as a table. Report any row that cannot be formatted.
EOF

cat > skills/assistant-demo/contracts/output.yaml <<'EOF'
contract: demo_output
fields:
  - name: table
    required: true
EOF

cat > skills/assistant-demo/evals/cases.json <<'EOF'
{"activation_cases": [{"user_request": "Format this demo report.", "should_activate": true}]}
EOF

cat > tools/validate-skills.sh <<'EOF'
#!/usr/bin/env bash
test -f skills/assistant-demo/SKILL.md
EOF

cat > docs/specs/sync.md <<'EOF'
# Sync

run_sync returns at most max_items - 1 items.
EOF

chmod +x tools/validate-skills.sh
git init -q
git add -A
git -c user.name=fixture -c user.email=fixture@example.invalid commit -qm "Initial demo repository"

# One uncommitted change, for turns that deliver work that never went through a process.
cat >> src/report.py <<'EOF'


def report_title(name):
    return name.strip().title()
EOF
