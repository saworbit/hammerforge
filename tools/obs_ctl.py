"""Minimal obs-websocket v5 client for driving OBS during demo recording.

The password is read from OBS_WS_PASSWORD. It is deliberately never written to
a file so it cannot end up committed.

    OBS_WS_PASSWORD=... python tools/obs_ctl.py <command> [args]

Commands:
    status                    connection, recording state, output directory
    scenes                    scene and input inventory
    capture [--scene S] [--index N] <substr>...
                              point scene S's Window Capture at the one
                              window matching every substring, and cut to it
    scene <name>              cut to a scene
    start                     start recording
    stop                      stop recording, print the output file

Diagnostics, for when a capture is not showing what it should:

    windows [scene]           every window OBS can see, in the order capture
                              picks from
    settings [scene]          what OBS resolved for that source, as opposed to
                              what was asked for
    shot <scene> <path>       write a PNG of what the source is capturing now
"""

import base64
import hashlib
import json
import os
import sys
import uuid

import websocket

HOST = os.environ.get("OBS_WS_HOST", "192.168.0.2")
PORT = os.environ.get("OBS_WS_PORT", "4455")
PASSWORD = os.environ.get("OBS_WS_PASSWORD", "")


def connect():
    ws = websocket.create_connection("ws://%s:%s" % (HOST, PORT), timeout=10)
    hello = json.loads(ws.recv())
    ident = {"op": 1, "d": {"rpcVersion": 1}}
    auth = hello.get("d", {}).get("authentication")
    if auth:
        if not PASSWORD:
            raise SystemExit("OBS requires auth but OBS_WS_PASSWORD is not set")
        secret = base64.b64encode(
            hashlib.sha256((PASSWORD + auth["salt"]).encode()).digest()
        )
        ident["d"]["authentication"] = base64.b64encode(
            hashlib.sha256(secret + auth["challenge"].encode()).digest()
        ).decode()
    ws.send(json.dumps(ident))
    reply = json.loads(ws.recv())
    if reply.get("op") != 2:
        raise SystemExit("OBS identify failed: %s" % reply)
    return ws


def request(ws, kind, data=None):
    rid = str(uuid.uuid4())
    ws.send(
        json.dumps(
            {
                "op": 6,
                "d": {"requestType": kind, "requestId": rid, "requestData": data or {}},
            }
        )
    )
    while True:
        msg = json.loads(ws.recv())
        if msg.get("op") == 7 and msg["d"]["requestId"] == rid:
            status = msg["d"]["requestStatus"]
            if not status["result"]:
                raise SystemExit("%s failed: %s" % (kind, status.get("comment")))
            return msg["d"].get("responseData") or {}


def _fit_to_canvas(ws, scene, name):
    """Centre and letterbox the source in the canvas.

    A window capture arrives at the window's native size, so a 1152x648
    playtest window would sit in the top-left corner of a 1920x1080 canvas with
    black around two sides. SCALE_INNER fits it without cropping or distorting.
    """
    item = request(ws, "GetSceneItemId", {"sceneName": scene, "sourceName": name})[
        "sceneItemId"
    ]
    video = request(ws, "GetVideoSettings")
    cw, ch = video["baseWidth"], video["baseHeight"]
    request(
        ws,
        "SetSceneItemTransform",
        {
            "sceneName": scene,
            "sceneItemId": item,
            "sceneItemTransform": {
                "positionX": cw / 2.0,
                "positionY": ch / 2.0,
                "alignment": 0,  # centred on the position, rather than anchored
                "boundsType": "OBS_BOUNDS_SCALE_INNER",
                "boundsAlignment": 0,
                "boundsWidth": float(cw),
                "boundsHeight": float(ch),
            },
        },
    )


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    ws = connect()
    if cmd == "status":
        print("obs:", request(ws, "GetVersion")["obsVersion"])
        rec = request(ws, "GetRecordStatus")
        print("recording:", rec["outputActive"])
        print("record_dir:", request(ws, "GetRecordDirectory")["recordDirectory"])
        print("scene:", request(ws, "GetCurrentProgramScene").get("sceneName"))
    elif cmd == "scenes":
        for s in request(ws, "GetSceneList")["scenes"]:
            print("scene:", s["sceneName"])
        for i in request(ws, "GetInputList")["inputs"]:
            print("input:", i["inputName"], "|", i["inputKind"])
    elif cmd == "windows":
        # Lists what OBS can see, in the order it offers them -- which is the
        # order `capture` picks from when two windows share a title.
        name = sys.argv[2] if len(sys.argv) > 2 else "HF HammerForgeDemo source"
        items = request(
            ws,
            "GetInputPropertiesListPropertyItems",
            {"inputName": name, "propertyName": "window"},
        )
        for it in items["propertyItems"]:
            print(it["itemValue"])
    elif cmd == "capture":
        # Dedicated scene + input so the user's own scenes are left alone.
        # Every argument must appear in the window's "Title:Class:Exe" string.
        # Matching a single loose term such as "Godot Engine" will happily
        # select a different editor instance that happens to be open.
        #
        # --scene names the scene, so one run can hold several: the editor in
        # one and the playtest window the editor spawns in another, cut between
        # mid-take.
        args = sys.argv[2:]
        scene, index = "HammerForgeDemo", 0
        while args and args[0].startswith("--"):
            flag = args.pop(0)
            if flag == "--scene":
                scene = args.pop(0)
            elif flag == "--index":
                index = int(args.pop(0))
            else:
                raise SystemExit("unknown capture flag: %s" % flag)
        wanted = [a.lower() for a in args]
        if not wanted:
            raise SystemExit("capture needs at least one window substring")
        name = "HF %s source" % scene
        scenes = [s["sceneName"] for s in request(ws, "GetSceneList")["scenes"]]
        if scene not in scenes:
            request(ws, "CreateScene", {"sceneName": scene})
        inputs = [i["inputName"] for i in request(ws, "GetInputList")["inputs"]]
        if name not in inputs:
            request(
                ws,
                "CreateInput",
                {
                    "sceneName": scene,
                    "inputName": name,
                    "inputKind": "window_capture",
                    "inputSettings": {"method": 2, "cursor": True},
                },
            )
        items = request(
            ws,
            "GetInputPropertiesListPropertyItems",
            {"inputName": name, "propertyName": "window"},
        )
        # A launched Godot game shows up twice under one identical
        # "title:class:exe" string, and only one of the two survives -- capture
        # the wrong one and the picture goes black a few seconds in. The string
        # cannot tell them apart, so --index picks by position and the last
        # match is the fallback.
        hits = [
            it["itemValue"]
            for it in items["propertyItems"]
            if all(w in str(it["itemValue"]).lower() for w in wanted)
        ]
        if not hits:
            raise SystemExit("no window matching all of %r" % wanted)
        if index >= len(hits):
            print("  only %d match(es); using the last" % len(hits))
            index = len(hits) - 1
        match = hits[index]
        if len(hits) > 1:
            print("  %d identical matches; took #%d" % (len(hits), index))
        request(
            ws,
            "SetInputSettings",
            {
                "inputName": name,
                "inputSettings": {"window": match, "method": 2, "cursor": True},
                "overlay": True,
            },
        )
        _fit_to_canvas(ws, scene, name)
        request(ws, "SetCurrentProgramScene", {"sceneName": scene})
        print("capturing:", match, "in", scene)
    elif cmd == "settings":
        # What OBS resolved, as opposed to what was asked for: a capture method
        # it could not honour is not reported as an error, it just quietly
        # produces black once the window is no longer on top.
        scene = sys.argv[2] if len(sys.argv) > 2 else "HammerForgeDemo"
        got = request(ws, "GetInputSettings", {"inputName": "HF %s source" % scene})
        for k, v in sorted(got.get("inputSettings", {}).items()):
            print("  %s = %r" % (k, v))
    elif cmd == "shot":
        # What OBS actually has hold of, right now. A window capture that has
        # silently re-matched something else looks fine in every log line and
        # only shows up in the picture.
        scene, path = sys.argv[2], sys.argv[3]
        request(
            ws,
            "SaveSourceScreenshot",
            {
                "sourceName": "HF %s source" % scene,
                "imageFormat": "png",
                "imageFilePath": path,
            },
        )
        print("shot:", path)
    elif cmd == "scene":
        request(ws, "SetCurrentProgramScene", {"sceneName": sys.argv[2]})
        print("scene:", sys.argv[2])
    elif cmd == "start":
        request(ws, "StartRecord")
        print("recording started")
    elif cmd == "stop":
        out = request(ws, "StopRecord")
        print("saved:", out.get("outputPath"))
    else:
        raise SystemExit("unknown command: %s" % cmd)
    ws.close()


if __name__ == "__main__":
    main()
