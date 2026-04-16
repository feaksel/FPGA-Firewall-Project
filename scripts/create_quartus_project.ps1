param(
    [string]$QuartusSh = "C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $QuartusSh)) {
    throw "quartus_sh.exe not found at '$QuartusSh'"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$quartusDir = Join-Path $repoRoot "quartus"
$tclScript = Join-Path $quartusDir "create_de1_soc_w5500_project.tcl"

if (-not (Test-Path $tclScript)) {
    throw "Project creation TCL not found at '$tclScript'"
}

New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot "build\quartus") | Out-Null

Push-Location $quartusDir
try {
    & $QuartusSh -t $tclScript
    if ($LASTEXITCODE -ne 0) {
        throw "Quartus project creation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
