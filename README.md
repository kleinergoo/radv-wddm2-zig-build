# radv-wddm2-zig-build

Build [Mesa](https://gitlab.freedesktop.org/mesa/mesa) **RADV** — the open-source
AMD Vulkan driver (wddm2 winsys) — for **64-bit and 32-bit Windows**, using the
**Zig `cc` toolchain targeting `x86_64-windows-msvc` / `x86-windows-msvc`**. No
WSL, no Visual Studio project, no MinGW: a fresh CI build compiles and links
`vulkan_radeon.dll` purely with Zig + the bundled Windows SDK, then emits a
ready-to-use Vulkan **ICD JSON** for each architecture.

It builds **https://github.com/kleinergoo/mesa-radv-wddm2** — the Vortex/Valve
wddm2 winsys branch of Mesa — pristine (CI clones it fresh, applies no patches).

CI (GitHub Actions, `windows-latest`) builds **both** architectures from pristine
upstream and uploads:
- `vulkan_radeon.dll` (per-arch zip artifact),
- `<arch>` **ICD JSON** (per-arch artifact).

Success in CI = both DLLs link cleanly + both ICD JSONs are produced. There is no
GPU run on the runners (no display / physical device).

---

## Layout

```
radv-wddm2-zig-build/
├─ .github/workflows/build.yml     # CI: auto-provisions tools, builds 64+32, uploads artifacts
├─ zb/
│  ├─ build.ps1                    # configure (meson) + build (ninja) for an -Arch; renders ini
│  ├─ make_icd.ps1                 # write an ICD JSON pointing at a built DLL (auto bitness)
│  ├─ zig_msvc_fix.h               # forced include: _Interlocked* intrinsics aliases (MSVC names under clang)
│  ├─ zig_windres.py               # adapts Meson's RC probing + calls `zig rc`
│  └─ zig-x86-cc.py                # 32-bit compiler wrapper: -target x86-windows-msvc + fix + -loldnames
└─ README.md
```

The `zb/build.ps1` renders the actual meson **native file (64-bit)** / **cross file
(32-bit)** at build time with repo-absolute paths, then runs
`meson setup` + `ninja`. The 32-bit wrapper matters because clang-as-MSVC needs the
`_Interlocked*` intrinsics supplied via the forced include, and `-loldnames` is only
added on real links.

---

## Requirements

- Windows (the build runs on GitHub Actions `windows-latest` automatically).
- **zig 0.16.0** (pinned in CI via `mlugg/setup-zig`).
- **meson + ninja** (installed via `pip install meson ninja` in CI).
- **Windows SDK** (preinstalled on `windows-latest`; supplies `d3dkmthk.h`).
- DirectX-Headers — pulled as a **meson subproject** by Mesa itself
  (`subprojects/DirectX-Headers.wrap`), no manual step.
- Python 3 for the wrapper scripts.

Local: install zig 0.16.0 with `zig` on PATH, `pip install meson ninja`, and run
`zb/build.ps1`.

---

## Building (local)

```powershell
# 64-bit only
powershell -ExecutionPolicy Bypass -File zb\build.ps1 -Arch 64 -SrcDir <mesa-radv-wddm2 checkout> -Zig zig

# 32-bit only
powershell -ExecutionPolicy Bypass -File zb\build.ps1 -Arch 32 -SrcDir <mesa-radv-wddm2 checkout> -Zig zig

# both (default) - requires an upstream checkout at ./src
powershell -ExecutionPolicy Bypass -File zb\build.ps1 -Zig zig
```

Outputs (per arch):
- `build-<arch>\src\amd\vulkan\vulkan_radeon.dll`
- `radv_wddm2_<arch>.json` — the ICD JSON (root of the repo), absolute `library_path`.

`build.ps1` runs `meson subprojects download` first so Mesa's subprojects (including
DirectX-Headers) are available.

---

## Running a Vulkan app with the built driver

The Vulkan loader picks its driver from `VK_ICD_FILENAMES`. Point it at the built
**ICD JSON** (the JSON contains the absolute `library_path` to the DLL):

```powershell
# Absolute path is required (the app's working dir differs from your shell).
$env:VK_ICD_FILENAMES = "C:\path\to\radv_wddm2_64.json"
& "C:\Path\To\app.exe"       # native Vulkan app -> uses 64-bit RADV

# 32-bit app
$env:VK_ICD_FILENAMES = "C:\path\to\radv_wddm2_32.json"
& "C:\Path\To\app32.exe"
```

To use the **AMD proprietary driver** instead, clear the variable:

```powershell
Remove-Item Env:VK_ICD_FILENAMES
```

> **Important:** `VK_ICD_FILENAMES` must be an **absolute** path to the `.json`. A
> bare relative filename makes the loader fail to open the ICD (e.g.
> `loader_get_json: Failed to open`, `VK_KHR_surface not supported`) and silently
> loads **no** driver.

### Examples (D3D-app via DXVK, or native Vulkan)

Source-engine games run through **DXVK** (D3D9→Vulkan). Point DXVK's Vulkan driver at
RADV the same way (see the game's DXVK setup):

```powershell
$env:VK_ICD_FILENAMES = "C:\path\to\radv_wddm2_64.json"
& "D:\SteamGames\steamapps\common\Counter-Strike Source\cstrike_win64.exe" -vulkan -windowed -w 1280 -h 720 +fps_max 0 -novid
```

Native Vulkan benchmarks (e.g. FurMark 2's `furmark-vk` demo) also just need the
variable set before launch:

```powershell
$env:VK_ICD_FILENAMES = "C:\path\to\radv_wddm2_64.json"
C:\Program Files\Geeks3D\FurMark2_x64\furmark.exe --demo furmark-vk --max-frames 1000 --width 1280 --height 720 --vsync 0 --no-osi
```

---

## Caveats

- Pristine upstream only: this repo does **not** carry or apply local driver
  patches. It builds `kleinergoo/mesa-radv-wddm2` exactly as fetched.
- RADV built for Windows targets the **wddm2 winsys** (supports the AMD ecosystem on
  WDDM); expect the same limits as any native-Windows RADV build.
- GitHub-hosted runners cannot render/benchmark, so CI validates compile/link, not
  frame output. Run the examples above on a machine with the AMD GPU to confirm.