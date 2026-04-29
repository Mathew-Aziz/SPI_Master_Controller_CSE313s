//- TP-FIFO-05/06/07, TP-REG-04 (reserved offsets),
// TP-REG-05 (EN=0 ignored TX writes), plus illegal width attempt (log-only / robustness)
`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class error_injection_test;

  static task run(ref spi_ref_model     ref_model,
                  ref spi_coverage_col  coverage);

    bit [31:0] rd;

    $display("[INFO] error_injection_test: starting");

    // TODO (minimum):
    // - TX write when full => TX_OVF set + discard (R13)
    // - RX read when empty => returns 0, no RX_OVF (R15)
    // - Reserved offsets 0x24+ read 0, writes ignored (R23)
    // - Illegal width encoding attempt (undefined behavior): do not assert strict behavior

    tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);

    $display("[INFO] error_injection_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif