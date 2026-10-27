#!/usr/bin/env python3
"""Watch an Obsidian vault for Markdown changes using Linux inotify."""

from __future__ import annotations

import ctypes
import errno
import json
import os
import select
import struct
import sys
import time
from pathlib import Path

MASK = (0x00000008 | 0x00000040 | 0x00000080 | 0x00000100 | 0x00000200 |
        0x00000400 | 0x00000800 | 0x00004000 | 0x00008000)
IN_IGNORED = 0x00008000
IN_Q_OVERFLOW = 0x00004000
IN_ISDIR = 0x40000000
EXCLUDED = {".obsidian", ".git", ".trash", "_trash", "node_modules"}
EVENT = struct.Struct("iIII")


def emit(kind: str, path: str = "") -> None:
    print(json.dumps({"event": kind, "path": path}, separators=(",", ":")), flush=True)


def ignored_dir(name: str) -> bool:
    return name.startswith(".") or name in EXCLUDED


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    vault = Path(sys.argv[1]).expanduser()
    libc = ctypes.CDLL(None, use_errno=True)
    init = libc.inotify_init1
    init.argtypes = [ctypes.c_int]
    init.restype = ctypes.c_int
    add_watch = libc.inotify_add_watch
    add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    add_watch.restype = ctypes.c_int
    fd = init(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd < 0:
        print(os.strerror(ctypes.get_errno()), file=sys.stderr)
        return 1

    watches: dict[int, str] = {}
    announced = False

    def add_tree() -> None:
        nonlocal announced
        root = vault.resolve(strict=False)
        if not root.is_dir():
            return
        for current, dirs, _files in os.walk(root, followlinks=False):
            dirs[:] = [d for d in dirs if not ignored_dir(d) and not (Path(current) / d).is_symlink()]
            wd = add_watch(fd, os.fsencode(current), MASK)
            if wd < 0:
                err = ctypes.get_errno()
                if err not in (errno.EACCES, errno.ENOENT, errno.ENOSPC):
                    emit("error")
                continue
            watches[wd] = current
        if not announced:
            emit("ready")
            announced = True

    try:
        while True:
            if not announced:
                add_tree()
                if not announced:
                    time.sleep(3)
                    continue
            readable, _, _ = select.select([fd], [], [], 5)
            if not readable:
                # A removable vault may disappear and later return.
                if not vault.is_dir():
                    watches.clear()
                    announced = False
                continue
            try:
                payload = os.read(fd, 256 * 1024)
            except BlockingIOError:
                continue
            offset = 0
            changed: set[str] = set()
            while offset + EVENT.size <= len(payload):
                wd, mask, _cookie, name_len = EVENT.unpack_from(payload, offset)
                offset += EVENT.size
                raw_name = payload[offset:offset + name_len].split(b"\0", 1)[0]
                offset += name_len
                if mask & IN_Q_OVERFLOW:
                    emit("change")
                    continue
                directory = watches.get(wd)
                if mask & IN_IGNORED:
                    watches.pop(wd, None)
                    continue
                if directory is None:
                    continue
                name = os.fsdecode(raw_name) if raw_name else ""
                full_path = Path(directory) / name if name else Path(directory)
                if mask & IN_ISDIR:
                    if name and (mask & (0x00000100 | 0x00000080)) and not ignored_dir(name):
                        for current, dirs, _files in os.walk(full_path, followlinks=False):
                            dirs[:] = [d for d in dirs if not ignored_dir(d) and not (Path(current) / d).is_symlink()]
                            new_wd = add_watch(fd, os.fsencode(current), MASK)
                            if new_wd >= 0:
                                watches[new_wd] = current
                    continue
                if full_path.suffix.lower() in {".md", ".markdown"}:
                    try:
                        relative = full_path.relative_to(vault.resolve(strict=False)).as_posix()
                    except ValueError:
                        relative = ""
                    if relative:
                        changed.add(relative)
            for relative in sorted(changed):
                emit("change", relative)
    finally:
        os.close(fd)


if __name__ == "__main__":
    raise SystemExit(main())
