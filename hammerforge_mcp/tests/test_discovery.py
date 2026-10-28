import json
import os
import subprocess
import sys

import pytest

from hammerforge_mcp.discovery import (
    DiscoveryError,
    discovery_path,
    pid_alive,
    read_discovery,
)

from .conftest import TOKEN, make_project, write_discovery


def test_a_folder_without_project_godot(tmp_path):
    with pytest.raises(DiscoveryError, match=r"no project\.godot"):
        read_discovery(tmp_path)


def test_no_file_says_how_to_turn_the_bridge_on(tmp_path):
    project = make_project(tmp_path)
    with pytest.raises(DiscoveryError, match="Allow agent connections"):
        read_discovery(project)


def test_a_good_file(tmp_path):
    project = make_project(tmp_path)
    write_discovery(project, 4321)
    found = read_discovery(project)
    assert found.port == 4321
    assert found.token == TOKEN
    assert found.pid == os.getpid()
    assert found.bridge_version == 1


def test_godot_writes_whole_numbers_as_floats(tmp_path):
    project = make_project(tmp_path)
    write_discovery(project, 4321)
    path = discovery_path(project)
    data = json.loads(path.read_text(encoding="utf-8"))
    data["port"] = 4321.0
    path.write_text(json.dumps(data), encoding="utf-8")
    assert read_discovery(project).port == 4321


def test_a_dead_pid_says_the_editor_exited(tmp_path):
    project = make_project(tmp_path)
    child = subprocess.run(
        [sys.executable, "-c", "import os; print(os.getpid())"],
        capture_output=True,
        text=True,
        check=True,
    )
    write_discovery(project, 4321, pid=int(child.stdout))
    with pytest.raises(DiscoveryError, match="has exited"):
        read_discovery(project)
    assert read_discovery(project, check_pid=False).port == 4321


def test_a_broken_file(tmp_path):
    project = make_project(tmp_path)
    discovery_path(project).write_text("{half", encoding="utf-8")
    with pytest.raises(DiscoveryError, match="could not be read"):
        read_discovery(project)


def test_pid_alive():
    assert pid_alive(os.getpid())
    assert not pid_alive(0)


def test_the_token_is_not_in_repr(tmp_path):
    project = make_project(tmp_path)
    write_discovery(project, 4321)
    assert TOKEN not in repr(read_discovery(project))


def test_the_file_sits_in_its_own_folder(tmp_path):
    assert discovery_path(tmp_path).parent.name == "hammerforge_mcp"
    assert discovery_path(tmp_path).parent.parent.name == ".godot"


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("port", 0),
        ("port", -1),
        ("port", 65536),
        ("port", True),
        ("pid", -1),
        ("pid", 0),
        ("pid", 1 << 64),
        ("bridge_version", 0),
        ("port", float("inf")),
        ("pid", float("inf")),
        ("port", float("nan")),
    ],
)
def test_invalid_discovery_numbers_are_actionable_errors(tmp_path, key, value):
    project = make_project(tmp_path)
    write_discovery(project, 4321)
    path = discovery_path(project)
    data = json.loads(path.read_text(encoding="utf-8"))
    data[key] = value
    path.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(DiscoveryError, match="Untick and tick") as caught:
        read_discovery(project)
    assert TOKEN not in str(caught.value)


def test_invalid_utf8_discovery_is_an_actionable_error(tmp_path):
    project = make_project(tmp_path)
    discovery_path(project).write_bytes(b"\xff")
    with pytest.raises(DiscoveryError, match="Untick and tick"):
        read_discovery(project)


def test_unreadable_discovery_is_an_actionable_error(tmp_path, monkeypatch):
    from pathlib import Path

    project = make_project(tmp_path)

    def denied(*args, **kwargs):
        raise PermissionError("access denied")

    monkeypatch.setattr(Path, "read_text", denied)
    with pytest.raises(DiscoveryError, match="access denied"):
        read_discovery(project)
