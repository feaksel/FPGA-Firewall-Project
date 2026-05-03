$tests = @(
    "fake_eth_source_tb",
    "parser_tb",
    "rule_engine_tb",
    "packet_buffer_tb",
    "frame_rx_fifo_tb",
    "seven_seg_hex_tb",
    "firewall_core_tb",
    "spi_master_tb",
    "eth_controller_adapter_tb",
    "w5500_tx_engine_tb",
    "adapter_firewall_integration_tb",
    "two_port_bypass_tb",
    "de1_soc_top_bypass_tb"
)

foreach ($test in $tests) {
    Write-Host "=== $test ==="
    powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\run_xsim.ps1" $test
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
