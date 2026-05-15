//- TP-CLK-01/02 (+ TP-SPI-05 sampled-at-start with mid-transfer DIV write)
`ifndef CLK_DIV_CORNER_TEST_SV
`define CLK_DIV_CORNER_TEST_SV 

// Magic Numbers
localparam [7:0] EDGE_DETECTION_PATTERN = 8'hA5;
localparam int TIMEOUT_CYCLES = 2_500_000;
localparam int MEASURE_TIMEOUT = 200_000;
localparam int MID_MEASURE_TIMEOUT = 5_000;
localparam CTRL_DEFAULT = (1 << 0) | (1 << 1);  // EN=1, MSTR=1, other fields default 0
localparam SS_EN0 = 32'h0000_0001;
localparam SS_DISABLE = 32'h0000_0000;

class clk_div_corner_test;

  // -------------------------------------------------------------------------
  // Local APB wrappers: BFM + coverage sampling (R1/R22)
  // -------------------------------------------------------------------------
  static task apb_wr(input bit [7:0] addr, input bit [31:0] data, ref spi_coverage_col coverage);
    tb_top.u_apb_bfm.apb_write(addr, data);
    coverage.sample_apb(.addr(addr), .is_write(1'b1), .wdata(data), .rdata(32'h0), .pslverr(1'b0),
                        .pready(1'b1));
  endtask

  static task apb_rd(input bit [7:0] addr, output bit [31:0] data, ref spi_coverage_col coverage);
    tb_top.u_apb_bfm.apb_read(addr, data);
    coverage.sample_apb(.addr(addr), .is_write(1'b0), .wdata(32'h0), .rdata(data), .pslverr(1'b0),
                        .pready(1'b1));
  endtask

  static task measure_sclk_period(input int timeout = MEASURE_TIMEOUT, output int period,
                                  ref spi_coverage_col coverage);
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
    period = 2 * count;
  endtask

  static task wait_for_busy_clear(input int timeout = 100_000, output cleared);
    for (int i = 0; i < timeout; i++) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 0) cleared = 1;  // busy cleared
    end

    $display("[CHECKER_ERROR] clk_div_corner: timeout waiting for BUSY=0");
    cleared = 0;  // timeout
  endtask

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
    int new_div_value = 10;
    int mid_period;
    int next_period;
    int cleared;

    apb_wr(APB_CLK_DIV, old_div_value, coverage);
    coverage.sample_clk_div(old_div_value[15:0]);

    apb_wr(APB_TX_DATA, EDGE_DETECTION_PATTERN, coverage);
    if (!wait_for_busy_set(TIMEOUT_CYCLES)) ref_model.error_count++;

    apb_wr(APB_CLK_DIV, new_div_value, coverage);  // Write new DIV while transfer is active
    coverage.sample_clk_div(new_div_value[15:0]);

    // Check Current Transfer
    measure_sclk_period(MID_MEASURE_TIMEOUT, mid_period);
    if (mid_period != 2 * (old_div_value + 1)) begin
      $display("[SCOREBOARD_ERROR] clk_div_corner: mid-transfer DIV=1 expected=4 measured=%0d",
               mid_period);
      ref_model.error_count++;
    end
    // Cleanup
    void'(tb_top.u_apb_bfm.apb_read(APB_RX_DATA));
    ref_model.pop_rx();

    // Check Next Transfer
    apb_wr(APB_TX_DATA, EDGE_DETECTION_PATTERN, coverage);
    wait_for_busy_clear(TIMEOUT_CYCLES, cleared);
    if (!cleared) ref_model.error_count++;

    measure_sclk_period(MID_MEASURE_TIMEOUT, next_period);
    if (next_period != 2 * (new_div_value + 1)) begin
      $display(
          "[SCOREBOARD_ERROR] clk_div_corner: post-mid-transfer DIV=10 expected=22 measured=%0d",
          next_period);
      ref_model.error_count++;
    end
    cleanup();
  endtask

  static task send_byte_and_wait(input byte tx_data, output byte rx_data,
                                 input int timeout = TIMEOUT_CYCLES, ref spi_coverage_col coverage);
    int cleared;
    
    apb_wr(APB_TX_DATA, tx_data, coverage);
    @(posedge tb_top.PCLK);
    wait_for_busy_clear(timeout, cleared);
    if (!cleared) begin
      rx_data = 0;
      return;
    end
    apb_rd(APB_RX_DATA, rx_data, coverage);
  endtask

  static task cleanup();
    // Deassert all slave selects
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_DISABLE);
    @(posedge tb_top.PCLK);
  endtask

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    // Program DIV=0,1, small, large(>=1024) and measure SCLK period in PCLK cycles (R8,R24).
    // Attempt mid-transfer DIV update to validate sampled-at-start (R25).
    int div_corners[$] = '{0, 1, 2, 3, 255, 1024, 65535};
    int div_value;
    int expected_period;
    int measured_period;
    byte rx_data;
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

    apb_wr(APB_CTRL, CTRL_DEFAULT, coverage);  // EN=1, MSTR=1, MODE=0, WIDTH=8
    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00), .loopback(1'b0));

    apb_wr(APB_CLK_DIV, SS_DISABLE, coverage);  // DIV=0 baseline
    coverage.sample_clk_div(16'h0000);

    apb_wr(APB_SS_CTRL, SS_EN0, coverage);  // SS_EN[0]=1, SS_VAL[0]=0
    coverage.sample_ss(4'b0001, 4'b0000);

    // --- Phase 2: Corner Cases ---
    foreach (div_corners[i]) begin
      div_value = div_corners[i];
      expected_period = 2 * (div_value + 1);

      apb_wr(APB_CLK_DIV, div_value, coverage);
      coverage.sample_clk_div(div_value[15:0]);

      ref_model.predict_transfer(.tx_word(EDGE_DETECTION_PATTERN), .width(8));
      send_byte_and_wait(EDGE_DETECTION_PATTERN, rx_data, TIMEOUT_CYCLES, coverage);

      // Measure SCLK period
      measure_sclk_period(MEASURE_TIMEOUT, measured_period);
      if (expected_period != measured_period) begin
        $display("[SCOREBOARD_ERROR] clk_div_corner: DIV=%0d expected=%0d measured=%0d", div_value,
                 expected_period, measured_period);
        ref_model.error_count++;
      end

      // Drain RX from reference model and sample busy/ss
      ref_model.pop_rx();
      coverage.sample_busy(1'b0, 2'b00);

      cleanup();
      apb_wr(APB_SS_CTRL, SS_EN0, coverage);
      coverage.sample_ss(4'b0001, 4'b0000);
    end

    // --- Phase 3: R25 Mid-Transfer DIV Update ---
    test_mid_transfer_div_update(ref_model, coverage);
    void'(tb_top.u_apb_bfm.apb_read(APB_RX_DATA));
    ref_model.pop_rx();

    cleanup();
    coverage.sample_ss(4'b0000, 4'b0000);

    $display("[INFO] clk_div_corner_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass
`endif
