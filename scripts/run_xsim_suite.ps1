$tests = @(
    "fake_eth_source_tb",
    "parser_tb",
    "rule_engine_tb",
    "packet_buffer_tb",
    "firewall_core_tb",
    "spi_master_tb",
    "eth_controller_adapter_tb",
    "adapter_firewall_integration_tb"
)

foreach ($test in $tests) {
    Write-Host "=== $test ==="
    powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\run_xsim.ps1" $test
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
