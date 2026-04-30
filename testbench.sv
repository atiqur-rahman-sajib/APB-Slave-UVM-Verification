`include "uvm_macros.svh"
import uvm_pkg::*;

//--------------------------------------------
// TRANSACTION - data object passed between
// UVM components
//--------------------------------------------
class apb_transaction extends uvm_sequence_item;
    `uvm_object_utils(apb_transaction)

    rand bit        pwrite;
    rand bit [7:0]  paddr;
    rand bit [31:0] pwdata;
    bit      [31:0] prdata;

    // constrain address to valid registers only
    // addresses 0, 4, 8, 12
    constraint valid_addr {
        paddr inside {8'h00, 8'h04, 8'h08, 8'h0C};
    }

    function new(string name = "apb_transaction");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("PWRITE=%0b PADDR=0x%0h PWDATA=0x%0h PRDATA=0x%0h",
                          pwrite, paddr, pwdata, prdata);
    endfunction
endclass

//--------------------------------------------
// SEQUENCE - generates stimulus
//--------------------------------------------
class apb_sequence extends uvm_sequence #(apb_transaction);
    `uvm_object_utils(apb_sequence)

    function new(string name = "apb_sequence");
        super.new(name);
    endfunction

    task body();
        apb_transaction tx;
        int i;

        // write to all 4 registers
        for (i = 0; i < 4; i++) begin
            tx = apb_transaction::type_id::create("tx");
            start_item(tx);
            assert(tx.randomize() with {
                pwrite == 1;
                paddr  == i * 4;
            });
            finish_item(tx);
        end

        // read back all 4 registers
        for (i = 0; i < 4; i++) begin
            tx = apb_transaction::type_id::create("tx");
            start_item(tx);
            assert(tx.randomize() with {
                pwrite == 0;
                paddr  == i * 4;
            });
            finish_item(tx);
        end
    endtask
endclass

//--------------------------------------------
// DRIVER - drives transactions into DUT
//--------------------------------------------
class apb_driver extends uvm_driver #(apb_transaction);
    `uvm_component_utils(apb_driver)

    virtual interface apb_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRIVER", "No virtual interface found!")
    endfunction

    task run_phase(uvm_phase phase);
        apb_transaction tx;
        // initialize signals
        vif.PSEL    <= 0;
        vif.PENABLE <= 0;
        vif.PWRITE  <= 0;
        vif.PADDR   <= 0;
        vif.PWDATA  <= 0;
        @(posedge vif.PCLK);

        forever begin
            seq_item_port.get_next_item(tx);
            drive_transfer(tx);
            seq_item_port.item_done();
        end
    endtask

    task drive_transfer(apb_transaction tx);
        @(posedge vif.PCLK);
        vif.PSEL   <= 1;
        vif.PWRITE <= tx.pwrite;
        vif.PADDR  <= tx.paddr;
        vif.PWDATA <= tx.pwdata;

        @(posedge vif.PCLK);
        vif.PENABLE <= 1;
        @(posedge vif.PCLK);

        tx.prdata   = vif.PRDATA;
        vif.PSEL    <= 0;
        vif.PENABLE <= 0;
    endtask
endclass

//--------------------------------------------
// MONITOR - observes DUT signals
//--------------------------------------------
class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    virtual interface apb_if vif;
    uvm_analysis_port #(apb_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("MONITOR", "No virtual interface found!")
    endfunction

    task run_phase(uvm_phase phase);
        apb_transaction tx;
        forever begin
            @(posedge vif.PCLK);
            if (vif.PSEL && vif.PENABLE && vif.PREADY) begin
                tx        = apb_transaction::type_id::create("tx");
                tx.pwrite = vif.PWRITE;
                tx.paddr  = vif.PADDR;
                tx.pwdata = vif.PWDATA;
                tx.prdata = vif.PRDATA;
                ap.write(tx);
            end
        end
    endtask
endclass

//--------------------------------------------
// SCOREBOARD - checks correctness
//--------------------------------------------
class apb_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(apb_scoreboard)

    uvm_analysis_imp #(apb_transaction, apb_scoreboard) ap;

    // shadow register model
    bit [31:0] shadow_regs [0:3];
    int pass_count;
    int fail_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        pass_count = 0;
        fail_count = 0;
    endfunction

    function void write(apb_transaction tx);
        int idx;
        idx = tx.paddr / 4;

        if (tx.pwrite) begin
            // write - update shadow
            shadow_regs[idx] = tx.pwdata;
            `uvm_info("SCOREBOARD",
                $sformatf("WRITE: addr=0x%0h data=0x%0h", tx.paddr, tx.pwdata),
                UVM_LOW)
        end else begin
            // read - compare with shadow
            if (tx.prdata == shadow_regs[idx]) begin
                `uvm_info("SCOREBOARD",
                    $sformatf("READ PASSED: addr=0x%0h expected=0x%0h got=0x%0h",
                    tx.paddr, shadow_regs[idx], tx.prdata), UVM_LOW)
                pass_count++;
            end else begin
                `uvm_error("SCOREBOARD",
                    $sformatf("READ FAILED: addr=0x%0h expected=0x%0h got=0x%0h",
                    tx.paddr, shadow_regs[idx], tx.prdata))
                fail_count++;
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count),
            UVM_LOW)
    endfunction
endclass

//--------------------------------------------
// COVERAGE - tracks what has been tested
//--------------------------------------------
class apb_coverage extends uvm_subscriber #(apb_transaction);
    `uvm_component_utils(apb_coverage)

    apb_transaction tx;

    covergroup apb_cg;
        cp_addr: coverpoint tx.paddr {
            bins addr0 = {8'h00};
            bins addr4 = {8'h04};
            bins addr8 = {8'h08};
            bins addrC = {8'h0C};
        }
        cp_op: coverpoint tx.pwrite {
            bins write_op = {1};
            bins read_op  = {0};
        }
        // cross coverage - every address with every operation
        cx_addr_op: cross cp_addr, cp_op;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        apb_cg = new();
    endfunction

    function void write(apb_transaction t);
        tx = t;
        apb_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COVERAGE",
            $sformatf("Functional Coverage = %0.2f%%", apb_cg.get_coverage()),
            UVM_LOW)
    endfunction
endclass

//--------------------------------------------
// AGENT - contains driver, monitor, sequencer
//--------------------------------------------
class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)

    apb_driver    driver;
    apb_monitor   monitor;
    uvm_sequencer #(apb_transaction) sequencer;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver    = apb_driver::type_id::create("driver", this);
        monitor   = apb_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer #(apb_transaction)::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

//--------------------------------------------
// ENVIRONMENT - top level UVM container
//--------------------------------------------
class apb_env extends uvm_env;
    `uvm_component_utils(apb_env)

    apb_agent      agent;
    apb_scoreboard scoreboard;
    apb_coverage   coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = apb_agent::type_id::create("agent", this);
        scoreboard = apb_scoreboard::type_id::create("scoreboard", this);
        coverage   = apb_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent.monitor.ap.connect(scoreboard.ap);
        agent.monitor.ap.connect(coverage.analysis_export);
    endfunction
endclass

//--------------------------------------------
// TEST - top level test
//--------------------------------------------
class apb_test extends uvm_test;
    `uvm_component_utils(apb_test)

    apb_env      env;
    apb_sequence seq;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = apb_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        seq = apb_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #100;
        phase.drop_objection(this);
    endtask
endclass

//--------------------------------------------
// INTERFACE
//--------------------------------------------
interface apb_if (input logic PCLK);
    logic        PRESETn;
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [7:0]  PADDR;
    logic [31:0] PWDATA;
    logic [31:0] PRDATA;
    logic        PREADY;
endinterface

//--------------------------------------------
// TOP MODULE - connects everything
//--------------------------------------------
module tb_top;

    logic PCLK;

    // clock generation
    initial PCLK = 0;
    always #5 PCLK = ~PCLK;

    // interface instance
    apb_if apb_bus(.PCLK(PCLK));

    // DUT instance
    apb_slave dut (
        .PCLK    (PCLK),
        .PRESETn (apb_bus.PRESETn),
        .PSEL    (apb_bus.PSEL),
        .PENABLE (apb_bus.PENABLE),
        .PWRITE  (apb_bus.PWRITE),
        .PADDR   (apb_bus.PADDR),
        .PWDATA  (apb_bus.PWDATA),
        .PRDATA  (apb_bus.PRDATA),
        .PREADY  (apb_bus.PREADY)
    );

    // pass interface to UVM via config db
    initial begin
        uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top.*", "vif", apb_bus);
    end

    // reset and run test
    initial begin
        apb_bus.PRESETn = 0;
        apb_bus.PSEL    = 0;
        apb_bus.PENABLE = 0;
        run_test("apb_test");
    end

    initial begin
        #20;
        apb_bus.PRESETn = 1;
    end

endmodule
