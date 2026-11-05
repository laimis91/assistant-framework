#!/usr/bin/env bash
# Offline tests for the skill-activation scorer and plugin generator. No model calls.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$REPO_ROOT/tools/evals/skill-activation/test_skill_activation.py"
