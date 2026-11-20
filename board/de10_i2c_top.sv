`timescale 1ns/1ps
`default_nettype none
// Read the onboard ADXL345 DEVID register (0x00) at address 0x53.
module de10_i2c_top #(
    parameter integer POWERUP_CYCLES=1_000_000,
    parameter integer HALF_PERIOD=2500
)(input wire MAX10_CLK1_50,input wire KEY0,
  inout wire GSENSOR_SDI,inout wire GSENSOR_SCLK,
  output wire GSENSOR_CS_N,output wire GSENSOR_SDO,output wire [9:0] LEDR);
    wire rst_n;
    reset_release resetter(MAX10_CLK1_50,KEY0,rst_n);
    wire scl_low,sda_low;
    assign GSENSOR_SDI=sda_low ? 1'b0 : 1'bz;
    assign GSENSOR_SCLK=scl_low ? 1'b0 : 1'bz;
    assign GSENSOR_CS_N=1'b1; assign GSENSOR_SDO=1'b0;
    reg valid,write_en;reg [7:0] addr;reg [31:0] wdata;
    wire [31:0] rdata;
    wire unused_status=^rdata;
    wire unused_ready,unused_irq;
    i2c_controller core(.clk(MAX10_CLK1_50),.rst_n(rst_n),.reg_valid(valid),.reg_write(write_en),
        .reg_addr(addr),.reg_wdata(wdata),.reg_ready(unused_ready),.reg_rdata(rdata),
        .scl_i(GSENSOR_SCLK),.sda_i(GSENSOR_SDI),.scl_low(scl_low),.sda_low(sda_low),.irq(unused_irq));
    localparam WAIT_POWER=0,DIVIDER=1,TIMEOUT=2,TX=3,COMMAND=4,POLL=5,READ_RESULT=6,CLEANUP=7,HALT=8;
    reg [3:0] state;reg [31:0] wait_count;reg [1:0] byte_index;
    reg [7:0] result;reg passed,failed;
    assign LEDR={failed,passed,result};
    always @* begin
        valid=0;write_en=0;addr=4;wdata=0;
        case(state)
            DIVIDER:begin valid=1;write_en=1;addr=16;wdata=HALF_PERIOD;end
            TIMEOUT:begin valid=1;write_en=1;addr=24;wdata=5_000_000;end
            TX:begin
                valid=1;write_en=1;addr=8;
                case(byte_index) 0:wdata=32'ha6;2:wdata=32'ha7;default:wdata=0;endcase
            end
            COMMAND:begin
                valid=1;write_en=1;addr=0;
                case(byte_index) 0,2:wdata=5;1:wdata=4;default:wdata=10;endcase
            end
            POLL:begin valid=1;addr=4;end
            READ_RESULT:begin valid=1;addr=12;end
            CLEANUP:begin valid=1;write_en=1;addr=0;wdata=2;end
            default:begin end
        endcase
    end
    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if(!rst_n)begin state<=WAIT_POWER;wait_count<=0;byte_index<=0;result<=0;passed<=0;failed<=0;end
        else case(state)
            WAIT_POWER:if(wait_count==POWERUP_CYCLES-1)state<=DIVIDER;else wait_count<=wait_count+1'b1;
            DIVIDER:state<=TIMEOUT;
            TIMEOUT:state<=TX;
            TX:state<=COMMAND;
            COMMAND:state<=POLL;
            POLL:if(rdata[1])begin
                if(rdata[5]||rdata[3]||rdata[2])begin failed<=1;state<=CLEANUP;end
                else if(byte_index==3)state<=READ_RESULT;
                else begin byte_index<=byte_index+1'b1;state<=TX;end
            end
            READ_RESULT:begin result<=rdata[7:0];passed<=rdata[7:0]==8'he5;failed<=rdata[7:0]!=8'he5;state<=HALT;end
            CLEANUP:state<=HALT;
            default:state<=HALT;
        endcase
    end
endmodule
`default_nettype wire
