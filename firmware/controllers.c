#include "controllers.h"
static int valid_io(hw_io io) { return io.read != NULL && io.write != NULL; }
uint32_t hw_mmio_read(void *base, uint32_t offset) {
    return *(volatile uint32_t *)((uintptr_t)base + offset);
}
void hw_mmio_write(void *base, uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)((uintptr_t)base + offset) = value;
}
int i2c_configure(hw_io io, uint32_t clock_hz, uint32_t bus_hz,
                  uint32_t timeout_cycles, int interrupt_enable) {
    if (!valid_io(io) || !clock_hz || !bus_hz || bus_hz > 100000 || !timeout_cycles) return HW_INVALID;
    if (io.read(io.context,I2C_STATUS)&17u) return HW_BUSY; /* busy OR holding bus */
    /* Round up the half-period. Synchronization/transition cycles make SCL a little slower. */
    uint64_t half=((uint64_t)clock_hz+2ull*bus_hz-1)/(2ull*bus_hz);
    if (half<4 || half>65535) return HW_INVALID;
    io.write(io.context,I2C_DIV,(uint32_t)half);
    io.write(io.context,I2C_TIMEOUT,timeout_cycles);
    io.write(io.context,I2C_IRQ_ENABLE,interrupt_enable!=0);
    return HW_OK;
}
static int i2c_command(hw_io io,uint8_t data,uint32_t flags,uint32_t polls) {
    if(io.read(io.context,I2C_STATUS)&1u) return HW_BUSY;
    io.write(io.context,I2C_TX,data);
    io.write(io.context,I2C_COMMAND,flags);
    while(polls--) {
        uint32_t s=io.read(io.context,I2C_STATUS);
        if(s&2u) {
            if(s&8u) return HW_TIMEOUT;
            if(s&32u) return HW_BAD_COMMAND;
            if(s&4u) return HW_NACK;
            return HW_OK;
        }
    }
    /* Does not cancel hardware. Caller must finish/STOP or reset; an idle held bus has no watchdog. */
    return HW_POLL_TIMEOUT;
}
int i2c_write_read(hw_io io,uint8_t address,const uint8_t *tx,size_t tx_len,
                   uint8_t *rx,size_t rx_len,uint32_t poll_limit) {
    if(!valid_io(io) || address<8 || address>0x77 || (!tx_len && !rx_len) ||
       (tx_len && !tx) || (rx_len && !rx) || !poll_limit) return HW_INVALID;
    if(io.read(io.context,I2C_STATUS)&17u) return HW_BUSY;
    int rc;
    if(tx_len) {
        rc=i2c_command(io,(uint8_t)(address<<1),I2C_START|I2C_WRITE,poll_limit);
        if(rc) goto failed;
        for(size_t i=0;i<tx_len;i++) {
            uint32_t flags=I2C_WRITE;
            if(i==tx_len-1 && !rx_len) flags|=I2C_STOP;
            rc=i2c_command(io,tx[i],flags,poll_limit);
            if(rc) goto failed;
        }
    }
    if(rx_len) {
        rc=i2c_command(io,(uint8_t)((address<<1)|1u),I2C_START|I2C_WRITE,poll_limit);
        if(rc) goto failed;
        for(size_t i=0;i<rx_len;i++) {
            uint32_t flags=I2C_READ | (i==rx_len-1 ? I2C_STOP : I2C_ACK);
            rc=i2c_command(io,0,flags,poll_limit);
            if(rc) goto failed;
            rx[i]=(uint8_t)io.read(io.context,I2C_RX);
        }
    }
    return HW_OK;
failed:
    if(rc==HW_NACK) {
        int cleanup=i2c_command(io,0,I2C_STOP,poll_limit);
        if(cleanup!=HW_OK) return cleanup;
    }
    return rc;
}
int dma_start(hw_io io,uint32_t source,uint32_t destination,uint32_t words) {
    if(!valid_io(io)) return HW_INVALID;
    if(io.read(io.context,DMA_STATUS)&1u) return HW_BUSY;
    uint64_t s_end=(uint64_t)source+4ull*words;
    uint64_t d_end=(uint64_t)destination+4ull*words;
    if(words && ((source&3u)||(destination&3u)||s_end>0x100000000ull||d_end>0x100000000ull||
       ((uint64_t)source<d_end && (uint64_t)destination<s_end))) return HW_CONFIG_ERROR;
    io.write(io.context,DMA_SOURCE,source);
    io.write(io.context,DMA_DESTINATION,destination);
    io.write(io.context,DMA_WORDS,words);
    io.write(io.context,DMA_COMMAND,1);
    return HW_OK;
}
int dma_wait(hw_io io,uint32_t poll_limit,uint32_t *completed_words) {
    if(!valid_io(io) || !poll_limit) return HW_INVALID;
    while(poll_limit--) {
        uint32_t s=io.read(io.context,DMA_STATUS);
        if(s&2u) {
            if(completed_words) *completed_words=io.read(io.context,DMA_COMPLETED);
            if(!(s&4u)) return HW_OK;
            switch((s>>3)&7u) {
                case 1:return HW_CONFIG_ERROR;
                case 2:return HW_BUS_ERROR;
                case 3:return HW_TIMEOUT;
                default:return HW_BUS_ERROR;
            }
        }
    }
    if(completed_words) *completed_words=io.read(io.context,DMA_COMPLETED);
    return HW_POLL_TIMEOUT;
}
