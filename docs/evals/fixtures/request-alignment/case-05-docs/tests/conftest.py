import shutil
import subprocess

import pytest


def _docker_available():
    if shutil.which("docker") is None:
        return False
    return subprocess.run(["docker", "info"], capture_output=True).returncode == 0


def pytest_collection_modifyitems(config, items):
    if _docker_available():
        return
    skip = pytest.mark.skip(reason="Docker daemon not available")
    for item in items:
        if "integration" in item.keywords:
            item.add_marker(skip)
