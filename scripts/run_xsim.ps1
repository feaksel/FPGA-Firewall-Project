param(
    [Parameter(Mandatory = $true)]
    [string]$Testbench
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\xsim\$Testbench"
$VivadoBin = "C:\Xilinx\2025.1\Vivado\bin"
$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"
$SvTestFile = Join-Path $RepoRoot "tb/tests/$Testbench.sv"
$VTestFile = Join-Path $RepoRoot "tb/tests/$Testbench.v"

if (Test-Path $SvTestFile) {
    $TestFile = "tb/tests/$Testbench.sv"
} elseif (Test-Path $VTestFile) {
    $TestFile = "tb/tests/$Testbench.v"
} else {
    Write-Error "Testbench '$Testbench' not found as .sv or .v under tb/tests."
    exit 1
}

$Sources = @(
    "tb/common/fw_tb_pkg.sv",
    "rtl/debug/debug_counters.v",
    "rtl/spi/spi_master.v",
    "rtl/buffer/packet_buffer.v",
    "rtl/parser/eth_ipv4_parser.v",
    "rtl/rules/rule_engine.v",
    "rtl/firewall/firewall_core.v",
    "rtl/eth_if/ethernet_controller_adapter.v",
    "rtl/top/firewall_top.v",
    "tb/models/fake_eth_source.v",
    $TestFile
)

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

Push-Location $RepoRoot
try {
    Remove-Item -Recurse -Force "xsim.dir" -ErrorAction SilentlyContinue
    Remove-Item -Force "xvlog.log","xvlog.pb","xelab.log","xelab.pb","xsim.log","xsim.pb" -ErrorAction SilentlyContinue

    $XvlogArgs = @(
        "--sv",
        "-i", "rtl/common",
        "-i", "tb/common"
    ) + $Sources

    & $Xvlog @XvlogArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & $Xelab "work.$Testbench" "-s" $Testbench "--debug" "typical"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & $Xsim $Testbench "-runall"
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
