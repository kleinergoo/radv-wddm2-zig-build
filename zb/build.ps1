# ---------------------------------------------------------------------------
# build.ps1 - build the RADV (Mesa Vulkan) wddm2 driver with zig for 64-bit
# and/or 32-bit Windows, then emit an ICD JSON for each built driver.
#
# Reproduces the proven local zig-windows-msvc setup on a fresh checkout:
#   - 64-bit: zig cc, target x86_64-windows-msvc, -include zig_msvc_fix.h
#   - 32-bit: zig-x86-cc.py wrapper, target x86-windows-msvc, same fix header,
#             plus -loldnames on final link only (pure info / -c probes skip it)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File zb\build.ps1 `
#       -Arch 64|32          # which build(s) to produce
#       -SrcDir <upstream mesa-radv-wddm2 checkout>  (default $PWD\src)
#       -BuildDir <meson build dir>                   (default $PWD\build-<arch>)
#       -Zig <path to zig.exe>                        (default: zig on PATH)
#       -ReleaseICH          # generate <arch> ICD JSON (default on)
# ---------------------------------------------------------------------------
param(
    [ValidateSet("64","32")][string[]]$Arch        = @("64","32"),
    [string]$SrcDir   = "",
    [string]$BuildDir = "",
    [string]$Zig      = "",
    [switch]$NoIcd,
    # Production RADV-only meson options (mirror the proven local build).
    [string[]]$MesonOpts = @("-Dgallium-drivers=", "-Dvulkan-drivers=amd",
                             "-Dllvm=disabled", "-Damd-use-llvm=false",
                             "-Degl=disabled", "-Dopengl=false",
                             "-Dgles1=disabled", "-Dgles2=disabled",
                             "-Dbuildtype=debugoptimized", "-Ddefault_library=static")
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $SrcDir)   { $SrcDir   = Join-Path $RepoRoot "src" }
if (-not $Zig)      { $Zig      = "zig" }

foreach ($a in $Arch) {
    Write-Host "=== Building RADV [${a}-bit] ==="
    $bd = if ($BuildDir) { $BuildDir } else { Join-Path $RepoRoot "build-${a}" }
    New-Item -ItemType Directory -Force -Path $bd | Out-Null

    # --- Pinned absolute zig + support-file paths (so the ini works anywhere) --
    $zigExe        = (Get-Command $Zig -ErrorAction Stop).Source
    $fixHeader     = (Join-Path $PSScriptRoot "zig_msvc_fix.h").Replace('\','/')
    $winresPy      = (Join-Path $PSScriptRoot "zig_windres.py").Replace('\','/')
    $x86CcPy       = (Join-Path $PSScriptRoot "zig-x86-cc.py").Replace('\','/')

    if ($a -eq "64") {
        $ini = Join-Path $bd "zig-windows-msvc-native.ini"
        $native = "--native-file"
        $target = "x86_64-windows-msvc"
        $cc  = @("zig","cc")
    } else {
        $ini = Join-Path $bd "zig-windows-msvc-x86-cross.ini"
        $native = "--cross-file"
        $target = "x86-windows-msvc"
        $cc  = @("python",$x86CcPy)
    }

    # --- Render the meson binary/mach description file -----------------------
    $content = @"
[binaries]
c = [$(($cc | ForEach-Object { "'$_'" }) -join ",")]
cpp = [$(($cc | ForEach-Object { "'$_'" }) -join ",")]
c_ld = 'zig'
cpp_ld = 'zig'
ar = ['zig','ar']
strip = ['zig','strip']
windres = ['python','$winresPy']

[built-in options]
c_args = ['-target','$target','-include','$fixHeader']
cpp_args = ['-target','$target','-include','$fixHeader']
c_link_args = ['-target','$target','-loldnames']
cpp_link_args = ['-target','$target','-loldnames']
"@
    if ($a -eq "32") {
        # 32-bit: the wrapper injects target/fix/loldnames itself, so the
        # cross file only pins the machines and uses empty arg lists.
        $content = @"
[binaries]
c = ['python','$x86CcPy']
cpp = ['python','$x86CcPy']
c_ld = 'zig'
cpp_ld = 'zig'
ar = ['zig','ar']
strip = ['zig','strip']
windres = ['python','$winresPy']

[built-in options]
c_args = []
cpp_args = []
c_link_args = []
cpp_link_args = []

[host_machine]
system = 'windows'
cpu_family = 'x86'
cpu = 'i686'
endian = 'little'
"@
    }
    Set-Content -Path $ini -Value $content -Encoding Ascii
    Write-Host "Wrote $ini"

    # --- Configure + build ---------------------------------------------------
    if (-not (Test-Path (Join-Path $SrcDir "meson.build"))) {
        throw "No meson.build under -SrcDir ($SrcDir). Point it at an upstream mesa-radv-wddm2 checkout."
    }
    Push-Location $SrcDir
    try {
        Write-Host "meson subprojects download"
        meson subprojects download
        Write-Host "meson setup $bd $native $ini (target ${a}-bit) $($MesonOpts -join ' ')"
        if (-not (Test-Path (Join-Path $bd "build.ninja"))) {
            meson setup $bd $native $ini $MesonOpts
        } else {
            meson setup --reconfigure $bd $native $ini $MesonOpts
        }
        ninja -C $bd
    } finally {
        Pop-Location
    }

    $dll = Join-Path $bd "src\amd\vulkan\vulkan_radeon.dll"
    if (-not (Test-Path $dll)) {
        throw "Expected driver not found: $dll"
    }

    # --- ICD JSON -------------------------------------------------------------
    if (-not $NoIcd) {
        & (Join-Path $PSScriptRoot "make_icd.ps1") -Dll $dll -Icd (Join-Path $RepoRoot "radv_wddm2_${a}.json")
    }
    Write-Host "=== Done ${a}-bit: $dll ==="
}