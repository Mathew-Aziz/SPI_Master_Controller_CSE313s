//- TP-CLK-01/02 (+ TP-SPI-05 sampled-at-start with mid-transfer DIV write)
`ifndef CLK_DIV_CORNER_TEST_SV
`define CLK_DIV_CORNER_TEST_SV 

localparam [7:0] APB_CTRL = 8'h00;
localparam [7:0] APB_STATUS = 8'h04;
localparam [7:0] APB_TX_DATA = 8'h08;
localparam [7:0] APB_RX_DATA = 8'h0C;
localparam [7:0] APB_CLK_DIV = 8'h10;
localparam [7:0] APB_SS_CTRL = 8'h14;
localparam [7:0] APB_INT_EN = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY = 8'h20;

class clk_div_corner_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    // TODO:
    // Program DIV=0,1, small, large(>=1024) and measure SCLK period in PCLK cycles (R8,R24).
    // Optionally attempt mid-transfer DIV update to validate sampled-at-start (R25).

    $display("[INFO] clk_div_corner_test: starting");

    // --- Phase 1: BFM & Register Init ---    
    tb_top.bfm_mode      = 2'b00;  // Mode 0 (CPOL=0, CPHA=0)
    tb_top.bfm_width     = 2'b00;  // 8-bit
    tb_top.bfm_lsb_first = 1'b0;  // MSB-first
    tb_top.bfm_miso_word = 8'h00;  // Dummy echo

    apb.write(APB_CTRL,
              32'h0000_0003);  // Program CTRL: EN=1, MSTR=1, MODE=0, WIDTH=8, LSB_FIRST=0
    apb.write(APB_SS_CTRL, 32'h0000_0001);  // Assert SS[0]

    // Corner-Case DIV Verification Loop



    // Optional R25 — Sampled-at-Start Behavior



    // Teardown and Reportinh



    $display("[INFO] clk_div_corner_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
