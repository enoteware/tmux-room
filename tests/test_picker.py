#!/usr/bin/env python3
"""Picker rendering bounds, selection visibility, and terminal sizing contracts."""
import fcntl
import os
from pathlib import Path
import pty
import re
import struct
import subprocess
import sys
import termios
import unicodedata
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "tmux-room"
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def renderer_source():
    source = SCRIPT.read_text().split("render_view_table() {", 1)[1]
    return source.split("python3 -c '\n", 1)[1].split("\n'\n}", 1)[0]


def fixture(selected=0, count=30, unavailable=0):
    statuses = [f"S\tdevice-{index:02}\tUnreachable\n" for index in range(unavailable)]
    rooms = [f"R\t{index + 1}\t{int(index == selected)}\t0\tmacbook\troom-{index:02} 晚上\tcodex\tneeds_input\t1\t1750000000\tWork in progress\n"
             for index in range(count)]
    return "".join(statuses + rooms)


def display_width(text):
    # Fixtures contain CJK and combining accents, without ambiguous emoji widths.
    return sum(0 if unicodedata.combining(char) else
               2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
               for char in text)


class PickerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = renderer_source()

    def render(self, width=80, height=24, data=None, **overrides):
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith("TMUX_ROOM_RENDER_") and key != "NO_COLOR"}
        environment.update(TERM="xterm-256color", TMUX_ROOM_RENDER_INTERACTIVE="1",
                           TMUX_ROOM_RENDER_WIDTH=str(width), TMUX_ROOM_RENDER_HEIGHT=str(height),
                           TMUX_ROOM_RENDER_HEADER="FLEET: 3 devices, 2 reachable, 1 unavailable",
                           TMUX_ROOM_RENDER_SUBHEADER="STATUS: Devices need attention.")
        environment.update(overrides)
        return subprocess.check_output([sys.executable, "-c", self.source],
                                       input=fixture() if data is None else data,
                                       text=True, env=environment, timeout=5)

    def assert_bounds(self, rendered, width, height):
        lines = ANSI.sub("", rendered).splitlines()
        self.assertLessEqual(len(lines), height - 1, "bottom newline must not scroll the terminal")
        for line in lines:
            self.assertLessEqual(display_width(line), width, repr(line))
        return lines

    def test_responsive_viewport_keeps_every_selection_visible(self):
        for width, height in ((40, 12), (80, 24), (160, 48)):
            for selected in (0, 14, 29):
                with self.subTest(width=width, height=height, selected=selected):
                    output = self.render(width, height, fixture(selected, unavailable=2))
                    lines = self.assert_bounds(output, width, height)
                    plain = "\n".join(lines)
                    self.assertRegex(plain, rf"> +room-{selected:02} 晚上")
                    self.assertIn("2 unavailable", plain)
                    self.assertIn("of 30", plain)
                    self.assertIn("Enter attach", plain)
                    self.assertIn("w watch", plain)
                    self.assertIn("q quit", plain)
                    if height >= 16:
                        self.assertIn("SELECTED", plain)
                        self.assertIn("Note: Work in progress", plain)
                    else:
                        self.assertNotIn("SELECTED", plain)
                    selected_lines = [line for line in output.splitlines() if "\x1b[7m" in line]
                    self.assertEqual(len(selected_lines), 2 if width < 64 else 1)
                    for line in selected_lines:
                        self.assertEqual(display_width(ANSI.sub("", line)), width)

    def test_all_rows_are_reachable_across_page_boundaries(self):
        for selected in range(30):
            with self.subTest(selected=selected):
                lines = self.assert_bounds(self.render(40, 12, fixture(selected)), 40, 12)
                self.assertRegex("\n".join(lines), rf"> +room-{selected:02} 晚上")

    def test_many_unavailable_devices_do_not_push_out_rooms(self):
        output = self.render(40, 12, fixture(29, unavailable=50))
        plain = "\n".join(self.assert_bounds(output, 40, 12))
        self.assertIn("50 unavailable", plain)
        self.assertIn("> room-29", plain)
        self.assertIn("q quit", plain)

    def test_empty_search_keeps_recovery_controls_and_query(self):
        output = self.render(40, 12, data="", TMUX_ROOM_RENDER_QUERY="missing")
        plain = "\n".join(self.assert_bounds(output, 40, 12))
        self.assertIn("SEARCH: missing", plain)
        self.assertIn("No rooms match this search.", plain)
        self.assertIn("c clear", plain)
        self.assertNotIn("Rooms 1-0", plain)

    def test_plain_terminal_modes_keep_selection_without_ansi(self):
        for options in ({"NO_COLOR": "1"}, {"NO_COLOR": ""}, {"TERM": "dumb"}):
            with self.subTest(options=options):
                output = self.render(**options)
                self.assertNotIn("\x1b", output)
                self.assertRegex(output, r"> +room-00")

    def test_listing_remains_unpaginated_without_picker_chrome(self):
        output = self.render(80, 12, fixture(selected=-1), TMUX_ROOM_RENDER_INTERACTIVE="0")
        self.assertIn("FLEET: 3 devices, 2 reachable, 1 unavailable", output)
        self.assertNotIn("TMUX ROOM", output)
        self.assertNotIn("SELECTED", output)
        self.assertNotIn("\x1b", output)
        for index in range(30):
            self.assertIn(f"room-{index:02}", output)



class TerminalSizingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SCRIPT.read_text()
        definitions = []
        for name in ("terminal_columns", "terminal_lines"):
            body = source.split(name + "() {", 1)[1].split("\n}\n", 1)[0]
            definitions.append(name + "() {" + body + "\n}")
        cls.program = "\n".join(definitions) + "\nterminal_columns; printf ' ' ; terminal_lines"

    def measure(self, tty_size=None, stderr_tty=False, **overrides):
        environment = {key: value for key, value in os.environ.items()
                       if key not in ("TMUX_ROOM_COLUMNS", "TMUX_ROOM_LINES", "COLUMNS", "LINES")}
        environment.update(overrides)
        if tty_size is None:
            return subprocess.check_output(["bash", "-c", self.program], stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                           env=environment, text=True, timeout=5)
        master, slave = pty.openpty()
        try:
            columns, rows = tty_size
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
            return subprocess.check_output(["bash", "-c", self.program],
                                           stdin=subprocess.DEVNULL if stderr_tty else slave,
                                           stderr=slave if stderr_tty else subprocess.DEVNULL,
                                           env=environment, text=True, timeout=5)
        finally:
            os.close(slave)
            os.close(master)

    def test_real_terminal_dimensions_override_stale_shell_values(self):
        for size in ((40, 12), (80, 24), (160, 48)):
            with self.subTest(size=size):
                self.assertEqual(self.measure(size, COLUMNS="120", LINES="30"),
                                 str(size[0]) + " " + str(size[1]))

    def test_piped_input_uses_terminal_on_stderr(self):
        self.assertEqual(self.measure((40, 12), stderr_tty=True), "40 12")
        self.assertEqual(self.measure((40, 12), stderr_tty=True,
                                     TMUX_ROOM_COLUMNS="80", TMUX_ROOM_LINES="24"), "80 24")

    def test_explicit_overrides_win_over_real_terminal(self):
        self.assertEqual(self.measure((160, 48), TMUX_ROOM_COLUMNS="080", TMUX_ROOM_LINES="024"), "80 24")

    def test_no_terminal_uses_shell_fallback_and_bounds(self):
        self.assertEqual(self.measure(COLUMNS="90", LINES="33"), "90 33")
        self.assertEqual(self.measure(TMUX_ROOM_COLUMNS="1", TMUX_ROOM_LINES="1"), "20 6")
        self.assertEqual(self.measure(TMUX_ROOM_COLUMNS="9999", TMUX_ROOM_LINES="9999"), "240 200")



class PickerInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        body = SCRIPT.read_text().split("read_picker_key() {", 1)[1].split("\n}\n", 1)[0]
        cls.program = "read_picker_key() {" + body + "\n}\nread_picker_key; printf '%s' \"$?\""

    def test_idle_real_terminal_redraws_instead_of_exiting(self):
        master, slave = pty.openpty()
        try:
            result = subprocess.check_output(["/bin/bash", "-c", self.program],
                                             stdin=slave, text=True, timeout=4)
            self.assertEqual(result, "2", "Bash 3.2 returns 1 on read timeout; picker must redraw")
        finally:
            os.close(slave)
            os.close(master)

    def test_immediate_eof_exits_instead_of_redraw_loop(self):
        result = subprocess.check_output(["/bin/bash", "-c", self.program],
                                         stdin=subprocess.DEVNULL, text=True, timeout=2)
        self.assertEqual(result, "1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
