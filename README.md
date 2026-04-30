# APB Slave with UVM Verification - SystemVerilog

## Project Overview
An APB (Advanced Peripheral Bus) Slave register file implemented in 
SystemVerilog and verified using a full UVM (Universal Verification 
Methodology) testbench. The design contains 4 x 32-bit read/write 
registers verified through directed write/read sequences with 
functional coverage tracking.

## Specifications
- Protocol       : AMBA APB (Advanced Peripheral Bus)
- Data Width     : 32-bit
- Address Width  : 8-bit
- Registers      : 4 x 32-bit (at addresses 0x00, 0x04, 0x08, 0x0C)
- Reset          : Active LOW (PRESETn)
- PREADY         : Tied HIGH (zero wait state)
- Clock          : 100 MHz (10ns period)

## Files
- design.sv    : APB Slave module (apb_slave)
- testbench.sv : Full UVM testbench (tb_top)

## How It Works
The APB Slave responds to standard APB protocol:
- SETUP  Phase : PSEL asserted, PENABLE low
- ACCESS Phase : PENABLE asserted, data transferred
- WRITE        : Data latched on rising PCLK when PSEL + PENABLE + PWRITE
- READ         : Combinational output, no clock delay

## UVM Testbench Architecture
- Transaction  : apb_transaction  - randomized APB read/write item
- Sequence     : apb_sequence     - writes then reads all 4 registers
- Driver       : apb_driver       - drives APB signals into DUT
- Monitor      : apb_monitor      - observes DUT bus activity
- Scoreboard   : apb_scoreboard   - shadow register model, checks reads
- Coverage     : apb_coverage     - tracks address x operation coverage
- Agent        : apb_agent        - contains driver, monitor, sequencer
- Environment  : apb_env          - top level UVM container
- Test         : apb_test         - top level test entry point

## Test Sequence
Step 1 : Write random data to all 4 registers (0x00, 0x04, 0x08, 0x0C)
Step 2 : Read back all 4 registers
Step 3 : Scoreboard compares read data against shadow register model
Step 4 : Coverage report shows address x operation cross coverage

## Functional Coverage
Coverpoints:
- cp_addr  : All 4 register addresses (0x00, 0x04, 0x08, 0x0C)
- cp_op    : Write and Read operations
- cx_addr_op : Cross coverage - every address with every operation

## How to Simulate
Open in EDA Playground:
https://www.edaplayground.com/x/sHn2

Tools     : SystemVerilog + UVM 1.2
Simulator : Cadence Xcelium or Aldec Riviera Pro

## Author
Atiqur Rahman Sajib
