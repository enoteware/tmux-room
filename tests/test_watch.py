#!/usr/bin/env python3
"""Focused safety, layout, and terminal integration checks for the watch view."""
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import shlex
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "tmux-room"


def set_terminal_size(fd, columns, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))


def read_until(fd, process, predicate, timeout=10):
    output = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.1)[0]:
            try:
                block = os.read(fd, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not block:
                break
            output.extend(block)
            if predicate(bytes(output)):
                return bytes(output)
        if process.poll() is not None:
            break
    raise AssertionError("terminal did not reach expected state: " + repr(bytes(output)[-2000:]))


def room_record(name="alpha", room_id="$1"):
    return {
        "id": room_id,
        "name": name,
        "windows": 1,
        "attached": False,
        "created_at": 1,
        "activity_at": 1,
        "path": "/tmp",
        "metadata": {"driver": "codex", "state": "running", "fresh": True},
    }


def fleet_fixture():
    return {
        "schema": "tmux-room.fleet",
        "schema_version": 1,
        "generated_at": 1,
        "complete": True,
        "devices": [{"name": "local", "source": "local", "status": "reachable",
                     "rooms": [room_record(), room_record("beta", "$2")]}],
    }


def source_code():
    text = SCRIPT.read_text()
    if "run_watch() {" not in text:
        raise AssertionError("run_watch implementation missing")
    return text.split("run_watch() {", 1)[1].split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]


def load_watch():
    namespace = {"__name__": "watch_test_module"}
    with mock.patch.object(sys, "argv", ["watch", str(SCRIPT), "/nonexistent/hosts", "PATH=/usr/bin:/bin"]):
        exec(compile(source_code(), str(SCRIPT) + ":watch", "exec"), namespace)
    return namespace


class WatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.watch = load_watch()

    def setUp(self):
        self.watch["STOP"].clear()

    def test_layout_adapts_and_paginates(self):
        previous = 0
        for width, height in ((40, 12), (80, 24), (160, 48)):
            with self.subTest(width=width, height=height):
                columns, rows, capacity = self.watch["layout"](height, width, 20)
                self.assertGreaterEqual(columns, 1)
                self.assertGreaterEqual(rows, 1)
                self.assertEqual(capacity, columns * rows)
                self.assertGreaterEqual(capacity, previous)
                self.assertLessEqual(capacity, 20)
                for offset in range(capacity):
                    col, row = offset % columns, offset // columns
                    left = col * width // columns
                    right = (col + 1) * width // columns
                    top = 2 + row * (height - 4) // rows
                    bottom = 2 + (row + 1) * (height - 4) // rows
                    self.assertLess(left, right)
                    self.assertLess(top, bottom)
                    self.assertLessEqual(right, width)
                    self.assertLessEqual(bottom, height - 2)
                previous = capacity
        self.assertEqual(self.watch["layout"](12, 40, 20)[2], 1)
        self.assertGreater(self.watch["layout"](48, 160, 20)[0], 1)

    def test_unicode_clip_respects_cells_and_accents(self):
        fit = self.watch["fit"]
        self.assertEqual(fit("\u754c\u754cabc", 3), "\u754c")
        self.assertEqual(fit("e\u0301clair", 1), "e\u0301")
        self.assertEqual(fit("\u0301a", 1), "a")
        self.assertEqual(fit("hello", 0), "")
        self.assertEqual(fit("hello", -1), "")

    def test_terminal_controls_are_removed(self):
        clean = self.watch["clean"]
        self.assertEqual(clean("\x1b[31mred\x1b[0m\x07"), "red")
        self.assertEqual(clean("before\x1b]52;c;c2VjcmV0\x07after"), "beforeafter")
        self.assertEqual(clean("\x1b]0;title\x1b\\visible"), "visible")
        self.assertNotIn("\x9b", clean("\x9b31mvalue"))
        self.assertEqual(clean("a\r\x00b"), "ab")

    def test_attention_filter_uses_explicit_status(self):
        rooms = [dict(room_record(), source="local", device="mini"),
                 dict(room_record("help"), source="remote", device="devbox"),
                 dict(room_record("broken"), source="local", device="mini")]
        rooms[1]["metadata"]["state"] = "needs_input"
        rooms[2]["metadata"]["state"] = "failed"
        result = self.watch["filtered"](rooms, "", True)
        self.assertEqual([room["name"] for room in result], ["help", "broken"])
        self.assertEqual([room["name"] for room in self.watch["filtered"](rooms, "DEVBOX", False)], ["help"])

    def test_capture_rejects_replaced_session(self):
        with mock.patch.object(sys, "argv", ["capture", "$1", "alpha", "10"]), \
                mock.patch("subprocess.check_output", side_effect=[b"$1|alpha|%4\n", b"old output\n", b"$2|alpha|%9\n"]):
            with self.assertRaises((AssertionError, RuntimeError)):
                exec(self.watch["CAPTURE"], {"__name__": "capture_test"})

    def test_capture_rejects_wrong_name_before_reading_pane(self):
        with mock.patch.object(sys, "argv", ["capture", "$1", "alpha", "10"]), \
                mock.patch("subprocess.check_output", return_value=b"$1|replacement|%4\n") as output:
            with self.assertRaises((AssertionError, RuntimeError)):
                exec(self.watch["CAPTURE"], {"__name__": "capture_test"})
        self.assertEqual(output.call_count, 1)

    def test_capture_uses_immutable_pane_and_is_read_only(self):
        with mock.patch.object(sys, "argv", ["capture", "$1", "alpha", "999"]), \
                mock.patch("subprocess.check_output", side_effect=[b"$1|alpha|%4\n", b"output\n", b"$1|alpha|%4\n"]) as output, \
                mock.patch("builtins.print") as printed:
            exec(self.watch["CAPTURE"], {"__name__": "capture_test"})
        self.assertEqual(output.call_args_list[1][0][0],
                         ["tmux", "capture-pane", "-p", "-t", "%4", "-S", "-80"])
        self.assertEqual(json.loads(printed.call_args[0][0])["pane"], "%4")
        self.assertEqual([call[0][0][1] for call in output.call_args_list],
                         ["display-message", "capture-pane", "display-message"])

    def test_capture_keeps_visible_output_above_blank_screen_tail(self):
        room = dict(room_record(), source="local", device="mini")
        payload = json.dumps({"pane": "%4", "text": "VISIBLE\n" + "\n" * 30})
        with mock.patch.dict(self.watch, {"bounded": lambda argv: payload}):
            pane, lines = self.watch["capture"](room, 5)
        self.assertEqual(pane, "%4")
        self.assertEqual(lines[-1], "VISIBLE")

    def test_remote_capture_quotes_identity_and_uses_noninteractive_ssh(self):
        room = dict(room_record("space; $(touch nope) 'room'"), source="remote", device="mini")
        commands = []

        def bounded(argv):
            commands.append(argv)
            return json.dumps({"pane": "%4", "text": "safe preview\n"})

        with mock.patch.dict(self.watch, {"bounded": bounded, "hosts": lambda: {"mini": "agent@mini-host"}}):
            self.assertEqual(self.watch["capture"](room, 12), ("%4", ["safe preview"]))
        self.assertEqual(len(commands), 1)
        argv = commands[0]
        self.assertEqual(argv[0], "ssh")
        self.assertIn("-n", argv)
        self.assertIn("BatchMode=yes", argv)
        self.assertNotIn("-t", argv)
        self.assertEqual(argv[-2], "agent@mini-host")
        self.assertEqual(shlex.split(argv[-1]), ["/usr/bin/env", "PATH=/usr/bin:/bin",
            "python3", "-c", self.watch["CAPTURE"], "$1", room["name"], "12"])

    def test_capture_timeout_is_bounded(self):
        started = time.monotonic()
        with self.assertRaisesRegex(RuntimeError, "timed out"):
            self.watch["bounded"]([sys.executable, "-c", "import time; time.sleep(10)"], timeout=0.2)
        self.assertLess(time.monotonic() - started, 2)

    def test_capture_output_is_bounded(self):
        with self.assertRaisesRegex(RuntimeError, "limit"):
            self.watch["bounded"]([sys.executable, "-c", "print('x' * 65536)"], limit=1024)

    def test_stop_cancels_inflight_work(self):
        self.watch["STOP"].set()
        started = time.monotonic()
        with self.assertRaises(RuntimeError):
            self.watch["bounded"]([sys.executable, "-c", "import time; time.sleep(10)"])
        self.assertLess(time.monotonic() - started, 2)

    def test_pty_launch_resize_and_quit(self):
        with tempfile.TemporaryDirectory(prefix="tmux-room-watch-test-") as temporary:
            base = Path(temporary)
            inventory = base / "fleet.json"
            inventory.write_text(json.dumps(fleet_fixture()))
            fixture_script = base / "tmux-room"
            fixture_script.write_text("#!" + sys.executable + "\nimport pathlib\nprint(pathlib.Path(" + repr(str(inventory)) + ").read_text())\n")
            fixture_script.chmod(0o755)
            capture_log = base / "tmux.log"
            fixture_tmux = base / "tmux"
            fixture_tmux.write_text("#!" + sys.executable + "\n" +
                "import os, sys\n" +
                "with open(os.environ['WATCH_TEST_LOG'], 'a') as log: log.write(repr(sys.argv[1:]) + '\\n')\n" +
                "if sys.argv[1] == 'display-message':\n" +
                " sid = sys.argv[sys.argv.index('-t')+1].rstrip(':')\n" +
                " print(sid + '|' + ('alpha' if sid == '$1' else 'beta') + '|%4')\n" +
                "elif sys.argv[1] == 'capture-pane': print('PREVIEW_MARKER')\n" +
                "else: raise SystemExit(91)\n")
            fixture_tmux.chmod(0o755)
            program = base / "watch.py"
            program.write_text(source_code())
            environment = dict(os.environ, TERM="xterm-256color", WATCH_TEST_LOG=str(capture_log),
                               PATH=str(base) + os.pathsep + os.environ.get("PATH", ""))
            master, slave = pty.openpty()
            set_terminal_size(slave, 160, 48)

            def controlling_terminal():
                os.setsid()
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)

            process = subprocess.Popen([sys.executable, str(program), str(fixture_script), str(base / "hosts"), "PATH=/usr/bin:/bin"],
                stdin=slave, stdout=slave, stderr=slave, env=environment, preexec_fn=controlling_terminal)
            os.close(slave)
            try:
                read_until(master, process, lambda data: b"PREVIEW_MARKER" in data)
                for columns, rows in ((40, 12), (80, 24), (160, 48)):
                    set_terminal_size(master, columns, rows)
                    os.kill(process.pid, signal.SIGWINCH)
                    os.write(master, b"c")
                    read_until(master, process, lambda data: b"WATCH" in data)
                    self.assertIsNone(process.poll(), "dashboard exited on resize")
                os.write(master, b"q")
                deadline = time.monotonic() + 4
                while process.poll() is None and time.monotonic() < deadline:
                    if select.select([master], [], [], 0.1)[0]:
                        try:
                            os.read(master, 65536)
                        except OSError as error:
                            if error.errno != errno.EIO:
                                raise
                self.assertEqual(process.poll(), 0, "watch did not quit promptly")
                logged = capture_log.read_text()
                self.assertIn("capture-pane", logged)
                for mutation in ("attach-session", "switch-client", "send-keys", "resize-pane", "kill-session"):
                    self.assertNotIn(mutation, logged)
            finally:
                if process.poll() is None:
                    process.kill()
                    os.close(master)
                    master = None
                    process.wait(timeout=3)
                if master is not None:
                    os.close(master)


if __name__ == "__main__":
    unittest.main(verbosity=2)
