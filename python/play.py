#!/usr/bin/env python3
"""
play.py — minimal RemGlk client for the flutterbug-terps binaries.

Spawns the right interpreter for a story file, exchanges RemGlk JSON
events with it over stdio, and renders the resulting text in a
plain terminal. Just enough to confirm a build works; not a real player.

Usage:
    python play.py path/to/story.ulx
    python play.py --vm git path/to/story.ulx       # force a specific terp
    python play.py --rem path/to/story.ulx          # raw JSON passthrough
    python play.py --build-dir ../other path/to/x   # alternate build dir

Defaults assume the layout
    flutterbug-terps/build/             # binaries
    flutterbug-terps/python/play.py     # this script
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path
from typing import Iterator, TextIO

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUILD_DIR = REPO_ROOT / "build"

# Magic-byte probes, ported from garglk/garglk/launcher.cpp::probe(). First
# 32 bytes of the file are matched against these byte regexes in order; first
# hit wins. Some formats have no useful magic (Scott Adams platform-specific
# disks, JACL, Plus, Taylor — see EXTENSIONS below).
MAGIC_PROBES: list[tuple[str, re.Pattern[bytes]]] = [
    ("bocfel",   re.compile(rb"^[\x01-\x08][\s\S]{17}\d{6}")),
    ("tads",     re.compile(rb"^TADS2 bin\x0a\x0d\x1a")),
    ("tads",     re.compile(rb"^T3-image\x0d\x0a\x1a[\x01\x02]\x00")),
    ("glulxe",   re.compile(rb"^Glul")),
    ("magnetic", re.compile(rb"^MaSc[\s\S]{4}\x00\x00\x00\x2a\x00[\x00-\x04]")),
    ("scare",    re.compile(rb"^\x3c\x42\x3f\xc9\x6a\x87\xc2\xcf[\x93\x94]\x45")),
    ("agility",  re.compile(rb"^\x58\xc7\xc1\x51")),
    ("advsys",   re.compile(rb"^[\s\S]{2}\xa0\x9d\x8b\x8e\x88\x8e")),
    ("hugo",     re.compile(rb"^[\x16\x18\x19\x1e\x1f][\s\S]{2}\d\d-\d\d-\d\d")),
    ("level9",   re.compile(rb"^[\s\S]{3}\x9b\x36\x21[\s\S]{18}\xff")),
    ("alan2",    re.compile(rb"^\x02(\x07\x05|\x08[\x01\x02\x03\x07])")),
    ("alan3",    re.compile(rb"^ALAN\x03")),
]

# Extension fallback for formats without a usable magic header (or to give
# users a quick path when the magic probe fails). Lowercase keys; matched
# against suffix without leading dot.
EXTENSIONS: dict[str, str] = {
    # Z-machine
    "z1": "bocfel", "z2": "bocfel", "z3": "bocfel", "z4": "bocfel",
    "z5": "bocfel", "z6": "bocfel", "z7": "bocfel", "z8": "bocfel",
    "zblorb": "bocfel", "zlb": "bocfel",
    # Glulx
    "ulx": "glulxe", "gblorb": "glulxe", "blb": "glulxe", "blorb": "glulxe",
    # TADS
    "gam": "tads", "t3": "tads",
    # Other native formats
    "hex": "hugo", "hxs": "hugo",
    "taf": "scare",
    "acd": "alan2",
    "a3c": "alan3",
    "j2": "jacl", "jacl": "jacl",
    "agx": "agility", "d$$": "agility", "aag": "agility",
    "mag": "magnetic",
    # Disk/snapshot images. These overlap heavily — magic probe never
    # resolves them (each is platform-native, not IF-format-native), so the
    # extension is the only signal. Defaults below match garglk's launcher;
    # use --vm to force a different terp for ambiguous cases.
    "saga": "scott",
    "tay": "taylor",
    "l9": "level9", "sna": "level9",  # garglk maps .sna → level9
    "atr": "plus", "xex": "plus", "po": "plus", "plus": "plus",
    "dat": "scott",   # ambiguous (advsys/scott/level9); --vm to override
    "d64": "scott",   # ambiguous (plus/scott/taylor); --vm to override
    "z80": "taylor",  # Spectrum snapshot for taylor
    "tap": "taylor", "tzx": "taylor",
}

# Filename patterns for cases where extension alone isn't enough.
FILENAME_RULES: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"GAMEDAT\d\.DAT$", re.I), "level9"),
]

# Only this many terps deviate from "binary name = target name".
BINARY_NAME = {
    "tads": "tadsr",
}


def detect_vm(storyfile: str) -> str:
    name = os.fspath(storyfile)

    # 1. Magic-byte probe — most reliable for native IF formats.
    try:
        with open(storyfile, "rb") as f:
            head = f.read(32)
        for vm, regex in MAGIC_PROBES:
            if regex.search(head):
                return vm
    except OSError:
        pass

    # 2. Filename pattern rules (e.g. GAMEDAT*.DAT → level9).
    for pat, vm in FILENAME_RULES:
        if pat.search(name):
            return vm

    # 3. Extension fallback for platform-image formats and unrecognized
    #    headers.
    ext = os.path.splitext(name)[1].lstrip(".").lower()
    if ext in EXTENSIONS:
        return EXTENSIONS[ext]

    raise SystemExit(
        f"could not detect VM from {name!r}\n"
        f"  pass --vm <name> to force one of: "
        f"{sorted(set(EXTENSIONS.values()))}"
    )


def find_binary(vm: str, build_dir: Path) -> Path:
    candidate = build_dir / BINARY_NAME.get(vm, vm)
    if not candidate.exists():
        raise SystemExit(f"binary not found: {candidate}\n"
                         f"  build it with `make {vm}` from {build_dir}")
    return candidate


# ---------------------------------------------------------------------------
# VMRunner — wrap a subprocess and exchange line-delimited RemGlk JSON.
# ---------------------------------------------------------------------------

class VMRunner:
    def __init__(self, storyfile: str, vm: str, build_dir: Path):
        self.storyfile = storyfile
        self.vm = vm
        self.binary = find_binary(vm, build_dir)
        self.proc: subprocess.Popen | None = None

    def __enter__(self) -> "VMRunner":
        self.proc = subprocess.Popen(
            [str(self.binary), self.storyfile],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def send(self, event: dict) -> None:
        assert self.proc and self.proc.stdin
        try:
            self.proc.stdin.write(json.dumps(event) + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, OSError):
            pass

    def recv(self) -> dict | None:
        """Read one update line. Returns None at EOF."""
        assert self.proc and self.proc.stdout
        while True:
            line = self.proc.stdout.readline()
            if not line:
                return None
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue

    def close(self) -> None:
        if not self.proc:
            return
        try:
            if self.proc.stdin:
                try: self.proc.stdin.close()
                except OSError: pass
            try:
                self.proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self.proc.send_signal(signal.SIGTERM)
                try: self.proc.wait(timeout=1.0)
                except subprocess.TimeoutExpired: self.proc.kill()
        finally:
            self.proc = None


# ---------------------------------------------------------------------------
# Cheap console renderer.
# ---------------------------------------------------------------------------

def _terminal_size() -> tuple[int, int]:
    s = shutil.get_terminal_size(fallback=(80, 50))
    return s.columns, max(s.lines, 5)


def _render_grid_lines(window: dict) -> list[str]:
    out = []
    for line in window.get("lines", []):
        out.append("".join(c.get("text", "") for c in line.get("content", [])))
    return out


def _render_buffer_paragraphs(window: dict) -> list[str]:
    """Flatten a buffer-window text update to plain lines."""
    out: list[str] = []
    for para in window.get("text", []):
        chunks = "".join(c.get("text", "") for c in para.get("content", []))
        if para.get("append") and out:
            out[-1] += chunks
        else:
            out.append(chunks)
    return out


def run_console(runner: VMRunner, *, stdin: TextIO = sys.stdin,
                stdout: TextIO = sys.stdout) -> int:
    width, height = _terminal_size()
    runner.send({
        "type": "init",
        "gen": 0,
        "metrics": {"width": width, "height": height},
        "support": ["timer"],
    })

    last_grid: list[str] = []
    gen = 0

    while True:
        update = runner.recv()
        if update is None:
            return 0
        if update.get("type") != "update":
            continue
        if update.get("disable"):
            # Game is shutting down; drain remaining updates and exit.
            return 0

        gen = update.get("gen", gen)

        # Draw any new buffer-window content.
        for w in update.get("content", []):
            if "lines" in w:
                last_grid = _render_grid_lines(w)
            elif "text" in w:
                for para in _render_buffer_paragraphs(w):
                    stdout.write(para + "\n")

        # Re-print the (most recent) grid window above the prompt as a
        # reverse-video status bar.
        if last_grid:
            for line in last_grid:
                stdout.write(f"\x1b[7m{line[:width]:<{width}}\x1b[0m\n")
        stdout.flush()

        inputs = update.get("input") or []
        if not inputs:
            continue

        req = inputs[0]
        kind = req.get("type")
        win = req.get("id")
        gen = req.get("gen", gen)

        try:
            if kind == "line":
                stdout.write("> ")
                stdout.flush()
                line = stdin.readline()
                if not line:
                    return 0
                runner.send({"type": "line", "gen": gen,
                             "window": win, "value": line.rstrip("\n")})
            elif kind == "char":
                stdout.write("[press Enter for any-key, or one char + Enter] ")
                stdout.flush()
                line = stdin.readline()
                if not line:
                    return 0
                ch = line[:1] if line and line[0] != "\n" else "return"
                runner.send({"type": "char", "gen": gen,
                             "window": win, "value": ch})
            else:
                stdout.write(f"[unsupported input type: {kind}]\n")
                return 1
        except (BrokenPipeError, OSError):
            return 0


def run_passthrough(runner: VMRunner) -> int:
    """Forward stdin -> VM stdin and VM stdout -> stdout, line-delimited JSON."""
    import select
    proc = runner.proc
    assert proc and proc.stdin and proc.stdout
    in_fd = sys.stdin.fileno()
    out_fd = proc.stdout.fileno()

    while True:
        rlist, _, _ = select.select([in_fd, out_fd], [], [])
        if out_fd in rlist:
            line = proc.stdout.readline()
            if not line:
                break
            sys.stdout.write(line)
            sys.stdout.flush()
        if in_fd in rlist:
            data = os.read(in_fd, 4096)
            if not data:
                try: proc.stdin.close()
                except OSError: pass
                for line in proc.stdout:
                    sys.stdout.write(line)
                break
            proc.stdin.write(data.decode("utf-8", errors="replace"))
            proc.stdin.flush()
    return proc.wait()


# ---------------------------------------------------------------------------
# CLI entry point.
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        prog="play.py",
        description="Run an IF interpreter from flutterbug-terps build/ "
                    "against a story file. Cheap console mode by default.")
    p.add_argument("storyfile", help="path to the story file")
    p.add_argument("--vm", help="force a specific terp (default: detect by extension)")
    p.add_argument("--rem", action="store_true",
                   help="passthrough RemGlk JSON on stdio (machine-readable)")
    p.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR,
                   help=f"directory containing the terp binaries "
                        f"(default: {DEFAULT_BUILD_DIR})")
    args = p.parse_args(argv)

    vm = args.vm or detect_vm(args.storyfile)

    with VMRunner(args.storyfile, vm=vm, build_dir=args.build_dir) as runner:
        if args.rem:
            return run_passthrough(runner)
        return run_console(runner)


if __name__ == "__main__":
    sys.exit(main())
