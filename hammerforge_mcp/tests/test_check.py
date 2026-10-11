import asyncio
import io
import json
import shlex
import subprocess
import sys
import threading

from hammerforge_mcp.check import run_check
from hammerforge_mcp.discovery import discovery_path

from .conftest import TOKEN, FakeListener, failed, make_project, ok


def _status(request):
    result = {
        "hammerforge_version": "0.3.2",
        "editor_pid": 4242,
        "target": {
            "target_id": "1:2:3",
            "scene_path": "res://levels/arena.tscn",
            "scene_name": "Arena",
            "level_root_path": "LevelRoot",
        },
        "counts": {"brushes": 12},
        "busy": "",
    }
    return ok(request, result)


class ListenerThread:
    """A fake listener on its own loop, since the check runs its own."""

    def __init__(self, project, responder):
        self.loop = asyncio.new_event_loop()
        self.listener = FakeListener(project, responder)
        self.ready = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        asyncio.set_event_loop(self.loop)
        self.loop.run_until_complete(self.listener.start())
        self.ready.set()
        self.loop.run_forever()

    def __enter__(self):
        self.thread.start()
        self.ready.wait(5)
        return self.listener

    def __exit__(self, *exc):
        asyncio.run_coroutine_threadsafe(self.listener.stop(), self.loop).result(5)
        self.loop.call_soon_threadsafe(self.loop.stop)
        self.thread.join(5)


def _run(project, **kwargs):
    out = io.StringIO()
    code = run_check(project, out=out, **kwargs)
    return code, out.getvalue()


def test_a_connected_editor_is_described(tmp_path):
    project = make_project(tmp_path)
    with ListenerThread(project, _status):
        code, text = _run(project)
    assert code == 0
    assert "HammerForge bridge: connected" in text
    assert "res://levels/arena.tscn" in text
    assert "LevelRoot, revision 5, 12 brushes" in text
    assert "process 4242" in text


def test_the_bridge_off_says_how_to_turn_it_on(tmp_path):
    project = make_project(tmp_path)
    code, text = _run(project)
    assert code == 1
    assert "not reachable" in text
    assert "bridge_off" in text
    assert "Allow agent connections" in text


def test_a_wrong_token_is_named(tmp_path):
    project = make_project(tmp_path)
    with ListenerThread(project, _status):
        file = discovery_path(project)
        file.write_text(file.read_text().replace(TOKEN, "cd" * 32))
        code, text = _run(project)
    assert code == 1
    assert "auth_failed" in text


def test_the_configuration_names_this_python_and_the_project(tmp_path):
    project = make_project(tmp_path)
    with ListenerThread(project, _status):
        _, text = _run(project)
    command = next(line for line in text.splitlines() if "claude mcp add" in line)
    if sys.platform == "win32":
        assert subprocess.list2cmdline([sys.executable]) in command
    else:
        assert shlex.quote(sys.executable) in command
    assert command.strip().startswith("claude mcp add --transport stdio hammerforge --")
    block = text[text.index("{") : text.rindex("}") + 1]
    config = json.loads(block)["mcpServers"]["hammerforge"]
    assert config["command"] == sys.executable
    assert config["args"] == [
        "-m",
        "hammerforge_mcp",
        "--project",
        str(project.resolve()),
    ]
    assert TOKEN not in text, "never the token"


def test_a_discovery_file_elsewhere_goes_into_the_configuration(tmp_path):
    project = make_project(tmp_path)
    elsewhere = tmp_path / "elsewhere.json"
    code, text = _run(project, discovery=elsewhere)
    assert code == 1
    block = text[text.index("{") : text.rindex("}") + 1]
    args = json.loads(block)["mcpServers"]["hammerforge"]["args"]
    assert args[-2:] == ["--discovery", str(elsewhere)]


def test_a_refused_status_is_not_called_connected(tmp_path):
    project = make_project(tmp_path)
    with ListenerThread(project, lambda request: failed(request, "internal_error")):
        code, text = _run(project)
    assert code == 1
    assert "status was refused" in text and "internal_error" in text
    assert "HammerForge bridge: connected\n" not in text


def test_a_folder_that_is_not_a_project_gets_no_configuration(tmp_path):
    code, text = _run(tmp_path)
    assert code == 1
    assert "project.godot" in text
    assert "mcpServers" not in text and "claude mcp add" not in text


def test_a_relative_discovery_path_is_made_absolute(tmp_path, monkeypatch):
    project = make_project(tmp_path)
    monkeypatch.chdir(tmp_path)
    _, text = _run(project, discovery="elsewhere.json")
    block = text[text.index("{") : text.rindex("}") + 1]
    args = json.loads(block)["mcpServers"]["hammerforge"]["args"]
    assert args[-1] == str((tmp_path / "elsewhere.json").resolve())


def test_a_path_with_spaces_and_a_dollar_reads_back_whole(tmp_path):
    from hammerforge_mcp.check import config_lines

    odd = tmp_path / "my game $1"
    command = next(line for line in config_lines(odd, None) if "claude mcp add" in line)
    if sys.platform == "win32":
        assert subprocess.list2cmdline([str(odd)]) in command
    else:
        assert shlex.split(command)[-1] == str(odd)


def _status_for(version):
    def respond(request):
        reply = _status(request)
        reply["result"]["hammerforge_version"] = version
        return reply

    return respond


def test_the_check_names_this_server_s_version(tmp_path):
    from hammerforge_mcp import __version__

    project = make_project(tmp_path)
    with ListenerThread(project, _status):
        _, text = _run(project)
    assert f"server: hammerforge-mcp {__version__}" in text


def test_a_server_for_another_release_says_which_one_to_install(tmp_path):
    # The install line took the server from main whatever addon a user had, and
    # nothing said the two were apart (#1055).
    project = make_project(tmp_path)
    with ListenerThread(project, _status_for("0.3.2")):
        code, text = _run(project)
    assert code == 0, "it still reached the editor"
    assert "not the server for HammerForge 0.3.2" in text
    assert "hammerforge.git@v0.3.2#subdirectory=hammerforge_mcp" in text


def test_a_server_from_the_same_line_says_nothing_more(tmp_path):
    from hammerforge_mcp import __version__

    project = make_project(tmp_path)
    editor = __version__.replace(".dev0", "-dev")
    with ListenerThread(project, _status_for(editor)):
        _, text = _run(project)
    assert "not the server" not in text


def test_the_check_connects_beside_the_agent_rather_than_in_its_place(tmp_path):
    # The listener keeps one agent, so a check that connected as one took the
    # working agent's place (#1060).
    project = make_project(tmp_path)
    with ListenerThread(project, _status) as listener:
        _run(project)
    assert listener.hellos[0].get("role") == "observer"
