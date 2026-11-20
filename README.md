# FPGA I2C Controller

I2C controller in SystemVerilog with a simple 32-bit register interface. The DE10-Lite demo uses it to read the ID register of the board's ADXL345 accelerometer.

## Design

- `rtl/i2c_controller.sv`: byte-level I2C controller supporting START/STOP, repeated START, ACK/NACK, clock stretching and a command watchdog. Uses open-drain style outputs
- `board/de10_i2c_top.sv`: reads DEVID (0x00) from address 0x53. The low 8 LEDs show the byte, LEDR8 = pass (0xE5), LEDR9 = fail
- `sim/i2c_target_model.sv`: independent wire-level target model used by the testbench
- `firmware/controllers.c`: C driver, also used for co-simulation against the RTL

Register map is in [docs/INTERFACES.md](docs/INTERFACES.md).

## Verification

| Test | Result |
|---|---|
| Randomized write/read regression, seeds 1 and 42 | 1,000 cases (9,010 byte commands) per seed, pass |
| C driver + Verilator RTL co-simulation | 100 multi-byte write/read pairs, pass |
| Verilator lint (`-Wall`, warnings fatal) | clean |
| Yosys generic synthesis | pass |

Directed cases cover address and data NACK, clock stretching, SCL/SDA stuck low, invalid commands, and reset mid-byte. Logs and a waveform are in `results/`.

Not done yet: Quartus timing results and an on-board test. Single controller only, no multi-master arbitration.

## Run

```sh
iverilog -g2012 -Wall -s tb_i2c -o tb_i2c rtl/i2c_controller.sv sim/i2c_target_model.sv sim/i2c_env.sv sim/tb_i2c.sv
vvp tb_i2c +N=1000 +SEED=1
```

For the board, open `board/de10_i2c.qpf` in Quartus.
