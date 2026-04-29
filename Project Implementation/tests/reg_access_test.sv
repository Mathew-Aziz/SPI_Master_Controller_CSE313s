//- TP-REG-01/02/03/04 (+ TP-REG-05 optional)
`ifndef REG_ACCESS_TEST_SV
`define REG_ACCESS_TEST_SV

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class reg_access_test;

  static task run(ref spi_ref_model     ref_model,
                  ref spi_coverage_col  coverage);

    bit [31:0] rd;

    $display("[INFO] reg_access_test: starting");

    // TODO (minimum):
    // - Read reset values (R2)
    // - Write/readback CTRL, CLK_DIV, SS_CTRL, INT_EN, DELAY (R1)
    // - Verify STATUS is RO (write ignored)
    // - Verify TX_DATA read returns 0; RX_DATA write ignored (optional)

    tb_top.u_apb_bfm.apb_read(APB_CTRL, rd);

    $display("[INFO] reg_access_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif