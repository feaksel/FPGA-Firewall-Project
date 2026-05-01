param(
    [Parameter(Mandatory = $true)]
    [string]$Testbench
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\iverilog\$Testbench"
$OutFile = Join-Path $BuildDir "$Testbench.out"
$PacketSrcDir = Join-Path $RepoRoot "tb\packets"
$PacketDstDir = Join-Path $BuildDir "tb\packets"
$SvTestFile = Join-Path $RepoRoot "tb/tests/$Testbench.sv"
$VTestFile = Join-Path $RepoRoot "tb/tests/$Testbench.v"
$RtlCommonDir = Join-Path $RepoRoot "rtl/common"
$TbCommonDir = Join-Path $RepoRoot "tb/common"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $PacketDstDir | Out-Null
Copy-Item -Force (Join-Path $PacketSrcDir "*") $PacketDstDir

if (Test-Path $SvTestFile) {
    $TestFile = $SvTestFile
} elseif (Test-Path $VTestFile) {
    $TestFile = $VTestFile
} else {
    Write-Error "Testbench '$Testbench' not found as .sv or .v under tb/tests."
    exit 1
}

$Common = @(
    (Join-Path $RepoRoot "tb/common/fw_tb_pkg.sv"),
    (Join-Path $RepoRoot "rtl/debug/debug_counters.v"),
    (Join-Path $RepoRoot "rtl/spi/spi_master.v"),
    (Join-Path $RepoRoot "rtl/buffer/packet_buffer.v"),
    (Join-Path $RepoRoot "rtl/buffer/frame_rx_fifo.v"),
    (Join-Path $RepoRoot "rtl/parser/eth_ipv4_parser.v"),
    (Join-Path $RepoRoot "rtl/rules/rule_engine.v"),
    (Join-Path $RepoRoot "rtl/firewall/firewall_core.v"),
    (Join-Path $RepoRoot "rtl/eth_if/ethernet_controller_adapter.v"),
    (Join-Path $RepoRoot "rtl/top/firewall_top.v"),
    (Join-Path $RepoRoot "rtl/top/de1_soc_w5500_top.v"),
    (Join-Path $RepoRoot "tb/models/fake_eth_source.v"),
    (Join-Path $RepoRoot "tb/models/w5500_macraw_model.sv")
)

$Args = @(
    "-g2012",
    "-I", $RtlCommonDir,
    "-I", $TbCommonDir,
    "-o", $OutFile
) + $Common + @($TestFile)

Push-Location $BuildDir
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
