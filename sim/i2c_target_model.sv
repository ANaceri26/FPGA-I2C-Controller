`timescale 1ns/1ps
`default_nettype none
// Verification-only 7-bit target at 0x50: byte pointer followed by auto-increment data.
// This is an independent wire-level model, not a replacement for the controller.
module i2c_target_model #(parameter [6:0] ADDRESS=7'h50, parameter [7:0] INITIAL_ID=0) (
    input wire clk,rst_n,scl,sda, input wire nack_address,nack_data,
    input wire [7:0] probe_addr, output wire [7:0] probe_data,
    output reg sda_low, output reg [31:0] starts,stops,read_acks,read_nacks
);
    localparam RX=0, ACK_PREP=1, ACK=2, TX=3, TX_ACK=4, IGNORE=5;
    integer state,count,j;
    reg old_scl,old_sda,address_phase,read_mode,selected,need_pointer,ack_value,master_ack;
    reg [7:0] incoming,ptr;
    reg [7:0] mem [0:255];
    wire [7:0] received={incoming[6:0],sda};
    assign probe_data=mem[probe_addr];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            old_scl<=1; old_sda<=1; state<=IGNORE; count<=0;
            address_phase<=1; read_mode<=0; selected<=0; need_pointer<=1;
            ack_value<=0; master_ack<=0; incoming<=0; ptr<=0; sda_low<=0;
            starts<=0; stops<=0; read_acks<=0; read_nacks<=0;
            for(j=0;j<256;j=j+1) mem[j]=(j==0 ? INITIAL_ID : 8'h00);
        end else begin
            old_scl<=scl; old_sda<=sda;
            if(old_sda && !sda && scl && old_scl) begin
                state<=RX; count<=0; address_phase<=1; sda_low<=0; starts<=starts+1'b1;
            end else if(!old_sda && sda && scl && old_scl) begin
                state<=IGNORE; sda_low<=0; stops<=stops+1'b1;
            end else begin
                if(!old_scl && scl) begin
                    case(state)
                        RX: begin
                            incoming<=received;
                            if(count==7) begin
                                count<=0; state<=ACK_PREP;
                                if(address_phase) begin
                                    selected<=(received[7:1]==ADDRESS)&&!nack_address;
                                    ack_value<=(received[7:1]==ADDRESS)&&!nack_address;
                                    read_mode<=received[0]; need_pointer<=!received[0];
                                    address_phase<=0;
                                end else begin
                                    ack_value<=selected && !nack_data;
                                    if(selected && !nack_data) begin
                                        if(need_pointer) begin ptr<=received; need_pointer<=0; end
                                        else begin mem[ptr]<=received; ptr<=ptr+1'b1; end
                                    end
                                end
                            end else count<=count+1;
                        end
                        TX: count<=count+1;
                        TX_ACK: begin
                            master_ack<=!sda;
                            if(sda) read_nacks<=read_nacks+1'b1;
                            else read_acks<=read_acks+1'b1;
                        end
                        default: begin end
                    endcase
                end
                if(old_scl && !scl) begin
                    case(state)
                        ACK_PREP: begin sda_low<=ack_value; state<=ACK; end
                        ACK: begin
                            sda_low<=0; count<=0;
                            if(!ack_value) state<=IGNORE;
                            else if(read_mode) begin state<=TX; sda_low<=!mem[ptr][7]; end
                            else state<=RX;
                        end
                        TX: begin
                            if(count==8) begin sda_low<=0; state<=TX_ACK; end
                            else sda_low<=!mem[ptr][7-count];
                        end
                        TX_ACK: begin
                            ptr<=ptr+1'b1; count<=0;
                            if(master_ack) begin state<=TX; sda_low<=!mem[ptr+8'd1][7]; end
                            else begin state<=IGNORE; sda_low<=0; end
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
endmodule
`default_nettype wire
