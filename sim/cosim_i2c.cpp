#include "Vi2c_env.h"
#include "verilated.h"
#include "controllers.h"
#include <cstdio>
#include <cstdlib>
#include <random>
static Vi2c_env top;
static void check(bool ok,const char *s) { if(!ok) { std::fprintf(stderr,"FAIL: %s\n",s);std::exit(1); } }
static void tick() { top.clk=0;top.eval();top.clk=1;top.eval();top.clk=0;top.eval(); }
static uint32_t read_reg(void *,uint32_t a) { top.reg_addr=a;top.reg_valid=1;top.reg_write=0;tick();return top.reg_rdata; }
static void write_reg(void *,uint32_t a,uint32_t v) {
    top.reg_addr=a;top.reg_wdata=v;top.reg_valid=1;top.reg_write=1;tick();top.reg_valid=0;top.reg_write=0;tick();
}
int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);top.rst_n=0;tick();top.rst_n=1;for(int i=0;i<5;i++)tick();
    hw_io io={nullptr,read_reg,write_reg};
    check(i2c_configure(io,1200000,100000,10000,1)==HW_OK,"configure");
    std::mt19937 rng(42);
    for(int t=0;t<100;t++) {
        uint8_t tx[9],rx[8]={0};tx[0]=uint8_t(rng()%240);
        for(int i=1;i<9;i++) tx[i]=uint8_t(rng());
        check(i2c_write_read(io,0x50,tx,9,nullptr,0,10000)==HW_OK,"C writes RTL");
        for(int i=0;i<8;i++) { top.probe_addr=tx[0]+i;top.eval();check(top.probe_data==tx[i+1],"target stored data"); }
        check(i2c_write_read(io,0x50,tx,1,rx,8,10000)==HW_OK,"C repeated-start read");
        for(int i=0;i<8;i++) check(rx[i]==tx[i+1],"C read data match");
    }
    uint8_t pointer=0,rx=0;
    top.nack_address=1;
    check(i2c_write_read(io,0x50,&pointer,1,nullptr,0,10000)==HW_NACK,"NACK surfaced to C");
    check(top.scl && top.sda,"NACK cleanup STOP");top.nack_address=0;
    top.nack_data=1;
    check(i2c_write_read(io,0x50,&pointer,1,nullptr,0,10000)==HW_NACK,"data NACK surfaced");top.nack_data=0;
    check(i2c_write_read(io,0x78,&pointer,1,nullptr,0,10000)==HW_INVALID,"reserved address");
    check(i2c_write_read(io,0x50,nullptr,1,nullptr,0,10000)==HW_INVALID,"null buffer");
    top.force_scl_low=1;write_reg(nullptr,I2C_TIMEOUT,50);
    check(i2c_write_read(io,0x50,&pointer,1,nullptr,0,10000)==HW_TIMEOUT,"hardware timeout");
    top.force_scl_low=0;for(int i=0;i<5;i++)tick();write_reg(nullptr,I2C_TIMEOUT,10000);
    check(i2c_write_read(io,0x50,nullptr,0,&rx,1,1)==HW_POLL_TIMEOUT,"software poll limit");
    for(int i=0;i<11000;i++)tick(); // Byte completes and holds SCL: explicit cleanup is needed.
    write_reg(nullptr,I2C_COMMAND,I2C_STOP);
    for(int i=0;i<100;i++)tick();
    check(i2c_write_read(io,0x50,&pointer,1,&rx,1,10000)==HW_OK,"recovery");
    std::puts("PASS C/RTL I2C: 100 write/read pairs (1600 payload bytes), NACK, invalid inputs, timeouts, recovery");
    top.final();return 0;
}
