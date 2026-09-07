param(
    [string]$QuestaBin = "C:\altera_lite\25.1std\questa_fse\win64"
)

$ErrorActionPreference = "Stop"
$integratedRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $integratedRoot
$member2Root = Join-Path $workspaceRoot "member2"
$buildDir = Join-Path $integratedRoot "build\bridge_questa"

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Push-Location $buildDir
try {
    if (Test-Path work) { Remove-Item work -Recurse -Force }
    & (Join-Path $QuestaBin "vlib.exe") work
    if ($LASTEXITCODE -ne 0) { throw "vlib failed" }

    $sourceFiles = @(
        # Existing files already in Dulina14/sys-bus
        (Join-Path $member2Root "rtl\bus_mux2.v"),
        (Join-Path $integratedRoot "rtl\serial_master_port.v"),
        (Join-Path $integratedRoot "rtl\serial_slave_memory.v"),
        (Join-Path $integratedRoot "rtl\serial_slave_port.v"),
        (Join-Path $integratedRoot "rtl\serial_bus_slave.v"),

        # New four-slave interconnect files
        (Join-Path $member2Root "rtl\bus_mux4.v"),
        (Join-Path $member2Root "rtl\bus_slave_valid_decoder4.v"),
        (Join-Path $member2Root "rtl\bus_arbiter_4slave.v"),
        (Join-Path $member2Root "rtl\serial_address_decoder_4slave.v"),
        (Join-Path $member2Root "rtl\serial_bus_m2_s4.v"),

        # New bridge endpoint files
        (Join-Path $integratedRoot "rtl\bridge_addr_convert.v"),
        (Join-Path $integratedRoot "rtl\bridge_uart_tx.v"),
        (Join-Path $integratedRoot "rtl\bridge_uart_rx.v"),
        (Join-Path $integratedRoot "rtl\bridge_uart.v"),
        (Join-Path $integratedRoot "rtl\serial_bus_bridge_slave.v"),
        (Join-Path $integratedRoot "rtl\serial_bus_bridge_master.v"),
        (Join-Path $integratedRoot "rtl\integrated_system_bus_bridge.v"),
        (Join-Path $integratedRoot "tb\tb_bridge_loop.sv")
    )

    & (Join-Path $QuestaBin "vlog.exe") -sv @sourceFiles
    if ($LASTEXITCODE -ne 0) { throw "vlog failed" }

    & (Join-Path $QuestaBin "vsim.exe") -c -voptargs=+acc work.tb_bridge_loop -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "Bridge simulation failed" }

    Write-Host "Bridge loop simulation passed."
}
finally {
    Pop-Location
}
