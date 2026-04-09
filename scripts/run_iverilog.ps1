param(
    [Parameter(Mandatory = $true)]
    [string]$Testbench
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build"
$OutFile = Join-Path $BuildDir "$Testbench.out"
$SvTestFile = Join-Path $RepoRoot "tb/tests/$Testbench.sv"
$VTestFile = Join-Path $RepoRoot "tb/tests/$Testbench.v"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

if (Test-Path $SvTestFile) {
    $TestFile = "tb/tests/$Testbench.sv"
} elseif (Test-Path $VTestFile) {
    $TestFile = "tb/tests/$Testbench.v"
} else {
    Write-Error "Testbench '$Testbench' not found as .sv or .v under tb/tests."
    exit 1
}

$Common = @(
    "tb/common/fw_tb_pkg.sv",
    "rtl/debug/debug_counters.v",
    "rtl/spi/spi_master.v",
    "rtl/buffer/packet_buffer.v",
    "rtl/parser/eth_ipv4_parser.v",
    "rtl/rules/rule_engine.v",
    "rtl/firewall/firewall_core.v",
    "rtl/eth_if/ethernet_controller_adapter.v",
    "rtl/top/firewall_top.v",
    "tb/models/fake_eth_source.v"
)

$Args = @(
    "-g2012",
    "-I", "rtl/common",
    "-I", "tb/common",
    "-o", $OutFile
) + $Common + @($TestFile)

Push-Location $RepoRoot
try {
    & iverilog @Args
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & vvp $OutFile
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
