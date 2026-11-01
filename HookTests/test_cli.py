"""
`crewnotch run <command>`: the command runs untouched, and the notch hears
when it starts and how it ended.
"""
import os
import signal
import stat
import unittest

from support import AppTestCase, fake_app, missing_socket_path, run_cli


class CommandRunTests(AppTestCase):
    def run_command(self, *args, **env):
        done = run_cli(self.app.path, "run", *args, **env)
        started = self.app.next_message()
        finished = self.app.next_message()
        return done, started, finished

    def test_successful_command(self):
        done, started, finished = self.run_command("echo", "hello world")
        self.assertEqual(done.returncode, 0)
        self.assertEqual(done.stdout, "hello world\n")  # output passes through

        # One row per terminal: the shell that ran us (here, the test) names it
        session = "command:%d" % os.getpid()
        self.assertEqual(started, {
            **started,
            "agent": "command", "session_id": session, "event": "UserPromptSubmit", "status": "processing",
            "prompt": "echo 'hello world'", "title": "echo 'hello world'", "can_respond": False, "pid": os.getpid(),
        })
        self.assertEqual(finished["session_id"], session)
        self.assertEqual(finished["event"], "Stop")
        self.assertEqual(finished["status"], "waiting_for_input")
        self.assertEqual(finished["exit_code"], 0)
        self.assertIsInstance(finished["duration_seconds"], float)
        self.assertTrue(finished["assistant_message"].startswith("Finished in"))
        self.assertNotIn("signal", finished)

    def test_title(self):
        for args in (["--title", "Deploy"], ["-t", "Deploy"], ["--title=Deploy"]):
            with self.subTest(args=args):
                _, started, _ = self.run_command(*args, "--", "true")
                self.assertEqual(started["title"], "Deploy")
                self.assertEqual(started["prompt"], "true")

    def test_shell_syntax_runs_through_the_shell(self):
        done, started, finished = self.run_command("echo one && echo two", SHELL="/bin/sh")
        self.assertEqual(done.stdout, "one\ntwo\n")
        self.assertEqual(started["prompt"], "echo one && echo two")
        self.assertEqual(finished["exit_code"], 0)

    def test_failing_command_keeps_its_exit_code(self):
        done, _, finished = self.run_command("/bin/sh", "-c", "exit 3")
        self.assertEqual(done.returncode, 3)
        self.assertEqual(finished["exit_code"], 3)
        self.assertTrue(finished["assistant_message"].startswith("Failed with exit code 3"))

    def test_command_killed_by_a_signal(self):
        done, _, finished = self.run_command("/bin/sh", "-c", "kill -TERM $$")
        self.assertEqual(finished["exit_code"], 128 + signal.SIGTERM)
        self.assertEqual(finished["signal"], signal.SIGTERM)
        self.assertTrue(finished["assistant_message"].startswith("Stopped after"))
        # Dies the same way, so a script or loop running it stops too
        self.assertEqual(done.returncode, -signal.SIGTERM)

    def test_missing_command(self):
        done, _, finished = self.run_command("/nonexistent/tool")
        self.assertEqual(done.returncode, 127)
        self.assertEqual(finished["exit_code"], 127)
        self.assertEqual(finished["duration_seconds"], 0)
        self.assertTrue(finished["assistant_message"].startswith("Couldn't start"))

    def test_command_without_permission_to_run(self):
        path = os.path.join(self.workspace, "script.sh")
        with open(path, "w") as script:
            script.write("#!/bin/sh\necho hi\n")
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        done, _, finished = self.run_command(path)
        self.assertEqual(done.returncode, 126)
        self.assertEqual(finished["exit_code"], 126)


class UsageTests(AppTestCase):
    def test_help(self):
        for args in ([], ["help"], ["--help"]):
            with self.subTest(args=args):
                done = run_cli(self.app.path, *args)
                self.assertEqual(done.returncode, 0)
                self.assertIn("usage: crewnotch run", done.stdout)
        self.assertSilent()

    def test_bad_usage(self):
        for args in (["run"], ["run", "--"], ["frobnicate"]):
            with self.subTest(args=args):
                done = run_cli(self.app.path, *args)
                self.assertEqual(done.returncode, 2)
                self.assertIn("usage: crewnotch run", done.stderr)
        self.assertSilent()


class AppUnavailableTests(unittest.TestCase):
    def test_command_still_runs_without_the_app(self):
        done = run_cli(missing_socket_path(self), "run", "/bin/sh", "-c", "echo ran; exit 4")
        self.assertEqual(done.stdout, "ran\n")
        self.assertEqual(done.returncode, 4)

    def test_untrusted_socket_hears_nothing(self):
        # The CLI keeps its own copy of the hook's trust check
        shared = fake_app(self)
        os.chmod(shared.dir, 0o777)
        linked = fake_app(self)
        link = missing_socket_path(self)
        os.symlink(linked.path, link)
        for app, path in ((shared, shared.path), (linked, link)):
            with self.subTest(path=path):
                done = run_cli(path, "run", "true")
                self.assertEqual(done.returncode, 0)
                self.assertTrue(app.silent())


if __name__ == "__main__":
    unittest.main()
