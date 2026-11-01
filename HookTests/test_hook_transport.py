"""
The hook's side of the socket: waiting for the app's answer, translating it
into each agent's output, and staying out of the way when anything is off.
"""
import json
import os
import tempfile
import time
import unittest

from support import NO_REPLY, SID, AppTestCase, fake_app, missing_socket_path, run_hook

REQUEST = {
    "session_id": SID,
    "cwd": tempfile.gettempdir(),
    "tool_name": "Bash",
    "tool_input": {"command": "npm test"},
    "permission_suggestions": [{"type": "addRules", "rules": [{"toolName": "Bash", "ruleContent": "npm test:*"}]}],
}
RULES = [{"type": "addRules", "rules": [{"toolName": "Bash", "ruleContent": "npm test:*"}], "destination": "localSettings"}]


def decision(output):
    return json.loads(output)["hookSpecificOutput"]["decision"]


def ask(socket_path, agent="claude"):
    """Sends an approval request the way the agent would; returns (stdout, exit code)."""
    return run_hook(socket_path, agent, "PermissionRequest", REQUEST)


class ApprovalReplyTests(unittest.TestCase):
    """What the agent sees for each answer from the notch."""

    def answer(self, agent, reply, prefix=b""):
        app = fake_app(self, reply, prefix)
        output, code = ask(app.path, agent)
        self.assertEqual(code, 0)
        message = app.next_message()
        self.assertEqual(message["event"], "PermissionRequest")
        self.assertEqual(message["status"], "waiting_for_approval")
        self.assertTrue(message["can_respond"])
        self.assertEqual(message["permission_suggestions"], REQUEST["permission_suggestions"])
        return output

    def test_allow(self):
        output = self.answer("claude", {"decision": "allow"})
        self.assertEqual(json.loads(output), {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}})

    def test_deny_with_and_without_reason(self):
        self.assertEqual(decision(self.answer("claude", {"decision": "deny", "reason": "Not on main"})),
                         {"behavior": "deny", "message": "Not on main"})
        self.assertEqual(decision(self.answer("claude", {"decision": "deny"})),
                         {"behavior": "deny", "message": "Denied from CrewNotch"})

    def test_claude_gets_updated_input_and_permissions(self):
        answers = {"command": "npm test", "answers": {"Which?": "A"}}
        result = decision(self.answer("claude", {"decision": "allow", "updated_input": answers, "updated_permissions": RULES}))
        self.assertEqual(result, {"behavior": "allow", "updatedInput": answers, "updatedPermissions": RULES})

    def test_codex_gets_a_bare_decision(self):
        # Codex rejects a decision that carries Claude-only fields
        result = decision(self.answer("codex", {"decision": "allow", "updated_input": {"a": 1}, "updated_permissions": RULES}))
        self.assertEqual(result, {"behavior": "allow"})

    def test_malformed_extras_are_dropped(self):
        result = decision(self.answer("claude", {"decision": "allow", "updated_input": "nope", "updated_permissions": {"not": "a list"}}))
        self.assertEqual(result, {"behavior": "allow"})

    def test_ask_leaves_the_prompt_to_the_agent(self):
        self.assertEqual(self.answer("claude", {"decision": "ask"}), "")

    def test_no_answer_leaves_the_prompt_to_the_agent(self):
        # Approving from the notch is off, or the request was answered in the terminal
        self.assertEqual(self.answer("claude", NO_REPLY), "")

    def test_liveness_probe_before_the_answer_is_ignored(self):
        output = self.answer("claude", {"decision": "allow"}, prefix=b"\n\n")
        self.assertEqual(decision(output), {"behavior": "allow"})

    def test_garbage_answer_is_ignored(self):
        self.assertEqual(self.answer("claude", b"{not json"), "")


class ObserveOnlyTests(AppTestCase):
    reply = {"decision": "allow"}

    def test_other_agents_never_wait(self):
        # Copilot's permission notification is shown, never answered
        started = time.monotonic()
        output, code = self.hook("copilot", "notification", {"sessionId": SID, "notification_type": "permission_prompt", "toolName": "bash"})
        self.assertLess(time.monotonic() - started, 5)
        self.assertEqual((output, code), ("{}", 0))
        self.assertFalse(self.app.next_message()["can_respond"])


class OutputFormatTests(AppTestCase):
    def test_json_agents_always_print_an_object(self):
        for agent, event in (("cursor", "stop"), ("copilot", "agentStop"), ("gemini", "AfterAgent"), ("antigravity", "Stop")):
            with self.subTest(agent=agent):
                self.assertEqual(self.hook(agent, event, {"session_id": SID}), ("{}", 0))
                self.app.next_message()

    def test_other_agents_print_nothing(self):
        for agent in ("claude", "codex", "kiro"):
            with self.subTest(agent=agent):
                self.assertEqual(self.hook(agent, "Stop", {"session_id": SID}), ("", 0))
                self.app.next_message()


class InputTests(AppTestCase):
    def test_event_name_from_the_payload(self):
        self.hook("claude", None, {"session_id": SID, "hook_event_name": "Stop"})
        self.assertEqual(self.app.next_message()["event"], "Stop")

    def test_agent_defaults_to_claude(self):
        self.hook(None, "Stop", {"session_id": SID})
        self.assertEqual(self.app.next_message()["agent"], "claude")

    def test_replayed_hooks_are_dropped(self):
        # Cursor and Grok also run hooks registered for Claude Code
        self.hook("claude", "Stop", {"session_id": SID, "cursor_version": "2.0"})
        self.hook("claude", "Stop", {"session_id": SID, "hookEventName": "Stop"})
        self.assertSilent()
        self.hook("cursor", "stop", {"session_id": SID, "cursor_version": "2.0"})
        self.assertEqual(self.app.next_message()["agent"], "cursor")

    def test_bad_input_sends_nothing(self):
        for stdin in ("", "not json", "[1, 2]", '"text"'):
            with self.subTest(stdin=stdin):
                self.assertEqual(run_hook(self.app.path, "claude", "Stop", stdin), ("", 0))
        self.assertSilent()

    def test_missing_session_id_sends_nothing(self):
        self.assertEqual(self.hook("claude", "Stop", {}), ("", 0))
        self.assertSilent()


class UntrustedSocketTests(unittest.TestCase):
    """Only a socket we own, in a folder nobody else can write to, may answer
    approvals: otherwise another local user could pose as CrewNotch."""

    def test_socket_in_a_shared_folder(self):
        app = fake_app(self, {"decision": "allow"})
        os.chmod(app.dir, 0o777)
        self.assertEqual(ask(app.path), ("", 0))
        self.assertTrue(app.silent())

    def test_link_posing_as_the_socket(self):
        # A link to a live socket would connect fine; only the check stops it
        app = fake_app(self, {"decision": "allow"})
        link = missing_socket_path(self)
        os.symlink(app.path, link)
        self.assertEqual(ask(link), ("", 0))
        self.assertTrue(app.silent())


class AppUnavailableTests(unittest.TestCase):
    """The agent must carry on as if no hook existed."""

    def test_app_not_running(self):
        missing = missing_socket_path(self)
        started = time.monotonic()
        self.assertEqual(ask(missing), ("", 0))
        self.assertEqual(ask(missing, "cursor"), ("{}", 0))
        self.assertLess(time.monotonic() - started, 5)

    def test_stale_socket_file(self):
        app = fake_app(self)
        app.server.close()  # the socket file stays, nobody listens
        self.assertEqual(ask(app.path), ("", 0))


if __name__ == "__main__":
    unittest.main()
