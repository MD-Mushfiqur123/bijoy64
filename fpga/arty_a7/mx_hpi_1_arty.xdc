# MX-Hpi-1 on Digilent Arty A7-100T
# 100 MHz system clock, active-low reset button, UART on Pmod JA.
# uart_tx_pin = JA pin 1, uart_rx_pin = JA pin 2 (use a crossover cable if
# talking to a PC USB-UART adapter).

set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports arst_n_in]

set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports uart_tx_pin]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports uart_rx_pin]

set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
