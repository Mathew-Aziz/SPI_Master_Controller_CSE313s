// =============================================================================
// apb_master_bfm.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal APB master BFM. Exposes two tasks: apb_write / apb_read. Uses the
// `cb_master` clocking block of apb_if.
//
// This is *not* UVM - it is just a module with tasks that the test programs
// call via a hierarchical reference (`tb_top.u_apb_bfm.apb_write(...)`).
// =============================================================================

`ifndef APB_MASTER_BFM_SV
`define APB_MASTER_BFM_SV 
`timescale 1ns / 1ps

module apb_master_bfm (
    apb_if.master apb
);


  initial begin
    apb.cb_master.psel    <= 1'b0;
    apb.cb_master.penable <= 1'b0;
    apb.cb_master.pwrite  <= 1'b0;
    apb.cb_master.paddr   <= '0;
    apb.cb_master.pwdata  <= '0;
  end

  task automatic apb_write(input [7:0] addr, input [31:0] data);
    @(apb.cb_master);
    apb.cb_master.psel    <= 1'b1;
    apb.cb_master.penable <= 1'b0;
    apb.cb_master.pwrite  <= 1'b1;
    apb.cb_master.paddr   <= addr;
    apb.cb_master.pwdata  <= data;
    @(apb.cb_master);
    apb.cb_master.penable <= 1'b1;
    do @(apb.cb_master); while (!apb.cb_master.pready);
    apb.cb_master.psel    <= 1'b0;
    apb.cb_master.penable <= 1'b0;
    apb.cb_master.pwrite  <= 1'b0;
  endtask

  task automatic apb_read(input [7:0] addr, output [31:0] data);
    @(apb.cb_master);
    apb.cb_master.psel    <= 1'b1;
    apb.cb_master.penable <= 1'b0;
    apb.cb_master.pwrite  <= 1'b0;
    apb.cb_master.paddr   <= addr;
    @(apb.cb_master);
    apb.cb_master.penable <= 1'b1;
    do @(apb.cb_master); while (!apb.cb_master.pready);
    data = apb.cb_master.prdata;
    apb.cb_master.psel    <= 1'b0;
    apb.cb_master.penable <= 1'b0;
  endtask

endmodule

`endif  // APB_MASTER_BFM_SV
