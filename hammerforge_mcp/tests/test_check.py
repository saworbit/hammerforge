import asyncio
import io
import json
import sys
import threading

from hammerforge_mcp.check import run_check
from hammerforge_mcp.discovery import discovery_path

from .conftest import TOKEN, FakeListener, make_project, ok


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
    assert (
        f'claude mcp add hammerforge -- "{sys.executable}" -m hammerforge_mcp' in text
    )
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
