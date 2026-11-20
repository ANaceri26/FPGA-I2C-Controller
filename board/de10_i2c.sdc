create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_clock_uncertainty
# Button reset asserts asynchronously; reset_release synchronizes release.
set_false_path -from [get_ports KEY0]
# LEDs are human-observed outputs, not clocked external interfaces.
set_false_path -to [get_ports {LEDR[*]}]
# I2C is asynchronous to clk50. Only exclude paths INTO the first synchronizer stages.
set_false_path -from [get_ports GSENSOR_SCLK] -to [get_registers {*|scl_meta}]
set_false_path -from [get_ports GSENSOR_SDI] -to [get_registers {*|sda_meta}]
# Serial outputs follow the divider protocol, not a synchronous external clock.
set_false_path -to [get_ports {GSENSOR_SDI GSENSOR_SCLK GSENSOR_SDO GSENSOR_CS_N}]
