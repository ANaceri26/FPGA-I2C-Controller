`timescale 1ns/1ps
module tb_i2c;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,reg_valid=0,reg_write=0;
    reg [7:0] reg_addr=0,probe_addr=0; reg [31:0] reg_wdata=0;
    wire reg_ready,irq,scl,sda; wire [31:0] reg_rdata,starts,stops,read_acks,read_nacks;
    wire [7:0] probe_data;
    reg force_scl_low=0,force_sda_low=0,nack_address=0,nack_data=0;
    i2c_env env(.*);
    integer seed=1,iterations=1000,k,j,t,commands=0; reg [31:0] st,random_value;
    reg [7:0] data0,data1,ptr;
    task wr(input [7:0] a,input [31:0] d);
        begin @(negedge clk); reg_valid=1;reg_write=1;reg_addr=a;reg_wdata=d;
        @(negedge clk);reg_valid=0;reg_write=0;end
    endtask
    task rd(input [7:0] a,output [31:0] d);
        begin @(negedge clk);reg_addr=a;#1;d=reg_rdata;end
    endtask
    task wait_done;
        begin t=0;st=0;
        while(!st[1] && t<20000) begin rd(4,st);t=t+1;end
        if(!st[1]) $fatal(1,"I2C failed to complete");
        commands=commands+1;
        end
    endtask
    task cmd(input [7:0] byte_value,input [4:0] flags);
        begin wr(8,{24'b0,byte_value});wr(0,{27'b0,flags});wait_done();
        if(st[5]||st[3]||st[2]) $fatal(1,"I2C unexpected status %h byte=%h flags=%h",st,byte_value,flags);
        end
    endtask
    initial begin
        if($value$plusargs("SEED=%d",seed)) begin end
        if($value$plusargs("N=%d",iterations)) begin end
        random_value=$urandom(seed);
        if($test$plusargs("TRACE")) begin $dumpfile("results/i2c.vcd");$dumpvars(0,tb_i2c);end
        repeat(5) @(negedge clk);rst_n=1;repeat(5) @(negedge clk);
        wr(16,6);wr(24,10000);wr(20,1);
        // Repeated START, auto-increment, controller ACK then final NACK.
        for(k=0;k<iterations;k=k+1) begin
            random_value=$urandom;ptr=random_value[7:0]&8'hfc;
            random_value=$urandom;data0=random_value[7:0];
            random_value=$urandom;data1=random_value[7:0];
            cmd(8'ha0,5);cmd(ptr,4);cmd(data0,4);cmd(data1,6);
            probe_addr=ptr;#1;if(probe_data!==data0) $fatal(1,"write byte 0 mismatch");
            probe_addr=ptr+1'b1;#1;if(probe_data!==data1) $fatal(1,"write byte 1 mismatch");
            cmd(8'ha0,5);cmd(ptr,4);cmd(8'ha1,5);
            cmd(0,24);rd(12,st);if(st[7:0]!==data0) $fatal(1,"read byte 0 mismatch");
            cmd(0,10);rd(12,st);if(st[7:0]!==data1) $fatal(1,"read byte 1 mismatch");
            if(!irq) $fatal(1,"missing IRQ");
            wr(4,2);if(irq) $fatal(1,"IRQ did not clear");
        end
        if(read_acks!=iterations || read_nacks!=iterations) $fatal(1,"read ACK/NACK count");
        if(starts!=3*iterations || stops!=2*iterations) $fatal(1,"START/STOP counts");
        // Address and data NACK, explicit STOP cleanup.
        nack_address=1;wr(8,8'ha0);wr(0,7);wait_done();
        if(!st[2] || st[3] || st[4]) $fatal(1,"address NACK");nack_address=0;
        cmd(8'ha0,5);nack_data=1;wr(8,32'h20);wr(0,6);wait_done();
        if(!st[2]) $fatal(1,"data NACK");nack_data=0;
        // Clock stretching during a data bit, then normal completion.
        fork
            begin cmd(8'ha0,7); end
            begin wait(!scl);@(negedge clk);force_scl_low=1;
                repeat(80) @(negedge clk);force_scl_low=0;end
        join
        // SCL stuck and SDA stuck must both time out and release controller outputs.
        wr(24,100);force_scl_low=1;wr(8,8'ha0);wr(0,7);wait_done();
        if(!st[3] || st[4]) $fatal(1,"SCL timeout");force_scl_low=0;
        repeat(5) @(negedge clk);force_sda_low=1;wr(0,7);wait_done();
        if(!st[3]) $fatal(1,"SDA timeout");force_sda_low=0;
        repeat(5) @(negedge clk);wr(24,10000);
        // SDA becomes stuck during STOP: do not report a successful free bus.
        wr(24,1000);wr(8,8'ha0);wr(0,7);
        wait(env.dut.state==15);@(negedge clk);force_sda_low=1;wait_done();
        if(!st[3]) $fatal(1,"STOP stuck-SDA timeout");force_sda_low=0;
        repeat(5) @(negedge clk);wr(24,10000);
        // Invalid command is rejected. Config and START writes while busy are ignored.
        wr(0,12);wait_done();if(!st[5]) $fatal(1,"bad command not rejected");
        wr(8,8'ha0);wr(0,7);wr(16,999);wr(0,12);wait_done();
        if(st[5]||st[3]||st[2]) $fatal(1,"busy command changed transfer");
        rd(16,st);if(st!=6) $fatal(1,"busy config changed divider");
        // Reset midway through byte, then reconfigure and prove recovery.
        wr(0,7);repeat(12) @(negedge clk);rst_n=0;
        repeat(4) @(negedge clk);if(!scl||!sda||irq) $fatal(1,"reset release");rst_n=1;
        repeat(5) @(negedge clk);wr(16,6);wr(24,10000);cmd(8'ha0,7);
        $display("PASS I2C: %0d randomized write/read transactions, %0d byte commands + fault/reset tests",iterations,commands);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"global watchdog");end
endmodule
