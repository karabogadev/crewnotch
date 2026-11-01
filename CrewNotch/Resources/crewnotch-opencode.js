// CrewNotch plugin for OpenCode.
// Reports session state (working, finished, needs you) to the CrewNotch app
// over its local Unix socket. It only observes: if CrewNotch isn't running,
// events are dropped silently and OpenCode is unaffected.
// Installed and removed by CrewNotch (Settings -> Agents).

import { createConnection } from "node:net"

const SOCKET_PATH = "/tmp/crewnotch.sock"

export const CrewNotch = async ({ directory, worktree }) => {
  const cwd = worktree || directory || process.cwd()
  const childSessions = new Set()

  const send = (sessionID, event, status, fields = {}) => {
    if (!sessionID || childSessions.has(sessionID)) return
    const state = {
      agent: "opencode",
      session_id: `opencode:${sessionID}`,
      cwd,
      event,
      status,
      pid: process.pid,
      can_respond: false,
      ...fields,
    }
    try {
      const socket = createConnection(SOCKET_PATH)
      socket.on("error", () => {})
      socket.on("connect", () => socket.end(JSON.stringify(state)))
    } catch {}
  }

  const textOf = (parts) =>
    (parts || [])
      .filter((part) => part && part.type === "text" && typeof part.text === "string")
      .map((part) => part.text)
      .join("\n")
      .trim()
      .slice(0, 4000) || undefined

  return {
    event: async ({ event }) => {
      const props = event.properties || {}
      switch (event.type) {
        case "session.created": {
          const info = props.info || {}
          if (info.parentID) {
            childSessions.add(info.id)
            return
          }
          send(info.id, "SessionStart", "waiting_for_input", { title: info.title })
          return
        }
        case "session.updated": {
          const info = props.info || {}
          if (info.title) send(info.id, "TitleChanged", "metadata", { title: info.title })
          return
        }
        case "session.status": {
          const type = props.status && props.status.type
          if (type === "busy" || type === "retry") send(props.sessionID, "PostToolUse", "processing")
          else if (type === "idle") send(props.sessionID, "Stop", "waiting_for_input")
          return
        }
        case "session.idle":
          send(props.sessionID, "Stop", "waiting_for_input")
          return
        case "session.error":
          send(props.sessionID, "Stop", "waiting_for_input", {
            message: (props.error && (props.error.message || props.error.name)) || "Error",
          })
          return
        case "permission.asked":
        case "permission.updated":
          send(props.sessionID, "PermissionRequest", "waiting_for_approval", {
            tool: props.permission || props.type || "Permission",
            tool_input: { pattern: (props.patterns || props.pattern || []).toString() },
            tool_use_id: props.id,
          })
          return
        case "permission.replied":
          send(props.sessionID, "PostToolUse", "processing")
          return
        case "session.deleted": {
          const info = props.info || {}
          send(info.id, "SessionEnd", "ended")
          return
        }
      }
    },

    "chat.message": async (input, output) => {
      send(input.sessionID, "UserPromptSubmit", "processing", { prompt: textOf(output && output.parts) })
    },

    "tool.execute.before": async (input, output) => {
      send(input.sessionID, "PreToolUse", "running_tool", {
        tool: input.tool,
        tool_input: (output && output.args) || {},
        tool_use_id: input.callID,
      })
    },

    "tool.execute.after": async (input) => {
      send(input.sessionID, "PostToolUse", "processing", { tool: input.tool, tool_use_id: input.callID })
    },
  }
}
