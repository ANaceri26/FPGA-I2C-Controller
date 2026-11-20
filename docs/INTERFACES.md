# Integration contract

## Common register port

One synchronous clock domain. Assert `reg_valid` with `reg_write`, 8-bit byte offset, and 32-bit write data. `reg_ready` is always 1. A write is accepted on each rising edge with valid and write asserted: hold for exactly one edge unless repeated writes are intended. Reads are combinational from reg_addr, without side effects. A bridge can sample read data on the acceptance edge. There are no byte enables or register-port error responses. Unmapped reads return zero; unmapped writes are ignored. Only documented aligned offsets decode; there is no address rounding.

Software must serialize access. Writing COMMAND while BUSY is ignored and does not queue a job. Configure while idle. DONE/error flags persist until W1C or a new accepted command. Completion wins a simultaneous W1C clear. IRQ is a level driven by IRQ_ENABLE and DONE. Map the register windows yourself; no physical/virtual base addresses are assumed.

## I2C external port

`scl_low` and `sda_low` mean **drive low** when 1, **release** when 0. Connect them to top-level open-drain tri-state assignments. Feed the actual pin levels into `scl_i` and `sda_i`. Provide suitable pull-ups. The core includes two-stage synchronization, but no dedicated input glitch rejection. Use only one initiating controller on this bus. Observe physical voltage and timing limits.

DIVIDER and TIMEOUT are captured at command launch. The command watchdog is a total active-command budget, not only a stretch budget. Timeout releases outputs; it does not guarantee an external target recovered. Software must handle the IDLE+HELD state after an abandoned transfer. Configuration writes may occur while HELD but not BUSY at the RTL level; the high-level C configure API rejects HELD to avoid changing timing midway through a transaction.

Valid commands: exactly one of WRITE/READ, optionally START/STOP/ACK, with START required when HELD=0; or STOP-only (2). Bits above 4 must be zero. ACK only has an effect on READ. Final NACK sent by the controller is not reported as a received-NACK error. The C API only uses nonreserved 7-bit addresses 0x08..0x77.

Read/modify/write is not appropriate for W1C status: write only the mask of flags you intend to clear. Unknown bits are ignored in STATUS writes.

## DMA memory completion port

- 32-bit byte addresses, 32-bit word data, aligned full-word transfers.
- `m_valid && m_ready` at a rising edge completes one operation.
- For reads, m_rdata is valid at that same edge. There is no later response channel.
- m_error is sampled only on acceptance. An erroring write must not change memory.
- Keep request payload stable while waiting. Data on m_wdata is irrelevant during reads.
- Timeout may withdraw an unaccepted request. The slave must not commit a request without valid and ready simultaneously asserted.
- The attached arbiter holds ownership across stalls; cancellation releases the lock.
- A slave that latches a pending operation must discard it on cancellation, as the board RAM adapter does when valid goes low.
- Both endpoints and bridges must be reset together for clean recovery. Destination data is not rolled back by reset/error.
- Arbitration is per beat; it does not reserve the bus for an entire buffered group.

BURST_WORDS may be a positive compile-time integer from 1 to 16; shipped default is 4. There is no runtime burst-size register. The reusable core itself does not enforce the declared implementation-support range; choose a supported value at elaboration.

Configuration validation covers word alignment, overlap, and 32-bit address-space overflow. It does not know your memory map. Use an address decoder/slave error response for unmapped or protected addresses. Length zero is a successful no-op, even if the unused address fields would be invalid for a nonzero transfer.

## Processor integration checklist

Choose or build bridges for your processor bus. Decode a peripheral base plus the documented offsets. Map DMA-accessible RAM separately. The register port and memory port are different interfaces, even though both use addresses.

Use proper device/uncached mappings and platform MMIO accessors. `hw_mmio_read/write` are minimal volatile accessors for platforms that already provide the needed ordering/mapping. Replace callbacks with barriers/access primitives when required. Obtain DMA bus addresses using your platform's mapping mechanism; do not cast ordinary CPU pointers and assume equivalence. Maintain caches or use suitable uncached/coherent buffers as the platform requires. Wire/clear interrupts if using them; the supplied C driver polls.

A native AXI/Avalon/Wishbone integration is not included or verified. In particular, do not expose this DMA's timeout-withdrawal behaviour directly on a bus that forbids withdrawing VALID before handshake.
