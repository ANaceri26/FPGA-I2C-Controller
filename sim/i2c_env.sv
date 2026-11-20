`timescale 1ns/1ps
`default_nettype none
module i2c_env (
    input wire clk,rst_n,reg_valid,reg_write,
    input wire [7:0] reg_addr, input wire [31:0] reg_wdata,
    output wire reg_ready, output wire [31:0] reg_rdata, output wire irq,
    input wire force_scl_low,force_sda_low,nack_address,nack_data,
    input wire [7:0] probe_addr, output wire [7:0] probe_data,
    output wire scl,sda, output wire [31:0] starts,stops,read_acks,read_nacks
);
    wire scl_low,sda_low,target_low;
    assign scl=!(scl_low || force_scl_low);
    assign sda=!(sda_low || target_low || force_sda_low);
    i2c_controller dut(.clk(clk),.rst_n(rst_n),.reg_valid(reg_valid),.reg_write(reg_write),
        .reg_addr(reg_addr),.reg_wdata(reg_wdata),.reg_ready(reg_ready),.reg_rdata(reg_rdata),
        .scl_i(scl),.sda_i(sda),.scl_low(scl_low),.sda_low(sda_low),.irq(irq));
    i2c_target_model target(.clk(clk),.rst_n(rst_n),.scl(scl),.sda(sda),
        .nack_address(nack_address),.nack_data(nack_data),.probe_addr(probe_addr),.probe_data(probe_data),
        .sda_low(target_low),.starts(starts),.stops(stops),.read_acks(read_acks),.read_nacks(read_nacks));
endmodule
`default_nettype wire
