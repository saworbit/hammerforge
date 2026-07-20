# HammerForge Install + Upgrade

Last updated: July 21, 2026

This guide covers installing, upgrading, and recovering HammerForge for Godot 4.7+ and configuring the project-scoped Godot MCP used by contributors to this repository.

## Requirements

- Godot Engine 4.7 stable or newer.
- A 3D scene in your project to host `LevelRoot`.

## Install HammerForge

1. Copy `addons/hammerforge` into your project.
2. Enable **HammerForge** in **Project → Project Settings → Plugins**.
3. Open any 3D scene. In the empty-state banner, choose **Create Starter** for a floor, sunlight, and player spawn, or **Create Empty** for only `LevelRoot`.
4. Verify the dock shows **Build**, **Paint**, **Objects**, and **Test**, with **Draw**, **Select**, **Paint**, **More**, and **Help** in the primary toolbar.
5. Draw a brush, then use **Test → Test Level (Bake + Play)** to verify the complete workflow.

An intentional left-click with Draw active can create an empty root. Camera navigation, right-clicks, and other passive viewport input do not modify the scene.

## Upgrade

1. Close Godot.
2. Back up your project, including `.hflevel` and `.hfprefab` files.
3. Replace the existing `addons/hammerforge` folder with the new version.
4. Reopen the project and re-enable the plugin if prompted.
5. Open a level and run **Test → Check Only**, followed by **Test Level**, to verify validation, bake, and play.

## Project-Scoped Godot MCP (Repository Contributors)

This repository vendors the Godot MCP addon in `addons/godot_mcp` and enables it in `project.godot`. The server binds to loopback port `9080`, rejects unauthenticated requests, and does not allow remote clients. Codex client state under `.codex/` is deliberately ignored so machine-specific settings never enter version control.

The authentication token is local user state. Never place it in `.codex/config.toml`, documentation, a shell script, or any committed file.

1. In Godot, open the Godot MCP panel and ensure the server is running on `127.0.0.1:9080` with authentication enabled.
2. Create a local `.codex/config.toml` with the following client definition:

   ```toml
   [mcp_servers.godot_mcp]
   enabled = true
   required = false
   url = "http://127.0.0.1:9080/mcp"
   bearer_token_env_var = "HAMMERFORGE_GODOT_MCP_TOKEN"
   startup_timeout_sec = 15.0
   tool_timeout_sec = 300.0
   ```

3. Copy the configured token into a user-scoped environment variable from PowerShell:

   ```powershell
   [Environment]::SetEnvironmentVariable("HAMMERFORGE_GODOT_MCP_TOKEN", "<same token configured in Godot MCP>", "User")
   ```

4. Restart Codex so it inherits the new environment variable.
5. Confirm the project MCP client connects. A request without the token should return HTTP 401; an authenticated MCP `initialize` request should succeed.

Godot stores MCP preferences and verification state under `user://`; these files and screenshots are intentionally ignored at the repository root. If port `9080` is already occupied, stop the other Godot MCP instance or assign a different port consistently in both Godot and your local client configuration.

## Cache Reset (Recovery)

If the plugin fails to load, the dock is missing, or tools behave incorrectly:

1. Close Godot.
2. Delete the project cache folder `.godot/editor`.
3. Reopen the project and enable the plugin again.
4. If resources still look stale, delete `.godot/imported` and reopen.

For MCP connection failures, first confirm that Godot is still open, the server reports port `9080`, and `HAMMERFORGE_GODOT_MCP_TOKEN` is present in the process environment. Do not disable authentication as a workaround.

## Compatibility Notes

- HammerForge targets Godot 4.7+.
- New `.hflevel` fields are backward compatible; missing keys fall back to defaults.
- `.glb` export requires a successful bake first.
- The vendored MCP addon is development tooling and is not required when distributing a game built with HammerForge.

## Migration Checklist

1. Back up the project and authored level/prefab files.
2. Open a level and run **Test → Check Only**; apply offered fixes deliberately.
3. Save the level to persist newly introduced fields.
4. Run **Bake Only** and **Test Level** to confirm geometry and runtime behavior.
5. Export a `.glb` if your downstream pipeline depends on it.
