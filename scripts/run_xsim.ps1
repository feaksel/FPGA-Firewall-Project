param(
    [Parameter(Mandatory = $true)]
    [string]$Testbench
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\xsim\$Testbench"
$PacketSrcDir = Join-Path $RepoRoot "tb\packets"
$PacketDstDir = Join-Path $BuildDir "tb\packets"
$VivadoBin = "C:\Xilinx\2025.1\Vivado\bin"
$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"
$SvTestFile = Join-Path $RepoRoot "tb/tests/$Testbench.sv"
$VTestFile = Join-Path $RepoRoot "tb/tests/$Testbench.v"
$RtlCommonDir = Join-Path $RepoRoot "rtl/common"
$TbCommonDir = Join-Path $RepoRoot "tb/common"

if (Test-Path $SvTestFile) {
    $TestFile = $SvTestFile
} elseif (Test-Path $VTestFile) {
    $TestFile = $VTestFile
} else {
    Write-Error "Testbench '$Testbench' not found as .sv or .v under tb/tests."
    exit 1
}

$Sources = @(
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
    (Join-Path $RepoRoot "tb/models/w5500_macraw_model.sv"),
    $TestFile
)

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $PacketDstDir | Out-Null
Copy-Item -Force (Join-Path $PacketSrcDir "*") $PacketDstDir

Push-Location $BuildDir
try {
    Remove-Item -Recurse -Force "xsim.dir" -ErrorAction SilentlyContinue
    Remove-Item -Force "xvlog.log","xvlog.pb","xelab.log","xelab.pb","xsim.log","xsim.pb" -ErrorAction SilentlyContinue

    $XvlogArgs = @(
        "--sv",
        "-i", $RtlCommonDir,
        "-i", $TbCommonDir
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
