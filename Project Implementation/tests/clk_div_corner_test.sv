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
localparam [7:0] EDGE_DETECTION_PATTERN = 8'hA5;


class clk_div_corner_test;

  // Helper: measure full SCLK period in PCLK cycles
  static task measure_sclk_period(input int timeout, output int period);
    int count = 0;
    wait (tb_top.u_wrap.u_dut.u_core.sclk == 0);

    @(posedge tb_top.u_wrap.u_dut.u_core.sclk);
    while (tb_top.spi.sclk == 1) begin
      @(posedge tb_top.PCLK);
      count++;
      if (count >= timeout) begin
        $display("[CHECKER_ERROR] clk_div_corner: period measurement timeout");
        period = -1;
        return;
      end
    end
    period = 2 * count;
  endtask

  static function int wait_for_busy_clear(int timeout = 100_000);
    for (int i = 0; i < timeout; i++) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 0) return 1;  // busy cleared
    end
    $display("[CHECKER_ERROR] clk_div_corner: timeout waiting for BUSY=0");
    return 0;  // timeout
  endfunction


  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    // TODO:
    // Program DIV=0,1, small, large(>=1024) and measure SCLK period in PCLK cycles (R8,R24).
    // Optionally attempt mid-transfer DIV update to validate sampled-at-start (R25).

    $display("[INFO] clk_div_corner_test: starting");

    // ---------------------------------------------------------
    // --- Phase 1: BFM & Register Init ---    
    // ---------------------------------------------------------
    tb_top.bfm_mode      = 2'b00;  // Mode 0 (CPOL=0, CPHA=0)
    tb_top.bfm_miso_word = 8'h00;  // Dummy echo
    tb_top.bfm_pattern = EDGE_DETECTION_PATTERN;

    // Program baseline registers in safe order: CTRL → CLK_DIV → SS_CTRL
    tb_top.apb.write(APB_CTRL, 32'h0000_0003);  // EN=1, MSTR=1, MODE=0, WIDTH=8
    tb_top.apb.write(APB_CLK_DIV, 32'h0000_0000);  // DIV=0 baseline
    tb_top.apb.write(APB_SS_CTRL, 32'h0000_0001);  // SS_EN[0]=1, SS_VAL[0]=0

    // ---------------------------------------------------------
    // --- Phase 2: Corner Cases ---
    // ---------------------------------------------------------
    int errors = 0;
    int div_corners[$] = '{0, 1, 2, 3, 255, 1024, 65535};

    foreach (div_corners[i]) begin
      int div_value = div_corners[i];
      tb_top.apb.write(APB_CLK_DIV, div_value);

      ref_model.predict_transfer(.tx_word(EDGE_DETECTION_PATTERN), .width(8));
      tb_top.apb.write(APB_TX_DATA, EDGE_DETECTION_PATTERN);

      int poll_count = 0;
      while ((tb_top.apb.read(
          APB_STATUS
      ) & 32'h1) == 1) begin
        @(posedge tb_top.PCLK);
        poll_count++;

        if (poll_count > 2_500_000) begin
          $display("[CHECKER_ERROR] clk_div_corner: BUSY timeout for DIV=%0d", div_value);
          errors++;
          break;
        end
      end

      // Compare expected and measured
      int measured_period;
      measure_sclk_period(200_000, measured_period);

      int expected_period = 2 * (div_value + 1);
      if (expected_period != measured_period) begin
        $display("[SCOREBOARD_ERROR] clk_div_corner: DIV=%0d expected=%0d measured=%0d", div_value,
                 expected_period, measured_period);
        errors++;
      end

      // Drain RX & Sample Coverage
      ref_model.pop_rx();
      void'(tb_top.apb.read(APB_RX_DATA));
      coverage.sample_div(div_value);

      // Clean up: deassert SS
      tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);
      @(posedge tb_top.PCLK); 

      // Reassert SS before sending new TX word for the next iteration
      tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);
    end

    // ---------------------------------------------------------
    // --- Phase 3: R25 Mid-Transfer DIV Update ---
    // ---------------------------------------------------------
    int old_div_value = 1;
    tb_top.apb.write(APB_CLK_DIV, old_div_value);
    tb_top.apb.write(APB_TX_DATA, EDGE_DETECTION_PATTERN);
    if (!wait_for_busy_clear(2_500_000)) errors++;

    int new_div_value = 10;
    tb_top.apb.write(APB_CLK_DIV, new_div_value);  // Write new DIV while transfer is active

    // Check Current Transfer
    int mid_period;
    measure_sclk_period(5000, mid_period);
    if (mid_period != 2 * (old_div_value + 1)) begin
      $display("[SCOREBOARD_ERROR] clk_div_corner: mid-transfer DIV=1 expected=4 measured=%0d",
               mid_period);
      errors++;
    end
    // Cleanup
    void'(tb_top.apb.read(APB_RX_DATA));
    ref_model.pop_rx();

    // Check Next Transfer
    tb_top.apb.write(APB_TX_DATA, EDGE_DETECTION_PATTERN);
    int poll_count_r25 = 0;
    while ((tb_top.apb.read(
        APB_STATUS
    ) & 32'h1) == 1) begin
      @(posedge tb_top.PCLK);
      if (++poll_count_r25 >= 500_000) break;
    end

    int next_period;
    measure_sclk_period(5000, next_period);
    if (next_period != 2 * (new_div_value + 1)) begin
      $display(
          "[SCOREBOARD_ERROR] clk_div_corner: post-mid-transfer DIV=10 expected=22 measured=%0d",
          next_period);
      errors++;
    end

    void'(tb_top.apb.read(APB_RX_DATA));
    ref_model.pop_rx();
    coverage.sample_div_mid_update();

    // ---------------------------------------------------------
    // --- Phase 4: Cleanup ---
    // ---------------------------------------------------------
    tb_top.apb.write(APB_SS_CTRL, 32'h0000_0000);  // Deasserts SS
    ref_model.error_count = errors;
    $display("[INFO] clk_div_corner_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass
`endif
