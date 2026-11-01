"""
Each agent's own hook payloads, run through crewnotch-hook.py, must reach
the app as the normalized event (Claude Code's names plus a status).
"""
import os
import unittest

from support import SID, AppTestCase, run_hook

# Marks a field the message must not carry.
ABSENT = object()
BASH = {"tool_name": "Bash", "tool_input": {"command": "ls"}, "tool_use_id": "t1"}

# (agent, event, payload, expected fields, or None when nothing may be sent).
# A field expected as ABSENT must not be in the message.
CASES = [
    # Claude Code
    ("claude", "UserPromptSubmit", {"prompt": "  hi  "}, {"event": "UserPromptSubmit", "status": "processing", "prompt": "hi"}),
    ("claude", "PreToolUse", BASH, {"event": "PreToolUse", "status": "running_tool", "tool": "Bash", "tool_input": {"command": "ls"}, "tool_use_id": "t1"}),
    ("claude", "PreToolUse", {"tool_name": "Bash", "tool_input": '{"command": "ls"}'}, {"tool_input": {"command": "ls"}}),
    ("claude", "PreToolUse", {"tool_name": "Bash", "tool_input": "plain text"}, {"tool_input": {"input": "plain text"}}),
    ("claude", "PostToolUse", BASH, {"event": "PostToolUse", "status": "processing", "tool_use_id": "t1"}),
    ("claude", "PostToolUseFailure", BASH, {"event": "PostToolUse", "status": "processing"}),
    ("claude", "PostToolUse", {"tool_name": "TaskCreate", "tool_response": {"task": {"id": "7"}, "noise": "x" * 50}},
     {"tool_response": {"task": {"id": "7"}}}),
    ("claude", "PermissionDenied", BASH, {"event": "PermissionDenied", "status": "processing"}),
    ("claude", "Notification", {"notification_type": "permission_prompt"}, None),
    ("claude", "Notification", {"notification_type": "idle_prompt", "message": "Waiting"},
     {"event": "Notification", "status": "waiting_for_input", "notification_type": "idle_prompt", "message": "Waiting"}),
    ("claude", "Notification", {"notification_type": "auth_success"}, {"event": "Notification", "status": "notification"}),
    ("claude", "Stop", {"last_assistant_message": "Done"}, {"event": "Stop", "status": "waiting_for_input", "assistant_message": "Done"}),
    ("claude", "StopFailure", {"error": "rate limited"}, {"event": "Stop", "status": "waiting_for_input", "message": "rate limited"}),
    ("claude", "SubagentStart", {}, {"event": "SubagentStart", "status": "processing"}),
    ("claude", "SubagentStop", {}, {"event": "SubagentStop", "status": "processing"}),
    ("claude", "PreCompact", {}, {"event": "PreCompact", "status": "compacting"}),
    ("claude", "PostCompact", {}, {"event": "PostCompact", "status": "processing"}),
    ("claude", "SessionStart", {}, {"event": "SessionStart", "status": "waiting_for_input"}),
    ("claude", "SessionEnd", {}, {"event": "SessionEnd", "status": "ended"}),
    ("claude", "SomethingNew", {}, None),
    # Codex shares Claude's names
    ("codex", "UserPromptSubmit", {"prompt": "hi"}, {"event": "UserPromptSubmit", "status": "processing"}),
    ("codex", "Stop", {"last_assistant_message": "Done"}, {"event": "Stop", "assistant_message": "Done"}),
    # Gemini CLI
    ("gemini", "SessionStart", {}, {"event": "SessionStart", "status": "waiting_for_input"}),
    ("gemini", "BeforeAgent", {"prompt": "hi"}, {"event": "UserPromptSubmit", "status": "processing", "prompt": "hi"}),
    ("gemini", "BeforeTool", {"tool_name": "run_shell_command", "tool_input": {"command": "ls"}},
     {"event": "PreToolUse", "status": "running_tool", "tool": "run_shell_command"}),
    ("gemini", "AfterTool", {"tool_name": "run_shell_command"}, {"event": "PostToolUse", "status": "processing"}),
    ("gemini", "AfterAgent", {"prompt_response": "Done"}, {"event": "Stop", "status": "waiting_for_input", "assistant_message": "Done"}),
    ("gemini", "PreCompress", {}, {"event": "PreCompact", "status": "compacting"}),
    ("gemini", "Notification", {"notification_type": "ToolPermission", "details": {"toolName": "write_file", "args": {"path": "a"}}},
     {"event": "PermissionRequest", "status": "waiting_for_approval", "tool": "write_file", "tool_input": {"path": "a"}, "can_respond": False}),
    ("gemini", "Notification", {"notification_type": "Other"}, None),
    ("gemini", "SessionEnd", {}, {"event": "SessionEnd", "status": "ended"}),
    # Cursor
    ("cursor", "sessionStart", {}, {"event": "SessionStart", "status": "waiting_for_input"}),
    ("cursor", "beforeSubmitPrompt", {"prompt": "hi"}, {"event": "UserPromptSubmit", "status": "processing"}),
    ("cursor", "preToolUse", BASH, {"event": "PreToolUse", "status": "running_tool", "tool": "Bash"}),
    ("cursor", "postToolUseFailure", BASH, {"event": "PostToolUse", "status": "processing"}),
    ("cursor", "afterAgentResponse", {"text": "Here you go"}, {"event": "AssistantResponse", "status": "processing", "assistant_message": "Here you go"}),
    ("cursor", "subagentStop", {}, {"event": "SubagentStop", "status": "processing"}),
    ("cursor", "preCompact", {}, {"event": "PreCompact", "status": "compacting"}),
    ("cursor", "stop", {"status": "completed"}, {"event": "Stop", "status": "waiting_for_input", "message": ABSENT}),
    ("cursor", "stop", {"status": "error"}, {"event": "Stop", "message": "error"}),
    ("cursor", "sessionEnd", {}, {"event": "SessionEnd", "status": "ended"}),
    # Copilot CLI
    ("copilot", "userPromptSubmitted", {"prompt": "hi"}, {"event": "UserPromptSubmit", "status": "processing"}),
    ("copilot", "preToolUse", {"toolName": "bash", "toolArgs": '{"command": "ls"}'},
     {"event": "PreToolUse", "tool": "bash", "tool_input": {"command": "ls"}}),
    ("copilot", "notification", {"notification_type": "permission_prompt", "toolName": "bash", "toolArgs": "{}"},
     {"event": "PermissionRequest", "status": "waiting_for_approval", "tool": "bash", "can_respond": False}),
    ("copilot", "notification", {"notificationType": "agent_idle"}, {"event": "Stop", "status": "waiting_for_input"}),
    ("copilot", "notification", {"notification_type": "progress"}, None),
    ("copilot", "agentStop", {}, {"event": "Stop", "status": "waiting_for_input"}),
    ("copilot", "sessionEnd", {}, {"event": "SessionEnd", "status": "ended"}),
    # Grok (its payloads carry hookEventName)
    ("grok", "UserPromptSubmit", {"prompt": "hi", "hookEventName": "UserPromptSubmit"}, {"event": "UserPromptSubmit"}),
    ("grok", "Stop", {"lastAssistantMessage": "Done", "hookEventName": "Stop"}, {"event": "Stop", "assistant_message": "Done"}),
    ("grok", "Stop", {"reason": "channel_closed", "hookEventName": "Stop"}, None),
    ("grok", "StopCancelled", {"hookEventName": "StopCancelled"}, {"event": "Stop", "status": "waiting_for_input"}),
    ("grok", "Notification", {"notificationType": "permission_prompt", "toolName": "bash", "hookEventName": "Notification"},
     {"event": "PermissionRequest", "status": "waiting_for_approval", "tool": "bash", "can_respond": False}),
    ("grok", "Notification", {"notificationType": "task_complete", "hookEventName": "Notification"}, {"event": "Stop"}),
    # Kiro
    ("kiro", "agentSpawn", {}, {"event": "SessionStart", "status": "waiting_for_input"}),
    ("kiro", "preToolUse", {"tool_name": "execute_bash", "tool_input": {"command": "ls"}}, {"event": "PreToolUse", "tool": "execute_bash"}),
    ("kiro", "stop", {"assistant_response": "Done"}, {"event": "Stop", "assistant_message": "Done"}),
    # Antigravity
    ("antigravity", "SessionStart", {}, {"event": "SessionStart", "status": "waiting_for_input", "source_app": "app"}),
    ("antigravity", "PreInvocation", {"invocationNum": 1, "lastUserInput": "hi"}, {"event": "UserPromptSubmit", "status": "processing", "prompt": "hi"}),
    ("antigravity", "PreInvocation", {"invocationNum": 4, "lastUserInput": "hi"}, {"event": "PostToolUse", "status": "processing", "prompt": ABSENT}),
    ("antigravity", "PostInvocation", {"toolCall": {"name": "run_command", "args": {"CommandLine": "ls"}}},
     {"event": "PostToolUse", "tool": "run_command", "tool_input": {"CommandLine": "ls"}}),
    ("antigravity", "Stop", {"terminationReason": "ERROR", "error": "boom"}, {"event": "Stop", "message": "boom"}),
    ("antigravity", "Stop", {"terminationReason": "COMPLETED", "error": "ignored"}, {"event": "Stop", "status": "waiting_for_input", "message": ABSENT}),
    ("antigravity", "SessionStart", {"transcriptPath": "/x/antigravity-ide/brain/1.md"}, {"source_app": "ide"}),
    ("antigravity", "SessionStart", {"transcriptPath": "/x/antigravity-cli/brain/1.md"}, {"source_app": "cli"}),
    # Agents and events CrewNotch doesn't know
    ("deepseek", "Stop", {}, None),
    ("nobody", "Stop", {}, None),
]

class HookMappingTests(AppTestCase):
    def test_every_agent_event(self):
        for agent, event, payload, expected in CASES:
            with self.subTest(agent=agent, event=event, payload=payload):
                output, code = self.hook(agent, event, dict(payload, session_id=SID))
                self.assertEqual(code, 0)
                if expected is None:
                    self.assertSilent()
                    continue
                message = self.app.next_message()
                for key, value in expected.items():
                    if value is ABSENT:
                        self.assertNotIn(key, message)
                    else:
                        self.assertEqual(message.get(key), value, key)
                self.assertEqual(message["agent"], agent)
                self.assertEqual(message["session_id"], SID if agent == "claude" else "%s:%s" % (agent, SID))
                self.assertEqual(message["cwd"], self.workspace)
                self.assertIsInstance(message["pid"], int)
                self.assertNotIn(None, message.values(), "None values are dropped before sending")

    def test_only_claude_and_codex_wait_for_an_answer(self):
        starts = {
            "claude": ("SessionStart", {}), "codex": ("SessionStart", {}),
            "gemini": ("SessionStart", {}), "cursor": ("sessionStart", {}), "copilot": ("sessionStart", {}),
            "grok": ("SessionStart", {"hookEventName": "SessionStart"}), "kiro": ("agentSpawn", {}),
            "antigravity": ("SessionStart", {}),
        }
        for agent, (event, payload) in starts.items():
            with self.subTest(agent=agent):
                self.hook(agent, event, dict(payload, session_id=SID))
                self.assertEqual(self.app.next_message()["can_respond"], agent in ("claude", "codex"))

    def test_session_id_keys(self):
        for key in ("session_id", "sessionId", "conversation_id", "conversationId"):
            self.hook("cursor", "stop", {key: "k-" + key})
            self.assertEqual(self.app.next_message()["session_id"], "cursor:k-" + key)

    def test_kiro_reads_prompt_and_session_from_its_environment(self):
        self.hook("kiro", "userPromptSubmit", {}, USER_PROMPT="from env", KIRO_SESSION_ID="kiro-env")
        message = self.app.next_message()
        self.assertEqual(message["prompt"], "from env")
        self.assertEqual(message["session_id"], "kiro:kiro-env")

    def test_claude_passes_its_transcript_path(self):
        self.hook("claude", "Stop", {"session_id": SID, "transcript_path": "/t/abc.jsonl"})
        self.assertEqual(self.app.next_message()["transcript_path"], "/t/abc.jsonl")
        self.hook("codex", "Stop", {"session_id": SID, "transcript_path": "/t/abc.jsonl"})
        self.assertNotIn("transcript_path", self.app.next_message())

    def test_long_text_is_clipped(self):
        self.hook("claude", "UserPromptSubmit", {"session_id": SID, "prompt": "x" * 5000})
        self.assertEqual(len(self.app.next_message()["prompt"]), 4000)


class WorkspaceTests(AppTestCase):
    def test_cwd_from_workspace_uri(self):
        self.hook("cursor", "stop", {"conversation_id": SID, "cwd": None, "workspace_roots": ["file:///Users/me/my%20app"]})
        self.assertEqual(self.app.next_message()["cwd"], "/Users/me/my app")

    def test_cwd_from_agent_environment(self):
        payload = {"session_id": SID}
        run_hook(self.app.path, "gemini", "BeforeAgent", payload, GEMINI_PROJECT_DIR="/gem/project")
        self.assertEqual(self.app.next_message()["cwd"], "/gem/project")
        run_hook(self.app.path, "claude", "Stop", payload, CLAUDE_PROJECT_DIR="/claude/project")
        self.assertEqual(self.app.next_message()["cwd"], "/claude/project")

    def test_git_branch_of_the_workspace(self):
        repo = os.path.join(self.workspace, ".git")
        os.makedirs(repo)
        nested = os.path.join(self.workspace, "src", "app")
        os.makedirs(nested)
        with open(os.path.join(repo, "HEAD"), "w") as head:
            head.write("ref: refs/heads/feature/pagination\n")
        self.hook("claude", "Stop", {"session_id": SID, "cwd": nested})
        self.assertEqual(self.app.next_message()["git_branch"], "feature/pagination")

        with open(os.path.join(repo, "HEAD"), "w") as head:
            head.write("0123456789abcdef0123456789abcdef01234567\n")
        self.hook("claude", "Stop", {"session_id": SID})
        self.assertEqual(self.app.next_message()["git_branch"], "0123456")

    def test_no_git_branch_outside_a_repo(self):
        self.hook("claude", "Stop", {"session_id": SID})
        self.assertNotIn("git_branch", self.app.next_message())


if __name__ == "__main__":
    unittest.main()
