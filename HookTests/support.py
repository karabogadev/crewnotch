"""
Shared helpers: a fake CrewNotch app listening on a private Unix socket,
and runners for the shipped scripts pointed at it through CREWNOTCH_SOCKET.
"""
import json
import os
import queue
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK = os.path.join(ROOT, "CrewNotch", "Resources", "crewnotch-hook.py")
CLI = os.path.join(ROOT, "CrewNotch", "Resources", "crewnotch-cli.py")

SID = "abc123"

# Sent instead of a reply: the app closes the connection without answering.
NO_REPLY = object()


class FakeApp:
    """Records every message sent to the socket, and answers approval
    requests (those the hook waits on) with `reply`: a JSON value, raw bytes,
    or NO_REPLY to close without answering."""

    def __init__(self, reply=NO_REPLY, prefix=b""):
        self.reply = reply
        self.prefix = prefix  # e.g. the app's liveness probe "\n"
        self.errors = []
        self.dir = tempfile.mkdtemp(prefix="cn")  # 0700, short enough for AF_UNIX
        self.path = os.path.join(self.dir, "s.sock")
        self.messages = queue.Queue()
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen(16)
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self):
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return  # closed
            try:
                with conn:
                    self._handle(conn)
            except (OSError, ValueError) as error:
                # Keep serving; the test that caused it fails in cleanup
                self.errors.append(error)

    def _handle(self, conn):
        data = b""
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                break
            data += chunk
        message = json.loads(data.decode())
        self.messages.put(message)
        waits = message.get("status") == "waiting_for_approval" and message.get("can_respond")
        if waits and self.reply is not NO_REPLY:
            body = self.reply if isinstance(self.reply, bytes) else json.dumps(self.reply).encode()
            conn.sendall(self.prefix + body)

    def next_message(self, timeout=3):
        return self.messages.get(timeout=timeout)

    def silent(self, wait=0.3):
        """True when nothing arrives within `wait` seconds."""
        try:
            self.messages.get(timeout=wait)
            return False
        except queue.Empty:
            return True

    def close(self):
        self.server.close()
        shutil.rmtree(self.dir, ignore_errors=True)


def fake_app(test, reply=NO_REPLY, prefix=b""):
    """A FakeApp that closes, and fails `test` on a server error, at cleanup."""
    app = FakeApp(reply, prefix)
    test.addCleanup(app.close)
    test.addCleanup(lambda: test.assertEqual(app.errors, [], "fake app failed to handle a message"))
    return app


def missing_socket_path(test):
    """A trusted folder with no socket in it: CrewNotch isn't running."""
    folder = tempfile.mkdtemp(prefix="cn")
    test.addCleanup(shutil.rmtree, folder, True)
    return os.path.join(folder, "s.sock")


def script_env(socket_path, **extra):
    env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ.get("HOME", "/tmp"),
           "CREWNOTCH_SOCKET": socket_path}
    env.update(extra)
    return env


def run_hook(socket_path, agent, event, stdin, **env):
    """Runs crewnotch-hook.py like an agent would. `stdin` is the payload
    (a dict) or raw text. Returns (stdout, exit code)."""
    args = [sys.executable, HOOK]
    if agent is not None:
        args += ["--agent", agent]
    if event is not None:
        args += ["--event", event]
    text = stdin if isinstance(stdin, str) else json.dumps(stdin)
    done = subprocess.run(args, input=text, capture_output=True, text=True,
                          env=script_env(socket_path, **env), timeout=15)
    return done.stdout.strip(), done.returncode


def run_cli(socket_path, *args, **env):
    """Runs `crewnotch <args>`; returns the CompletedProcess."""
    return subprocess.run([sys.executable, CLI] + list(args), capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, env=script_env(socket_path, **env), timeout=30)


class AppTestCase(unittest.TestCase):
    """A test with a fresh fake app and workspace folder."""

    reply = NO_REPLY

    def setUp(self):
        self.app = fake_app(self, self.reply)
        self.workspace = tempfile.mkdtemp(prefix="cn-ws")
        self.addCleanup(shutil.rmtree, self.workspace, True)

    def hook(self, agent, event, payload=None, **env):
        payload = dict(payload or {})
        payload.setdefault("cwd", self.workspace)
        return run_hook(self.app.path, agent, event, payload, **env)

    def assertSilent(self):
        self.assertTrue(self.app.silent(), "expected no message")
