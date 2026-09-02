#!/usr/bin/env python3
"""Bridge Meson's resource-compiler interface to zig rc.

Meson probes:
  --version  expects "GNU windres" -> ResourceCompilerType.windres
  /?         expects Microsoft pattern -> ResourceCompilerType.rc

We answer /? as Microsoft RC so Meson uses the MS rc interface, which
zig rc (a drop-in MS RC) accepts verbatim. GNU `-i in -o out` calls are
translated to `zig rc /fo out in` for the windres interface.
"""
import subprocess
import sys

zig = "zig"
args = sys.argv[1:]

if any(a == "--version" for a in args):
    sys.stdout.write("GNU windres (GNU Binutils) 2.46.0\n")
    sys.exit(0)

if any(a in ("/?", "-h", "--help") for a in args):
    sys.stdout.write("Microsoft (R) Windows (R) Resource Compiler Version (zig rc)\n")
    sys.exit(0)

# MS rc style: forward verbatim.
if any(a == "/fo" or (a.startswith("/fo") and len(a) > 3) for a in args):
    cmd = [zig, "rc"] + args
    rc = subprocess.run(cmd)
    sys.exit(rc.returncode)

# GNU windres style (-i in -o out): translate.
out = None
inc = []
defines = []
infile = None
i = 0
while i < len(args):
    a = args[i]
    if a == "-o" and i + 1 < len(args):
        out = args[i + 1]
        i += 2
        continue
    if a == "-i" and i + 1 < len(args):
        infile = args[i + 1]
        i += 2
        continue
    if a in ("-O", "--include-dir", "--language") and i + 1 < len(args):
        needle = "-I" if a == "--include-dir" else None
        if needle:
            inc.append(args[i + 1])
        i += 2
        continue
    if a == "-D" and i + 1 < len(args):
        defines.append(a + args[i + 1])
        i += 2
        continue
    if a == "--define" and i + 1 < len(args):
        defines.append("-D" + args[i + 1])
        i += 2
        continue
    if a.startswith("-I") and len(a) > 2:
        inc.append(a[2:])
        i += 1
        continue
    if a == "-I" and i + 1 < len(args):
        inc.append(args[i + 1])
        i += 2
        continue
    if a.startswith("-D") and not a.startswith("--"):
        defines.append(a)
        i += 1
        continue
    if a.startswith("--"):
        i += 1
        continue
    if a.startswith("-") and not a.startswith("--"):
        i += 1
        continue
    if infile is None:
        infile = a
        i += 1
        continue
    i += 1

if infile is None or out is None:
    sys.stderr.write("zig_windres: missing input/output: %r\n" % (args,))
    sys.exit(1)

cmd = [zig, "rc"]
for d in defines:
    cmd.append(d)
for p in inc:
    cmd.append("/i")
    cmd.append(p)
cmd.append("/fo")
cmd.append(out)
cmd.append(infile)

rc = subprocess.run(cmd)
sys.exit(rc.returncode)