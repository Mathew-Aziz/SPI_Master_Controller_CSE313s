//- TP-SPI-04/05 (strong) + boundary patterns of TP-SPI-03
`ifndef WIDTH_COVERAGE_TEST_SV
`define WIDTH_COVERAGE_TEST_SV

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class width_coverage_test;

  static task run(ref spi_ref_model     ref_model,
                  ref spi_coverage_col  coverage);

    $display("[INFO] width_coverage_test: starting");

    // TODO:
    // Focus on width boundaries:
    // - 8-bit patterns (0x01, 0x80, 0xFF)
    // - 16-bit patterns (0x0001, 0x8000, 0xA55A)
    // - 32-bit patterns (0x0000_0001, 0x8000_0000, 0xDEAD_BEEF)
    // Check exact cycle counts + BUSY timing (R7) and sampled-at-start (R25).

    $display("[INFO] width_coverage_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif