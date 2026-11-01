#!/usr/bin/env python3
"""
crewnotch: show any long-running command in the CrewNotch notch.

    crewnotch run [--title TEXT] [--] <command> [args...]
    crewnotch run "npm test && npm run build"

The notch shows the command as working while it runs, and finished (with
how long it took and whether it failed) when it ends, with the same
sounds and banners as an agent finishing. Output, input and the exit code
pass through unchanged; if CrewNotch isn't running the command just runs.
"""
import errno
import json
import os
import shlex
import signal
import socket
import stat
import subprocess
import sys
import time

SOCKET_PATH = os.environ.get("CREWNOTCH_SOCKET") or os.path.expanduser("~/.crewnotch/crewnotch.sock")

USAGE = """usage: crewnotch run [--title TEXT] [--] <command> [args...]

Shows a command in the CrewNotch notch while it runs, and tells you when
it finishes. Examples:
  crewnotch run npm test
  crewnotch run --title "Deploy" -- ./deploy.sh production
  crewnotch run "make && make test"
"""


def socket_is_trusted(path):
    """Only talk to a socket we own, in a directory nobody else can write to."""
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


def send(state):
    state = {k: v for k, v in state.items() if v is not None}
    if not socket_is_trusted(SOCKET_PATH):
        return
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        sock.close()
    except OSError:
        pass


def git_branch(cwd):
    """The checked-out branch (or short commit) of the repo holding `cwd`.

    Read here, in the agent's process, so the app itself never touches
    folders macOS protects (Documents, Desktop, Downloads).
    """
    directory = cwd
    for _ in range(12):
        dot_git = os.path.join(directory, ".git")
        try:
            if os.path.isdir(dot_git):
                git_dir = dot_git
            elif os.path.isfile(dot_git):
                with open(dot_git) as handle:
                    pointer = handle.read().strip()
                if not pointer.startswith("gitdir:"):
                    return None
                git_dir = os.path.join(directory, pointer[len("gitdir:"):].strip())
            else:
                git_dir = None
            if git_dir:
                with open(os.path.join(git_dir, "HEAD")) as handle:
                    head = handle.read().strip()
                prefix = "ref: refs/heads/"
                return head[len(prefix):] if head.startswith(prefix) else head[:7]
        except (OSError, UnicodeDecodeError):
            return None
        parent = os.path.dirname(directory)
        if parent == directory:
            return None
        directory = parent
    return None


def tty_of(pid):
    try:
        out = subprocess.run(["ps", "-o", "tty=", "-p", str(pid)], capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return None
    if not out or out in ("??", "-"):
        return None
    return out if out.startswith("/dev/") else "/dev/" + out


def duration(seconds):
    seconds = int(round(seconds))
    if seconds < 60:
        return "%ds" % seconds
    minutes, seconds = divmod(seconds, 60)
    if minutes < 60:
        return "%dm %ds" % (minutes, seconds) if seconds else "%dm" % minutes
    hours, minutes = divmod(minutes, 60)
    return "%dh %dm" % (hours, minutes)


def parse_run_args(args):
    title = None
    while args:
        if args[0] == "--":
            args = args[1:]
            break
        if args[0] in ("--title", "-t") and len(args) > 1:
            title = args[1]
            args = args[2:]
        elif args[0].startswith("--title="):
            title = args[0].split("=", 1)[1]
            args = args[1:]
        else:
            break
    return title, args


def run(args):
    title, command = parse_run_args(args)
    if not command:
        sys.stderr.write(USAGE)
        return 2

    # One quoted argument with shell syntax runs through the user's shell
    if len(command) == 1 and any(c in command[0] for c in " |&;<>()$`*?"):
        display = command[0]
        argv = [os.environ.get("SHELL") or "/bin/zsh", "-c", command[0]]
    else:
        display = " ".join(shlex.quote(part) for part in command)
        argv = command

    # The session lives as long as the shell that ran us: one row per terminal.
    # A command sent to the background (`&`) gets its own row, so two at once don't mix.
    shell_pid = os.getppid()
    session_id = "command:%d" % shell_pid
    if not in_foreground():
        session_id += "-%d" % os.getpid()
    base = {
        "agent": "command",
        "session_id": session_id,
        "cwd": os.getcwd(),
        "pid": shell_pid,
        "tty": tty_of(shell_pid),
        "can_respond": False,
        "git_branch": git_branch(os.getcwd()),
    }

    # Handlers go in before the child starts, so a Ctrl-C in between can't
    # kill us and leave the notch saying "working". Caught signals revert to
    # the default in the child, so it still gets Ctrl-C from the terminal.
    child = None
    def forward(signum, _frame):
        if child is not None and signum != signal.SIGINT:  # the terminal already sent SIGINT to the child
            child.send_signal(signum)
    for handled in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(handled, forward)

    send(dict(base, event="UserPromptSubmit", status="processing",
              prompt=display[:4000], title=(title or display)[:120]))

    started = time.time()
    try:
        child = subprocess.Popen(argv)
    except OSError as error:
        code = 126 if error.errno in (errno.EACCES, errno.EPERM, errno.ENOEXEC) else 127
        sys.stderr.write("crewnotch: %s: %s\n" % (command[0], error.strerror))
        send(dict(base, event="Stop", status="waiting_for_input",
                  assistant_message="Couldn't start: %s" % error.strerror, exit_code=code, duration_seconds=0))
        return code

    while True:
        try:
            code = child.wait()
            break
        except InterruptedError:
            continue
    elapsed = duration(time.time() - started)

    if code == 0:
        summary = "Finished in %s" % elapsed
    elif code < 0 and -code in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        summary = "Stopped after %s" % elapsed
    else:
        summary = "Failed with exit code %d after %s" % (code if code > 0 else 128 - code, elapsed)
    exit_code = code if code >= 0 else 128 - code
    # The app words the summary in the user's language; this text is the fallback
    send(dict(base, event="Stop", status="waiting_for_input", assistant_message=summary,
              exit_code=exit_code, signal=-code if code < 0 else None,
              duration_seconds=round(time.time() - started, 1)))

    # Killed by a signal: die the same way, so a script or loop running us stops too
    if code < 0:
        signal.signal(-code, signal.SIG_DFL)
        os.kill(os.getpid(), -code)
    return exit_code


def in_foreground():
    """Whether we run in the terminal's foreground job (not `cmd &`)."""
    try:
        return os.tcgetpgrp(sys.stdin.fileno()) == os.getpgrp()
    except OSError:
        return True  # no terminal: treat as the shell's own command


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "help"):
        sys.stdout.write(USAGE)
        return 0
    if args[0] == "run":
        return run(args[1:])
    sys.stderr.write("crewnotch: unknown command '%s'\n\n%s" % (args[0], USAGE))
    return 2


if __name__ == "__main__":
    sys.exit(main())
