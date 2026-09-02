#!/usr/bin/env python3
"""Bridge for building Mesa's 32-bit RADV with zig targeting x86-windows-msvc.

Meson invokes this script in place of a compiler. We translate the invocation
to:

    zig cc -target x86-windows-msvc -include <zig_msvc_fix.h> [-loldnames] <args>

- Compiles (any command that will produce an object/library, or a pure info /
  preprocess probe) never get -loldnames: zig errors "coff does not support
  linking multiple objects into one" if -loldnames reaches a compile.
- Final links (and only those) add -loldnames.

zig.exe is found from $ZIG, then from PATH; override with the ZIG env var or
set ZIG to an absolute path inside the calling shell.
"""
import os
import shutil
import subprocess
import sys

ZIG = os.environ.get("ZIG", "zig")
MSVC_FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "zig_msvc_fix.h")

args = sys.argv[1:]

# Meson passes compile flags via a response file ("@<file>.rsp"). Those flags
# carry the -c / -o markers we need to tell a compile from the final link, so
# expand any @argfile into the token stream for the decision below (we still
# forward the original @argfile to zig, which decodes it natively).
expanded = []
for a in args:
    if a.startswith("@"):
        try:
            with open(a[1:], "r", encoding="utf-8", errors="replace") as f:
                expanded += f.read().replace("\n", " ").replace("\t", " ").split()
        except OSError:
            pass
    else:
        expanded.append(a)

# Determine whether meson is asking for a compile vs. the final link.
low = [t.strip("\"").lower() for t in expanded]
link = True
if "-c" in low or any(t.startswith("-e") for t in low):
    link = False
for i, t in enumerate(low):
    if t == "-o" and i + 1 < len(low) and low[i + 1].endswith((".obj", ".o", ".lib", ".a")):
        link = False
if any(a in ("--version", "-v", "-dumpversion", "-dumpmachine", "-print-prog-name") for a in expanded):
    link = False

cmd = [ZIG, "cc", "-target", "x86-windows-msvc", "-include", MSVC_FIX]
if link:
    cmd.append("-loldnames")
cmd += args

# Make ZIG an absolute path if a named zig exists, so the subprocess call is robust.
if cmd[0] == "zig" and shutil.which("zig") is not None:
    cmd[0] = shutil.which("zig")

sys.exit(subprocess.call(cmd))