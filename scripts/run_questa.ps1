param(
    [Parameter(Mandatory = $true)]
    [string]$Testbench
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\questa\$Testbench"
$PacketSrcDir = Join-Path $RepoRoot "tb\packets"
$PacketDstDir = Join-Path $BuildDir "tb\packets"
$QuestaBin = "C:\altera_lite\25.1std\questa_fse\win64"
$Vlib = Join-Path $QuestaBin "vlib.exe"
$Vmap = Join-Path $QuestaBin "vmap.exe"
$Vlog = Join-Path $QuestaBin "vlog.exe"
$Vsim = Join-Path $QuestaBin "vsim.exe"
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
    "rtl/debug/seven_seg_hex.v",
    "rtl/debug/uart_tx.v",
    "rtl/debug/firewall_telemetry_uart.v",
    "rtl/spi/spi_master.v",
    "rtl/buffer/packet_buffer.v",
    "rtl/buffer/frame_rx_fifo.v",
    "rtl/parser/eth_ipv4_parser.v",
    "rtl/rules/rule_engine.v",
    "rtl/firewall/firewall_core.v",
    "rtl/firewall/firewall_forwarder.v",
    "rtl/eth_if/ethernet_controller_adapter.v",
    "rtl/eth_if/w5500_tx_engine.v",
    "rtl/eth_if/w5500_macraw_tx_adapter.v",
    "rtl/top/firewall_top.v",
    "rtl/top/de1_soc_w5500_top.v",
    "tb/models/fake_eth_source.v",
    "tb/models/w5500_macraw_model.sv",
    "tb/models/w5500_tx_model.sv",
    $TestFile
)

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $PacketDstDir | Out-Null
Copy-Item -Force (Join-Path $PacketSrcDir "*") $PacketDstDir

Push-Location $BuildDir
try {
    & $Vlib "work"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & $Vmap "work" "work"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $VlogArgs = @(
        "-sv",
        "+incdir+$RepoRoot\\rtl\\common",
        "+incdir+$RepoRoot\\tb\\common"
    ) + ($Sources | ForEach-Object { Join-Path $RepoRoot $_ })

    & $Vlog @VlogArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & $Vsim "-c" $Testbench "-do" "run -all; quit -f"
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
