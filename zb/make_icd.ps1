# ---------------------------------------------------------------------------
# make_icd.ps1 - emit a Vulkan ICD JSON pointing at a built vulkan_radeon.dll.
#
# Usage:  powershell -ExecutionPolicy Bypass `
#             -File make_icd.ps1 -Dll <abs path to vulkan_radeon.dll> `
#             [-Icd <output .json>] [-NoArch] [-Relative] `
#             [-ApiVersion 1.4.348] [-FileVer 1.0.1]
#
# -Relative : write library_path as ".\vulkan_radeon.dll" (backslash-escaped by
#             ConvertTo-Json) instead of an absolute path. Use this when the ICD
#             is shipped in the same directory as the DLL, so the archive is
#             relocatable.
# ---------------------------------------------------------------------------
param(
    [Parameter(Mandatory=$true)][string]$Dll,
    [string]$Icd = "",
    [string]$Arch = "",
    [switch]$NoArch,
    [switch]$Relative,
    [string]$ApiVersion = "1.4.348",
    [string]$FileVer = "1.0.1"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Dll -PathType Leaf)) {
    throw "DLL not found: $Dll"
}
$dllPath = (Get-Item -LiteralPath $Dll).FullName

# Inferred only when needed; kept for -NoArch callers.
[Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedVariable', '')]
$Machine = 0
if ($NoArch) {
    # caller provided explicit $Arch, or we infer from file (best-effort)
    if ($Arch -ne "") { $Arch = "" } # keep explicit-ish
}

if (-not $Arch) {
    # PE IMAGE_FILE_MACHINE (offset 0x3C -> e_lfanew, +4 => machine)
    $fs = [System.IO.File]::OpenRead($dllPath)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $pe = $br.ReadUInt32()
        $fs.Position = $pe + 4
        $Machine = $br.ReadUInt16()
        # IMAGE_FILE_MACHINE_I386=0x14c, AMD64=0x8664
        switch ($Machine) {
            0x14c  { $Arch = "32" }
            0x8664 { $Arch = "64" }
            default { $Arch = "unknown" }
        }
    } finally {
        $fs.Dispose()
    }
}

if (-not $Icd) {
    $Icd = Join-Path (Split-Path -Parent $dllPath) "radv_wddm2_${Arch}.json"
}

$json = @{
    "file_format_version" = $FileVer
    "ICD" = @{
        "api_version"   = $ApiVersion
        "library_arch"  = $Arch
        "library_path"  = if ($Relative) { ".\" + (Split-Path -Leaf $dllPath) } else { $dllPath }
    }
} | ConvertTo-Json -Compress

Set-Content -Path $Icd -Value $json -Encoding Ascii
Write-Host "Wrote ICD: $Icd"
Write-Host $json