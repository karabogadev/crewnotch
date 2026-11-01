// CrewNotch plugin for OpenCode.
// Reports session state (working, finished, needs you) to the CrewNotch app
// over its local Unix socket. It only observes: if CrewNotch isn't running,
// events are dropped silently and OpenCode is unaffected.
// Installed and removed by CrewNotch (Settings -> Agents).

import { createConnection } from "node:net"
import { lstatSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const SOCKET_PATH = join(homedir(), ".crewnotch", "crewnotch.sock")

// Only talk to a socket owned by this user, so nobody else can pose as CrewNotch.
const socketIsTrusted = () => {
  try {
    const info = lstatSync(SOCKET_PATH)
    return info.isSocket() && info.uid === process.getuid()
  } catch {
    return false
  }
}

export const CrewNotch = async ({ client, directory, worktree, serverUrl }) => {
  const cwd = worktree || directory || process.cwd()
  const childSessions = new Set()

  const stateFor = (sessionID, event, status, fields) => ({
    agent: "opencode",
    session_id: `opencode:${sessionID}`,
    cwd,
    event,
    status,
    pid: process.pid,
    can_respond: false,
    ...fields,
  })

  const send = (sessionID, event, status, fields = {}) => {
    if (!sessionID || childSessions.has(sessionID)) return
    if (!socketIsTrusted()) return
    try {
      const socket = createConnection(SOCKET_PATH)
      socket.on("error", () => {})
      socket.on("connect", () => socket.end(JSON.stringify(stateFor(sessionID, event, status, fields))))
    } catch {}
  }

  // Sends a request and waits for the app's answer: {decision, updated_permissions}.
  // Resolves null if the app isn't running, is set not to answer, or the socket closes.
  const ask = (sessionID, fields) =>
    new Promise((resolve) => {
      if (!sessionID || childSessions.has(sessionID) || !socketIsTrusted()) return resolve(null)
      const chunks = []
      try {
        const socket = createConnection(SOCKET_PATH)
        socket.on("error", () => resolve(null))
        socket.on("connect", () => {
          socket.write(JSON.stringify(stateFor(sessionID, "PermissionRequest", "waiting_for_approval", { ...fields, can_respond: true })))
          socket.end()
        })
        socket.on("data", (chunk) => chunks.push(chunk))
        socket.on("close", () => {
          try {
            resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : null)
          } catch {
            resolve(null)
          }
        })
      } catch {
        resolve(null)
      }
    })

  // Answers OpenCode's permission prompt. Whoever answers first wins, so the
  // prompt in the terminal keeps working while the notch waits.
  const reply = async (sessionID, requestID, response) => {
    const query = { directory }
    try {
      const result = await client.postSessionIdPermissionsPermissionId({
        path: { id: sessionID, permissionID: requestID },
        body: { response },
        query,
      })
      if (!result || !result.error) return
    } catch {}
    try {
      const url = new URL(`/permission/${encodeURIComponent(requestID)}/reply`, serverUrl)
      if (directory) url.searchParams.set("directory", directory)
      await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ reply: response }) })
    } catch {}
  }

  const answerFromNotch = async (props) => {
    const always = [].concat(props.always || []).filter((p) => typeof p === "string")
    const answer = await ask(props.sessionID, {
      tool: props.permission || props.type || "Permission",
      tool_input: requestInput(props),
      tool_use_id: props.id,
      permission_suggestions: always.length ? [{ type: "opencodeAlways", patterns: always }] : undefined,
    })
    if (!answer || (answer.decision !== "allow" && answer.decision !== "deny")) return
    const savesRule = Array.isArray(answer.updated_permissions) && answer.updated_permissions.length > 0
    await reply(props.sessionID, props.id, answer.decision === "deny" ? "reject" : savesRule ? "always" : "once")
  }

  // What the request would do, in the shape CrewNotch shows for other agents
  const requestInput = (props) => {
    const patterns = [].concat(props.patterns || props.pattern || []).filter((p) => typeof p === "string")
    const input = {}
    const meta = props.metadata || {}
    for (const [key, value] of Object.entries(meta)) {
      if (typeof value === "string" && value.length < 4000) input[key] = value
    }
    if ((props.permission || props.type) === "bash" && patterns.length) input.command = patterns.join(" && ")
    else if (patterns.length) input.pattern = patterns.join(", ")
    if (input.filepath && !input.file_path) input.file_path = input.filepath
    return input
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
          // Don't hold up OpenCode's other events while the notch waits for an answer
          answerFromNotch(props)
          return
        case "permission.replied":
          send(props.sessionID, "PostToolUse", "processing", { tool_use_id: props.requestID || props.permissionID })
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
