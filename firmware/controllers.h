#ifndef CONTROLLERS_H
#define CONTROLLERS_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Offset-based I/O permits the SAME driver to use real MMIO or an RTL simulator. */
typedef uint32_t (*hw_read_fn)(void *context, uint32_t offset);
typedef void (*hw_write_fn)(void *context, uint32_t offset, uint32_t value);
typedef struct { void *context; hw_read_fn read; hw_write_fn write; } hw_io;
enum { HW_OK=0, HW_INVALID=-1, HW_BUSY=-2, HW_POLL_TIMEOUT=-3,
       HW_NACK=-4, HW_TIMEOUT=-5, HW_BUS_ERROR=-6, HW_CONFIG_ERROR=-7, HW_BAD_COMMAND=-8 };
enum { I2C_COMMAND=0, I2C_STATUS=4, I2C_TX=8, I2C_RX=12, I2C_DIV=16,
       I2C_IRQ_ENABLE=20, I2C_TIMEOUT=24, I2C_ID=28 };
enum { I2C_START=1, I2C_STOP=2, I2C_WRITE=4, I2C_READ=8, I2C_ACK=16 };
enum { DMA_COMMAND=0, DMA_STATUS=4, DMA_SOURCE=8, DMA_DESTINATION=12,
       DMA_WORDS=16, DMA_COMPLETED=20, DMA_IRQ_ENABLE=24, DMA_TIMEOUT=28, DMA_ID=32 };
int i2c_configure(hw_io io, uint32_t clock_hz, uint32_t bus_hz, uint32_t timeout_cycles, int interrupt_enable);
/* A seven-bit address is passed unshifted. Reads end with NACK + STOP. */
int i2c_write_read(hw_io io, uint8_t address, const uint8_t *tx, size_t tx_len,
                   uint8_t *rx, size_t rx_len, uint32_t poll_limit);
int dma_start(hw_io io, uint32_t source_byte_address, uint32_t destination_byte_address, uint32_t words);
int dma_wait(hw_io io, uint32_t poll_limit, uint32_t *completed_words);
/* For an uncached, correctly ordered 32-bit MMIO mapping only. */
uint32_t hw_mmio_read(void *base, uint32_t offset);
void hw_mmio_write(void *base, uint32_t offset, uint32_t value);
#ifdef __cplusplus
}
#endif
#endif
