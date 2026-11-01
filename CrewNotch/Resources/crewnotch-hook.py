#!/usr/bin/env python3
"""
CrewNotch hook bridge.

Every supported coding agent runs this script from its own hook system:

    crewnotch-hook.py --agent <agent> [--event <EventName>]

The agent's JSON payload arrives on stdin. The script maps it onto one
normalized event (Claude Code's event vocabulary) and sends it to the
CrewNotch app over a Unix socket. For approval requests from agents that
support it, the script waits for the user's decision and prints it in the
agent's own output format.

The script only observes: if the app isn't running or anything goes wrong
it exits 0 without output, so the agent carries on as if no hook existed.
"""
import json
import os
import socket
import stat
import subprocess
import sys

SOCKET_PATH = os.environ.get("CREWNOTCH_SOCKET") or os.path.expanduser("~/.crewnotch/crewnotch.sock")
APPROVAL_TIMEOUT_SECONDS = 3600

# Agents whose approval prompt can be answered from the notch.
APPROVING_AGENTS = {"claude", "codex"}

# Agents that expect a JSON object on stdout even when the hook has no opinion.
JSON_OUTPUT_AGENTS = {"antigravity", "cursor", "copilot", "gemini"}

# Process names that sit between an agent and this script (`sh -c ...`).
WRAPPER_PROCESSES = {"sh", "bash", "zsh", "dash", "fish", "env", "python3", "Python", "timeout"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def pick(data, *keys):
    """First non-empty value among `keys` (supports snake_case/camelCase twins)."""
    for key in keys:
        value = data.get(key)
        if value not in (None, ""):
            return value
    return None


def as_dict(value):
    """Tool input may arrive as an object or as a JSON-encoded string."""
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {"input": value}
        except ValueError:
            return {"input": value}
    return {}


def path_from(value):
    """Workspace entries may be plain paths or file:// URIs."""
    if isinstance(value, list):
        value = value[0] if value else None
    if not isinstance(value, str):
        return None
    if value.startswith("file://"):
        from urllib.parse import unquote, urlparse
        return unquote(urlparse(value).path)
    return value


def clip(text, limit=4000):
    if not isinstance(text, str):
        return None
    text = text.strip()
    return text[:limit] if text else None


def event_state(event, status, **fields):
    state = {"event": event, "status": status}
    state.update({k: v for k, v in fields.items() if v is not None})
    return state


def tool_fields(data, name_keys=("tool_name", "toolName"), input_keys=("tool_input", "toolInput", "toolArgs")):
    return {
        "tool": pick(data, *name_keys),
        "tool_input": as_dict(pick(data, *input_keys)),
        "tool_use_id": pick(data, "tool_use_id", "toolUseId", "tool_call_id", "callId"),
    }


def agent_process():
    """(pid, tty) of the agent: the closest ancestor that isn't a shell wrapper."""
    pid = os.getppid()
    try:
        out = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,tty=,comm="],
            capture_output=True, text=True, timeout=2,
        ).stdout
    except Exception:
        return pid, None

    table = {}
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) == 4 and parts[0].isdigit() and parts[1].isdigit():
            table[int(parts[0])] = (int(parts[1]), parts[2], os.path.basename(parts[3]))

    for _ in range(8):
        entry = table.get(pid)
        if entry is None or entry[2] not in WRAPPER_PROCESSES or entry[0] <= 1:
            break
        pid = entry[0]

    tty = table.get(pid, (0, None, ""))[1]
    if not tty or tty in ("??", "-"):
        tty = None
    elif not tty.startswith("/dev/"):
        tty = "/dev/" + tty
    return pid, tty


def detect_replay_source(data):
    """Cursor and Grok also run hooks registered for other agents.

    Returns the agent that really fired the hook when the payload gives it
    away, so replayed copies can be dropped (each agent has its own hook).
    """
    if "cursor_version" in data:
        return "cursor"
    if "hookEventName" in data:
        return "grok"
    return None


# ---------------------------------------------------------------------------
# Per-agent mappers: payload -> normalized state (or None to ignore)
# ---------------------------------------------------------------------------

def map_claude_like(event, data):
    """Claude Code and Codex share event names and payload shape."""
    if event in ("UserPromptSubmit",):
        return event_state(event, "processing", prompt=clip(data.get("prompt")))
    if event == "PreToolUse":
        return event_state(event, "running_tool", **tool_fields(data))
    if event in ("PostToolUse", "PostToolUseFailure", "PermissionDenied"):
        return event_state("PostToolUse" if event != "PermissionDenied" else event, "processing", **tool_fields(data))
    if event == "PermissionRequest":
        return event_state(event, "waiting_for_approval", **tool_fields(data))
    if event == "Notification":
        kind = data.get("notification_type")
        if kind == "permission_prompt":
            return None  # PermissionRequest carries the details
        status = "waiting_for_input" if kind == "idle_prompt" else "notification"
        return event_state(event, status, notification_type=kind, message=clip(data.get("message")))
    if event in ("Stop", "StopFailure", "Interrupt"):
        return event_state(
            "Stop", "waiting_for_input",
            assistant_message=clip(data.get("last_assistant_message")),
            message=clip(data.get("error") or data.get("message")),
        )
    if event in ("SubagentStart", "SubagentStop", "PostCompact"):
        return event_state(event, "processing")
    if event == "PreCompact":
        return event_state(event, "compacting")
    if event == "SessionStart":
        return event_state(event, "waiting_for_input")
    if event == "SessionEnd":
        return event_state(event, "ended")
    return None


def map_gemini(event, data):
    if event == "SessionStart":
        return event_state(event, "waiting_for_input")
    if event == "BeforeAgent":
        return event_state("UserPromptSubmit", "processing", prompt=clip(data.get("prompt")))
    if event == "BeforeTool":
        return event_state("PreToolUse", "running_tool", **tool_fields(data))
    if event == "AfterTool":
        return event_state("PostToolUse", "processing", **tool_fields(data))
    if event == "Notification" and data.get("notification_type") == "ToolPermission":
        details = data.get("details") if isinstance(data.get("details"), dict) else {}
        return event_state(
            "PermissionRequest", "waiting_for_approval",
            tool=pick(details, "toolName", "name", "title") or "Tool",
            tool_input=as_dict(details.get("args") or details),
            message=clip(data.get("message")),
        )
    if event == "AfterAgent":
        return event_state("Stop", "waiting_for_input", assistant_message=clip(data.get("prompt_response")))
    if event == "PreCompress":
        return event_state("PreCompact", "compacting")
    if event == "SessionEnd":
        return event_state(event, "ended")
    return None


def map_cursor(event, data):
    if event == "sessionStart":
        return event_state("SessionStart", "waiting_for_input")
    if event == "beforeSubmitPrompt":
        return event_state("UserPromptSubmit", "processing", prompt=clip(data.get("prompt")))
    if event == "preToolUse":
        return event_state("PreToolUse", "running_tool", **tool_fields(data))
    if event in ("postToolUse", "postToolUseFailure"):
        return event_state("PostToolUse", "processing", **tool_fields(data))
    if event == "afterAgentResponse":
        return event_state("AssistantResponse", "processing", assistant_message=clip(data.get("text")))
    if event in ("subagentStart", "subagentStop"):
        return event_state("SubagentStart" if event == "subagentStart" else "SubagentStop", "processing")
    if event == "preCompact":
        return event_state("PreCompact", "compacting")
    if event == "stop":
        status = data.get("status")
        return event_state("Stop", "waiting_for_input", message=None if status in (None, "completed") else status)
    if event == "sessionEnd":
        return event_state("SessionEnd", "ended")
    return None


def map_copilot(event, data):
    if event == "sessionStart":
        return event_state("SessionStart", "waiting_for_input")
    if event == "userPromptSubmitted":
        return event_state("UserPromptSubmit", "processing", prompt=clip(data.get("prompt")))
    if event == "preToolUse":
        return event_state("PreToolUse", "running_tool", **tool_fields(data))
    if event in ("postToolUse", "postToolUseFailure"):
        return event_state("PostToolUse", "processing", **tool_fields(data))
    if event == "notification":
        kind = pick(data, "notification_type", "notificationType")
        if kind in ("permission_prompt", "elicitation_dialog"):
            return event_state(
                "PermissionRequest", "waiting_for_approval",
                tool=pick(data, "toolName", "title") or "Permission",
                tool_input=as_dict(pick(data, "toolArgs")),
                message=clip(data.get("message")),
            )
        if kind in ("agent_idle", "agent_completed"):
            return event_state("Stop", "waiting_for_input", message=clip(data.get("message")))
        return None
    if event == "agentStop":
        return event_state("Stop", "waiting_for_input")
    if event in ("subagentStart", "subagentStop"):
        return event_state("SubagentStart" if event == "subagentStart" else "SubagentStop", "processing")
    if event == "preCompact":
        return event_state("PreCompact", "compacting")
    if event == "sessionEnd":
        return event_state("SessionEnd", "ended")
    return None


def map_grok(event, data):
    if event == "Stop" and data.get("reason") in ("channel_closed", "shutdown"):
        return None  # session teardown, SessionEnd follows
    if event == "StopCancelled":
        event = "Stop"
    if event == "Notification":
        kind = pick(data, "notification_type", "notificationType")
        if kind == "permission_prompt":
            return event_state(
                "PermissionRequest", "waiting_for_approval",
                tool=pick(data, "toolName", "tool_name") or "Permission",
                tool_input=as_dict(pick(data, "toolInput", "tool_input")),
                message=clip(data.get("message")),
            )
        if kind in ("idle_prompt", "task_complete"):
            return event_state("Stop", "waiting_for_input", message=clip(data.get("message")))
        return None
    state = map_claude_like(event, data)
    if state and state["event"] == "Stop":
        state["assistant_message"] = clip(pick(data, "lastAssistantMessage", "last_assistant_message"))
    return state


def map_kiro(event, data):
    if event in ("agentSpawn", "SessionStart"):
        return event_state("SessionStart", "waiting_for_input")
    if event in ("userPromptSubmit", "UserPromptSubmit"):
        return event_state("UserPromptSubmit", "processing", prompt=clip(os.environ.get("USER_PROMPT") or data.get("prompt")))
    if event in ("preToolUse", "PreToolUse"):
        return event_state("PreToolUse", "running_tool", **tool_fields(data))
    if event in ("postToolUse", "PostToolUse"):
        return event_state("PostToolUse", "processing", **tool_fields(data))
    if event in ("stop", "Stop"):
        return event_state("Stop", "waiting_for_input", assistant_message=clip(data.get("assistant_response")))
    if event == "SessionEnd":
        return event_state("SessionEnd", "ended")
    return None


def map_antigravity(event, data):
    if event == "SessionStart":
        return event_state("SessionStart", "waiting_for_input")
    if event == "PreInvocation":
        # Fires before every model call; the first one after new input is the prompt.
        first_call = data.get("invocationNum") in (None, 0, 1)
        return event_state(
            "UserPromptSubmit" if first_call else "PostToolUse", "processing",
            prompt=clip(data.get("lastUserInput")) if first_call else None,
        )
    if event in ("PostToolUse", "PostInvocation"):
        call = data.get("toolCall") if isinstance(data.get("toolCall"), dict) else {}
        return event_state("PostToolUse", "processing", tool=call.get("name"), tool_input=as_dict(call.get("args")))
    if event == "Stop":
        reason = data.get("terminationReason")
        return event_state(
            "Stop", "waiting_for_input",
            message=clip(data.get("error")) if reason in ("ERROR", "MAX_INVOCATIONS", "MAX_TOKEN_BUDGET_EXCEEDED") else None,
        )
    return None


def antigravity_surface(data):
    """Which Antigravity front end fired the hook: 'app', 'ide' or 'cli'."""
    path = pick(data, "transcriptPath", "artifactDirectoryPath") or ""
    if "/antigravity-ide/" in path:
        return "ide"
    if "/antigravity-cli/" in path:
        return "cli"
    return "app"


MAPPERS = {
    "claude": map_claude_like,
    "codex": map_claude_like,
    "gemini": map_gemini,
    "cursor": map_cursor,
    "copilot": map_copilot,
    "grok": map_grok,
    "kiro": map_kiro,
    "antigravity": map_antigravity,
}


def session_and_cwd(agent, data):
    session_id = pick(data, "session_id", "sessionId", "conversation_id", "conversationId")
    if agent == "kiro":
        session_id = session_id or os.environ.get("KIRO_SESSION_ID")
    cwd = (
        path_from(pick(data, "cwd", "workspaceRoot", "workspace_roots", "workspacePaths"))
        or os.environ.get("GEMINI_PROJECT_DIR")
        or os.environ.get("CLAUDE_PROJECT_DIR")
        or os.getcwd()
    )
    return session_id, cwd


# ---------------------------------------------------------------------------
# Transport
# ---------------------------------------------------------------------------

def socket_is_trusted(path):
    """Only talk to a socket that we own, in a directory nobody else can write to.

    Otherwise another local user could pose as CrewNotch and approve tool calls.
    """
    try:
        sock_stat = os.lstat(path)
        dir_stat = os.stat(os.path.dirname(path))
    except OSError:
        return False
    uid = os.getuid()
    return (
        stat.S_ISSOCK(sock_stat.st_mode)
        and sock_stat.st_uid == uid
        and dir_stat.st_uid == uid
        and dir_stat.st_mode & 0o022 == 0
    )


def send(state, wait_for_reply):
    if not socket_is_trusted(SOCKET_PATH):
        return None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(APPROVAL_TIMEOUT_SECONDS if wait_for_reply else 2)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        reply = None
        if wait_for_reply:
            sock.shutdown(socket.SHUT_WR)
            data = sock.recv(65536)
            if data:
                reply = json.loads(data.decode())
        sock.close()
        return reply
    except (OSError, ValueError):
        return None


def approval_output(agent, reply):
    """Translate the app's {decision, reason} into the agent's hook output."""
    decision = (reply or {}).get("decision")
    if decision not in ("allow", "deny"):
        return None  # "ask" or no reply: the agent shows its own prompt
    behavior = {"behavior": decision}
    if decision == "deny":
        behavior["message"] = reply.get("reason") or "Denied from CrewNotch"
    return {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": behavior}}


def parse_args(argv):
    args = {"agent": "claude", "event": None}
    it = iter(argv)
    for arg in it:
        if arg in ("--agent", "--event"):
            args[arg[2:]] = next(it, None)
    return args


def main():
    args = parse_args(sys.argv[1:])
    agent = args["agent"]
    output = {} if agent in JSON_OUTPUT_AGENTS else None

    try:
        data = json.load(sys.stdin)
        if not isinstance(data, dict):
            raise ValueError
    except ValueError:
        data = {}

    replayed_by = detect_replay_source(data)
    mapper = MAPPERS.get(agent)
    event = args["event"] or pick(data, "hook_event_name", "hookEventName")

    state = None
    if mapper and event and (replayed_by is None or replayed_by == agent):
        state = mapper(event, data)

    if state:
        session_id, cwd = session_and_cwd(agent, data)
        if session_id:
            pid, tty = agent_process()
            state.update({
                "agent": agent,
                # Namespace non-Claude ids so they never collide with Claude's.
                "session_id": session_id if agent == "claude" else "%s:%s" % (agent, session_id),
                "cwd": cwd,
                "pid": pid,
                "tty": tty,
                "can_respond": agent in APPROVING_AGENTS,
            })
            if agent == "antigravity":
                state["source_app"] = antigravity_surface(data)
            if agent == "claude" and isinstance(data.get("transcript_path"), str):
                state["transcript_path"] = data["transcript_path"]

            wants_decision = state["status"] == "waiting_for_approval" and state["can_respond"]
            reply = send(state, wait_for_reply=wants_decision)
            if wants_decision:
                output = approval_output(agent, reply)

    if output is not None:
        print(json.dumps(output))
    sys.exit(0)


if __name__ == "__main__":
    main()
