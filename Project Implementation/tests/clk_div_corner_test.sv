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

    // Program baseline registers in safe order: CTRL → CLK_DIV → SS_CTRL
    tb_top.apb.write(APB_CTRL, 32'h0000_0003);  // EN=1, MSTR=1, MODE=0, WIDTH=8
    tb_top.apb.write(APB_CLK_DIV, 32'h0000_0000);  // DIV=0 baseline
    tb_top.apb.write(APB_SS_CTRL, 32'h0000_0001);  // SS_EN[0]=1, SS_VAL[0]=0

    // --- Phase 2: Corner Cases ---
    int errors = 0;
    int div_corners[$] = '{0, 1, 8, 1024, 65535};

    foreach (div_corners[i]) begin
      int div_value = div_corners[i];
      tb_top.apb_write(APB_CLK_DIV, div_value);

      ref_model.predict_transfer(.tx_word(8'hA5), .width(8));
      tb_top.apb_write(APB_TX_DATA, 8'hA5);

      int poll_count = 0;
      while ((tb_top.apb.read(
          APB_STATUS
      ) & 32'h1) == 1) begin
        @(posedge tb_top.PCLK);
        poll_count++;

        if (poll_count > 500_000) begin
          $display("[CHECKER_ERROR] clk_div_corner: BUSY timeout for DIV=%0d", div_val);
          errors++;
          break;
        end
      end

      // Find measured PCLK period
      wait (tb_top.spi.sclk == 0);
      int measured_period = 0;
      @(posedge tb_top.spi.sclk);  // sync
      while (tb_top.spi.sclk != 1) begin
        @(posedge tb_top.PCLK) measured_period++;

        if (measured_period > 200_000) begin
          $display("[CHECKER_ERROR] clk_div_corner: period measurement timeout for DIV=%0d",
                   div_val);
          measured_period = -1;
          break;
        end
      end

      // Compare expected and measured
      int expected_period = 2 * (div_val + 1);
      if (expected_period != measured_period) begin
        $display("[SCOREBOARD_ERROR] clk_div_corner: DIV=%0d expected=%0d measured=%0d", div_val,
                 expected_period, measured_period);
        errors++;
      end

      // Drain RX & Sample Coverage
      ref_model.pop_rx();
      void'(tb_top.apb.read(APB_RX_DATA));
      coverage.sample_div(div_val);
    end

    // --- Phase 3: R25 Mid-Transfer DIV Update ---




    // --- Phase 4: Cleanup ---

      tb_top.apb.write(APB_SS_CTRL, 32'h0000_0000); // Deasserts SS
      ref_model.error_count = errors;
      $display("[INFO] clk_div_corner_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
