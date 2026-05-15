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

// Magic Numbers
localparam [7:0] EDGE_DETECTION_PATTERN = 8'hA5;
localparam int TIMEOUT_CYCLES = 2_500_000;
localparam int MEASURE_TIMEOUT = 200_000;
localparam MID_MEASURE_TIMEOUT = 5_000;
localparam CTRL_DEFAULT = (1 << 0) | (1 << 1);  // EN=1, MSTR=1, other fields default 0
localparam SS_EN0 = 32'h0000_0001;
localparam SS_DISABLE = 32'h0000_0000;

class clk_div_corner_test;

  static function int measure_sclk_period(int timeout = MEASURE_TIMEOUT);
    // Helper: measure full SCLK period in PCLK cycles
    int count = 0;
    wait (tb_top.u_wrap.u_dut.u_core.sclk == 0);

    @(posedge tb_top.u_wrap.u_dut.u_core.sclk);
    while (tb_top.u_wrap.u_dut.u_core.sclk == 1) begin
      @(posedge tb_top.PCLK);
      if (++count > timeout) begin
        $display("[CHECKER_ERROR] clk_div_corner: period measurement timeout");
        return -1;
      end
    end
    return 2 * count;
  endfunction

  static function int wait_for_busy_clear(int timeout = 100_000);
    for (int i = 0; i < timeout; i++) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 0) return 1;  // busy cleared
    end

    $display("[CHECKER_ERROR] clk_div_corner: timeout waiting for BUSY=0");
    return 0;  // timeout
  endfunction

  static function int wait_for_busy_set(int timeout = 100_000);
    for (int i = 0; i < timeout; i++) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 1) return 1;
    end

    $display("[CHECKER_ERROR] clk_div_corner: timeout waiting for BUSY=1");
    return 0;
  endfunction

  static task test_mid_transfer_div_update(ref spi_ref_model ref_model,
                                           ref spi_coverage_col coverage);
    int old_div_value = 1;
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, old_div_value);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, EDGE_DETECTION_PATTERN);
    if (!wait_for_busy_set(TIMEOUT_CYCLES)) ref_model.error_count++;

    int new_div_value = 10;
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV,
                               new_div_value);  // Write new DIV while transfer is active

    // Check Current Transfer
    int mid_period = measure_sclk_period(MID_MEASURE_TIMEOUT);
    if (mid_period != 2 * (old_div_value + 1)) begin
      $display("[SCOREBOARD_ERROR] clk_div_corner: mid-transfer DIV=1 expected=4 measured=%0d",
               mid_period);
      ref_model.error_count++;
    end
    // Cleanup
    void'(tb_top.u_apb_bfm.apb_read(APB_RX_DATA));
    ref_model.pop_rx();

    // Check Next Transfer
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, EDGE_DETECTION_PATTERN);
    if (!wait_for_busy_clear(TIMEOUT_CYCLES)) ref_model.error_count++;

    int next_period = measure_sclk_period(MID_MEASURE_TIMEOUT);
    if (next_period != 2 * (new_div_value + 1)) begin
      $display(
          "[SCOREBOARD_ERROR] clk_div_corner: post-mid-transfer DIV=10 expected=22 measured=%0d",
          next_period);
      ref_model.error_count++;
    end
    cleanup();
  endtask

  static task send_byte_and_wait(input byte tx_data, output byte rx_data,
                                 input int timeout = TIMEOUT_CYCLES);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_data);
    @(posedge tb_top.PCLK);
    if (!wait_for_busy_clear(timeout)) begin
      rx_data = 0;
      return;
    end
    rx_data = tb_top.u_apb_bfm.apb_read(APB_RX_DATA);
  endtask

  static task cleanup();
    // Deassert all slave selects
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_DISABLE);
    @(posedge tb_top.PCLK);
  endtask

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    // Program DIV=0,1, small, large(>=1024) and measure SCLK period in PCLK cycles (R8,R24).
    // Attempt mid-transfer DIV update to validate sampled-at-start (R25).

    // --- Phase 1: BFM & Register Init ---    
    $display("[INFO] clk_div_corner_test: starting");
    // Reset Sequence
    tb_top.PRESETn = 0;
    repeat (5) @(posedge tb_top.PCLK);
    tb_top.PRESETn = 1;
    repeat (2) @(posedge tb_top.PCLK);

    tb_top.bfm_mode      = 2'b00;  // Mode 0 (CPOL=0, CPHA=0)
    tb_top.bfm_miso_word = 8'h00;  // Dummy echo
    tb_top.bfm_pattern   = EDGE_DETECTION_PATTERN;

    tb_top.u_apb_bfm.apb_write(APB_CTRL, CTRL_DEFAULT);  // EN=1, MSTR=1, MODE=0, WIDTH=8
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, SS_DISABLE);  // DIV=0 baseline
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_EN0);  // SS_EN[0]=1, SS_VAL[0]=0

    // --- Phase 2: Corner Cases ---
    int  div_corners[$] = '{0, 1, 2, 3, 255, 1024, 65535};
    byte rx_data;

    foreach (div_corners[i]) begin
      int div_value = div_corners[i];

      tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, div_value);
      ref_model.predict_transfer(.tx_word(EDGE_DETECTION_PATTERN), .width(8));
      send_byte_and_wait(EDGE_DETECTION_PATTERN, rx_data);

      // Measure SCLK period
      int measured_period = measure_sclk_period();
      int expected_period = 2 * (div_value + 1);
      if (expected_period != measured_period) begin
        $display("[SCOREBOARD_ERROR] clk_div_corner: DIV=%0d expected=%0d measured=%0d", div_value,
                 expected_period, measured_period);
        ref_model.error_count++;
      end

      // Drain RX from reference model and sample coverage
      ref_model.pop_rx();
      coverage.sample_div(div_value);

      cleanup();
      tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_EN0);
    end

    // --- Phase 3: R25 Mid-Transfer DIV Update ---
    test_mid_transfer_div_update(ref_model, coverage);
    void'(tb_top.u_apb_bfm.apb_read(APB_RX_DATA));
    ref_model.pop_rx();
    coverage.sample_div_mid_update();

    cleanup();
    $display("[INFO] clk_div_corner_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass
`endif
