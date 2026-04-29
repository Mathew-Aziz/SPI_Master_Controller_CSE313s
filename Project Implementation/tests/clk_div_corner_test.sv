//- TP-CLK-01/02 (+ TP-SPI-05 sampled-at-start with mid-transfer DIV write)
`ifndef CLK_DIV_CORNER_TEST_SV
`define CLK_DIV_CORNER_TEST_SV

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class clk_div_corner_test;

  static task run(ref spi_ref_model     ref_model,
                  ref spi_coverage_col  coverage);

    $display("[INFO] clk_div_corner_test: starting");

    // TODO:
    // Program DIV=0,1, small, large(>=1024) and measure SCLK period in PCLK cycles (R8,R24).
    // Optionally attempt mid-transfer DIV update to validate sampled-at-start (R25).

    $display("[INFO] clk_div_corner_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif