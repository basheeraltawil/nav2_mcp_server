# Nav2 MCP Server on TIAGo (ROS 2 Humble)

This guide walks you through running the Nav2 MCP Server against a **PAL Robotics
TIAGo** robot driven by **ROS 2 Humble**, and connecting it to three different
kinds of LLM front-end:

1. **Local** — Claude Desktop / Cursor / VS Code (stdio)
2. **GitHub Copilot** — VS Code agent mode (MCP)
3. **Offline / local LLMs** — Llama (and friends) via Ollama

> TL;DR of the Humble adaptation baked into this repo:
> - Default robot base frame is `base_footprint` (TIAGo), overridable with `BASE_FRAME`.
> - Default map frame is `map`, overridable with `MAP_FRAME`.
> - Python floor lowered to **3.10** (Humble ships on Ubuntu 22.04 / Python 3.10).
> - The `Dockerfile` is based on `ros:humble-ros-base`.
> - Nav2 **docking** (`dock_robot`/`undock_robot`) is **auto-detected**: `opennav_docking`
>   only exists on ROS 2 Jazzy+, so on Humble the dock tools return a clear
>   `FEATURE_NOT_SUPPORTED` error instead of crashing. Set `ENABLE_DOCKING=0` to
>   hard-disable them entirely. Everything else works on Humble.

---

## 0. How it fits together

```
LLM front-end (Claude / Copilot / Ollama+Llama)
      |  MCP (stdio/http)
      v
nav2_mcp_server  (this repo: rclpy + Nav2 API)
      |  ROS 2 DDS (same ROS_DOMAIN_ID)  -- /tf, actions
      v
TIAGo Nav2 stack
```

The MCP server is a **ROS 2 node**. It must run somewhere that can reach TIAGo's
DDS traffic: either **on the robot**, or on a workstation on the **same network
and `ROS_DOMAIN_ID`** as the robot.

---

## 1. Prerequisites

- A TIAGo (real or Gazebo sim) running **ROS 2 Humble** with the **Nav2** stack
  launched and its lifecycle **active**.
- Network reachability between the machine that will run this server and the robot:
  - same `ROS_DOMAIN_ID`
  - same DDS discovery domain (same LAN, or a configured discovery server)
- One of:
  - **Native**: Ubuntu 22.04 + ROS 2 Humble + `nav2_simple_commander` installed, **or**
  - **Docker** (the included image bundles the ROS 2 Humble deps).

Confirm the robot's frames and domain first (run on the robot or a sourced terminal):

```bash
echo $ROS_DOMAIN_ID
ros2 topic list | grep -E "/tf|/navigate_to_pose"
ros2 run tf2_ros tf2_echo map base_footprint
```

If `tf2_echo map base_footprint` prints a transform, you're good. If your TIAGo
uses a different base frame, note it for `BASE_FRAME` below.

---

## 2. Install the server

You only need **one** of the following (native or Docker).

### Option A — Native (recommended when running *on* the robot)

ROS 2 Python packages (`rclpy`, `nav2_simple_commander`, `tf2_ros`) come from your
ROS install, **not** from PyPI. So the virtualenv must be allowed to see the
system site-packages.

```bash
sudo apt update
sudo apt install -y \
  ros-humble-nav2-simple-commander \
  ros-humble-tf2-ros-py \
  ros-humble-nav2-msgs \
  python3-venv

git clone https://github.com/basheeraltawil/nav2_mcp_server.git
cd nav2_mcp_server

source /opt/ros/humble/setup.bash
python3 -m venv --system-site-packages .venv
source .venv/bin/activate

pip install -e .

cp .env.example .env        # edit ROS_DOMAIN_ID / BASE_FRAME as needed
python -m nav2_mcp_server    # or: nav2-mcp-server
```

> Using `uv`? Do `uv venv --system-site-packages .venv` first so the ROS Python
> packages remain importable, then `uv pip install -e .`. A plain `uv sync` creates
> an isolated venv that **cannot** import `rclpy`.

### Option B — Docker

The image is based on `ros:humble-ros-base` and installs the Nav2 Humble debs.

```bash
git clone https://github.com/basheeraltawil/nav2_mcp_server.git
cd nav2_mcp_server
docker build -t nav2_mcp_server .
```

Run it with **host networking** so DDS discovery reaches the robot:

```bash
docker run -i --rm --network host \
  -e ROS_DOMAIN_ID=<your_id> \
  -e ROS_LOCALHOST_ONLY=0 \
  -e BASE_FRAME=base_footprint \
  nav2_mcp_server
```

---

## 3. Configure for TIAGo

Copy `.env.example` to `.env` and set the values that match your robot:

```bash
ROS_DOMAIN_ID=30          # whatever your TIAGo uses
ROS_LOCALHOST_ONLY=0      # 0 when robot and server are on different machines
MAP_FRAME=map
BASE_FRAME=base_footprint
ENABLE_DOCKING=0          # opennav_docking is Jazzy+; keep off on Humble
TRANSPORT_MODE=stdio
LOG_LEVEL=INFO
```

### Quick smoke test

With TIAGo (or its sim) running and Nav2 active, in the activated venv with ROS sourced:

```bash
python -m nav2_mcp_server
```

It should log `Starting MCP server on stdio transport`. Verify end-to-end through any
client below by asking *"where is the robot now?"* (calls `get_robot_pose`).

---

## 4. Connect an LLM front-end

Replace `/ABSOLUTE/PATH/TO/nav2_mcp_server` with your clone path and `<your_id>` with
your `ROS_DOMAIN_ID`. Native install → point at the venv python; Docker → point at the
`docker run` command.

### 4A. Local — Claude Desktop / Cursor / VS Code

Launches the server over **stdio**. Claude Desktop config
(macOS `~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "nav2": {
      "command": "/ABSOLUTE/PATH/TO/nav2_mcp_server/.venv/bin/python",
      "args": ["-m", "nav2_mcp_server"],
      "env": {
        "ROS_DOMAIN_ID": "<your_id>",
        "ROS_LOCALHOST_ONLY": "0",
        "BASE_FRAME": "base_footprint"
      }
    }
  }
}
```

If the client can't inherit your ROS environment, use the self-contained Docker variant:

```json
{
  "mcpServers": {
    "nav2": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "--network", "host",
               "-e", "ROS_DOMAIN_ID=<your_id>",
               "-e", "ROS_LOCALHOST_ONLY=0",
               "-e", "BASE_FRAME=base_footprint",
               "nav2_mcp_server"]
    }
  }
}
```

Cursor: same JSON under Settings → MCP or `~/.cursor/mcp.json`. Restart the client, then
prompt: *"Navigate the robot to x=2, y=3, yaw=1.57."*

### 4B. GitHub Copilot (VS Code agent mode)

Copilot agent mode reads `.vscode/mcp.json` (top-level `"servers"` key):

```json
{
  "servers": {
    "nav2": {
      "type": "stdio",
      "command": "docker",
      "args": ["run", "-i", "--rm", "--network", "host",
               "-e", "ROS_DOMAIN_ID=<your_id>",
               "-e", "ROS_LOCALHOST_ONLY=0",
               "-e", "BASE_FRAME=base_footprint",
               "nav2_mcp_server"]
    }
  }
}
```

Enable agent mode (Copilot Chat → mode selector → *Agent*), confirm the `nav2` tools
appear in the tools list, then ask: *"Use the nav2 tools to spin the robot 90 degrees."*

### 4C. Offline / local LLMs — Llama via Ollama

Ollama does **not** speak MCP itself; use an MCP host.

**Option 1 — `mcphost` (Ollama-native CLI):**

```bash
ollama pull llama3.1            # use a TOOL-CALLING model (llama3.1/3.2, qwen2.5, mistral-nemo)
go install github.com/mark3labs/mcphost@latest
```

`~/.mcphost.json`:

```json
{
  "mcpServers": {
    "nav2": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "--network", "host",
               "-e", "ROS_DOMAIN_ID=<your_id>",
               "-e", "ROS_LOCALHOST_ONLY=0",
               "-e", "BASE_FRAME=base_footprint",
               "nav2_mcp_server"]
    }
  }
}
```

```bash
mcphost -m ollama:llama3.1
```

**Option 2 — Continue.dev (VS Code):** register an MCP server with the same
`command`/`args`/`env` in `~/.continue/config.yaml` and select an Ollama model.

**Notes for local models:** use a tool-calling-capable model (many small models ignore
tools); 7–8B is a practical floor, larger is more reliable at chaining tool calls;
everything runs offline once the model and image are local.

---

## 5. Available tools on Humble

All tools work on Humble **except** docking, gated behind `ENABLE_DOCKING`:

| Tool | Humble (TIAGo) | Notes |
| --- | --- | --- |
| `navigate_to_pose`, `follow_waypoints`, `spin_robot`, `backup_robot`, `drive_on_heading`, `approach_target` | ✅ | core navigation/behaviors |
| `get_path`, `get_path_from_robot` | ✅ | planner queries |
| `clear_costmaps`, `get_robot_pose`, `cancel_navigation`, `nav2_lifecycle` | ✅ | status / lifecycle |
| `dock_robot`, `undock_robot` | ⚠️ auto-detected | requires `opennav_docking` (ROS 2 Jazzy+). On Humble they return `FEATURE_NOT_SUPPORTED` |

The docking tools are always registered (so they show up in the client) but the
server auto-detects whether the running Nav2 actually provides the docking action.
On Humble (TIAGo) it does not, so a call returns a clear `FEATURE_NOT_SUPPORTED`
error at call time rather than crashing or hanging. Setting `ENABLE_DOCKING=0`
disables them everywhere, including on Jazzy+.

---

## 6. Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| `Action server for /navigate_to_pose not available` | Nav2 not launched / lifecycle not active; bring up Nav2 and run `nav2_lifecycle startup`. |
| `Could not get transform … base_footprint` / pose times out | Wrong `BASE_FRAME`, wrong `ROS_DOMAIN_ID`, or no DDS reachability. Check `ros2 run tf2_ros tf2_echo map base_footprint`. |
| `No module named 'rclpy'` | venv created without `--system-site-packages`, or ROS not sourced. Recreate per step 2, or use Docker. |
| Tools don't appear in the client | Check the client's MCP logs; confirm the `command`/`args` path and that the process starts. |
| Docker can't see the robot | Add `--network host` and set `ROS_LOCALHOST_ONLY=0`. |
| Local Llama ignores the tools | Use a tool-calling model (e.g. `llama3.1`); smaller models often can't call tools. |
