"""Minimal obs-websocket v5 client for driving OBS during demo recording.

The password is read from OBS_WS_PASSWORD. It is deliberately never written to
a file so it cannot end up committed.

    OBS_WS_PASSWORD=... python tools/obs_ctl.py <command> [args]

Commands:
    status                    connection, recording state, output directory
    scenes                    scene and input inventory
    ensure-capture <window>   create/point a Window Capture at a window title
    start                     start recording
    stop                      stop recording, print the output file
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
    ws.send(json.dumps({"op": 6, "d": {
        "requestType": kind, "requestId": rid, "requestData": data or {}}}))
    while True:
        msg = json.loads(ws.recv())
        if msg.get("op") == 7 and msg["d"]["requestId"] == rid:
            status = msg["d"]["requestStatus"]
            if not status["result"]:
                raise SystemExit("%s failed: %s" % (kind, status.get("comment")))
            return msg["d"].get("responseData") or {}


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
        items = request(ws, "GetInputPropertiesListPropertyItems",
                        {"inputName": "Window Capture", "propertyName": "window"})
        for it in items["propertyItems"]:
            print(it["itemValue"])
    elif cmd == "capture":
        # Dedicated scene + input so the user's own scenes are left alone.
        want = sys.argv[2]
        scene, name = "HammerForgeDemo", "HF Capture"
        scenes = [s["sceneName"] for s in request(ws, "GetSceneList")["scenes"]]
        if scene not in scenes:
            request(ws, "CreateScene", {"sceneName": scene})
        inputs = [i["inputName"] for i in request(ws, "GetInputList")["inputs"]]
        if name not in inputs:
            request(ws, "CreateInput", {
                "sceneName": scene, "inputName": name,
                "inputKind": "window_capture",
                "inputSettings": {"method": 2, "cursor": True}})
        items = request(ws, "GetInputPropertiesListPropertyItems",
                        {"inputName": name, "propertyName": "window"})
        match = None
        for it in items["propertyItems"]:
            if want.lower() in str(it["itemValue"]).lower():
                match = it["itemValue"]
                break
        if not match:
            raise SystemExit("no window matching %r" % want)
        request(ws, "SetInputSettings", {
            "inputName": name,
            "inputSettings": {"window": match, "method": 2, "cursor": True},
            "overlay": True})
        request(ws, "SetCurrentProgramScene", {"sceneName": scene})
        print("capturing:", match)
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
