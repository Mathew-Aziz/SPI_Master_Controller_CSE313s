//- TP-SPI-01/02/03/04 (+ some TP-SPI-05 for sampled-at-start)
`ifndef MODE_COVERAGE_TEST_SV
`define MODE_COVERAGE_TEST_SV

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class mode_coverage_test;

  static task run(ref spi_ref_model     ref_model,
                  ref spi_coverage_col  coverage);

    $display("[INFO] mode_coverage_test: starting");

    // TODO:
    // Loop over MODE=0..3, WIDTH={8,16,32}, LSB_FIRST={0,1}
    // Program CTRL accordingly, send 1 word, read RX, check.
    // coverage.sample_config(...) per combination.
    // This test is the big one for R4/R5/R6/R7 + coverage closure.

    $display("[INFO] mode_coverage_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif