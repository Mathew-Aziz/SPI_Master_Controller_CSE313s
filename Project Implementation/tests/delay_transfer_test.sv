//- TP-DLY-01/02
`ifndef DELAY_TRANSFER_TEST_SV
`define DELAY_TRANSFER_TEST_SV 

localparam [7:0] APB_CTRL = 8'h00;
localparam [7:0] APB_STATUS = 8'h04;
localparam [7:0] APB_TX_DATA = 8'h08;
localparam [7:0] APB_RX_DATA = 8'h0C;
localparam [7:0] APB_CLK_DIV = 8'h10;
localparam [7:0] APB_SS_CTRL = 8'h14;
localparam [7:0] APB_INT_EN = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY = 8'h20;

localparam int TIMEOUT_CYCLES = 2_500_000;
localparam int IDLE_MEASURE_TIMEOUT = 200_000;
localparam CTRL_DEFAULT = (1 << 0) | (1 << 1);  // EN=1, MSTR=1
localparam SS_EN0 = 32'h0000_0001;
localparam SS_DISABLE = 32'h0000_0000;

class delay_transfer_test;

  static function int get_div_value();
    return tb_top.u_apb_bfm.apb_read(APB_CLK_DIV) [15:0];
  endfunction

  // Measures the number of PCLK cycles SCLK remains at idle level between transfers.
  // Returns -1 on timeout or if BUSY deasserts unexpectedly (R21 violation).
  static function int measure_idle_pclk(int timeout = IDLE_MEASURE_TIMEOUT);
    logic        cpol = tb_top.bfm_mode[1];  // CPOL: MODE[1] (R4)
    int unsigned div_val = get_div_value();
    int unsigned half_cycle_pclk = div_val + 1;  // R8: one SCLK half-cycle = (DIV+1) PCLKs

    // Wait for SCLK to reach idle level, confirmed stable for one half-cycle
    while (timeout > 0) begin
      @(posedge tb_top.PCLK);
      if (tb_top.u_wrap.u_dut.u_core.sclk == cpol) begin
        repeat (half_cycle_pclk) @(posedge tb_top.PCLK);
        if (tb_top.u_wrap.u_dut.u_core.sclk == cpol) break;
      end
      timeout--;
    end
    if (timeout == 0) return -1;

    // Count idle PCLKs until SCLK leaves idle level.
    // Start at half_cycle_pclk to account for the confirmation window already elapsed.
    int unsigned count = half_cycle_pclk;
    while (timeout > 0) begin
      @(posedge tb_top.PCLK);

      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1'b1) == 0) begin
        $display("[CHECKER_ERROR] delay_transfer: BUSY deasserted during DELAY gap");
        return -1;
      end

      if (tb_top.u_wrap.u_dut.u_core.sclk != cpol) return count;
      count++;
      timeout--;
    end

    return -1;
  endfunction

  // Validates observed idle PCLK count against expected.
  // For DELAY=0, any idle > 2 PCLKs is flagged.
  // For DELAY>0, allows 1 PCLK sync skew tolerance.
  static function void check_idle_gap(int observed, int expected, int delay_value, int gap_index,
                                      ref spi_ref_model ref_model);
    if (observed == -1) begin
      $display("[CHECKER_ERROR] delay_transfer: idle measurement timeout (DELAY=%0d, gap=%0d)",
               delay_value, gap_index);
      ref_model.error_count++;
      return;
    end

    if (delay_value == 0) begin
      if (observed > 2) begin
        $display(
            "[SCOREBOARD_ERROR] delay_transfer: unexpected idle with DELAY=0 (gap=%0d, observed=%0d)",
            gap_index, observed);
        ref_model.error_count++;
      end
    end else begin
      int difference = (observed > expected) ? observed - expected : expected - observed;
      if (difference > 1) begin
        $display(
            "[SCOREBOARD_ERROR] delay_transfer: idle PCLK mismatch (DELAY=%0d, gap=%0d, expected=%0d, observed=%0d)",
            delay_value, gap_index, expected, observed);
        ref_model.error_count++;
      end
    end
  endfunction

  static task drain_rx(input int num_words, ref spi_ref_model ref_model);
    for (int i = 0; i < num_words; i++) begin
      void'(tb_top.u_apb_bfm.apb_read(APB_RX_DATA));
      ref_model.pop_rx();
    end
  endtask

  static function int wait_for_busy_set(int timeout = TIMEOUT_CYCLES);
    for (int i = 0; i < timeout; i++) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 1) return 1;
    end
    $display("[CHECKER_ERROR] delay_transfer: timeout waiting for BUSY=1");
    return 0;
  endfunction

  static function int wait_for_busy_clear(int timeout = TIMEOUT_CYCLES);
    for (int i = 0; i < timeout; i++) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 0) return 1;
    end
    $display("[CHECKER_ERROR] delay_transfer: timeout waiting for BUSY=0");
    return 0;
  endfunction

  static task cleanup();
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_DISABLE);
    @(posedge tb_top.PCLK);
  endtask

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    // DELAY=0,1,>=128. Queue 2+ words, verify inserted idle half-cycles and BUSY stays 1 (R21).
    $display("[INFO] delay_transfer_test: starting");

    // --- Phase 1: Reset & Init ---
    tb_top.PRESETn = 0;
    repeat (5) @(posedge tb_top.PCLK);
    tb_top.PRESETn = 1;
    repeat (2) @(posedge tb_top.PCLK);

    tb_top.bfm_mode      = 2'b00;  // Mode 0 (CPOL=0, CPHA=0)
    tb_top.bfm_width     = 2'b00;  // 8-bit width
    tb_top.bfm_lsb_first = 1'b0;  // MSB-first
    tb_top.bfm_miso_word = 8'h00;  // Dummy echo
    coverage.sample_config(.mode(2'b00), .lsb_first(0), .width(2'b00));

    tb_top.u_apb_bfm.apb_write(APB_CTRL, CTRL_DEFAULT);
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 16'd1);
    coverage.sample_clk_div(16'd1);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_EN0);

    byte tx_words[3] = '{8'hA5, 8'h3C, 8'h78};

    // --- Phase 2: Idle Cycle Verification ---
    int delay_values[$] = '{0, 1, 200};
    foreach (delay_values[i]) begin
      int          delay_value = delay_values[i];
      int unsigned div_val = get_div_value();
      int          expected_idle_pclk = delay_value * (div_val + 1);

      tb_top.u_apb_bfm.apb_write(APB_DELAY, delay_value);
      coverage.sample_delay(.delay_val(delay_value), .queued(1'b1));

      foreach (tx_words[j]) begin
        byte word = tx_words[j];
        ref_model.predict_transfer(.tx_word(word), .width(8));
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, word);
      end

      if (!wait_for_busy_set()) begin
        ref_model.error_count++;
        continue;
      end

      for (int gap = 0; gap < 2; gap++) begin  // 2 gaps for 3 words
        check_idle_gap(.observed(measure_idle_pclk()), .expected(expected_idle_pclk),
                       .delay_value(delay_value), .gap_index(gap), .ref_model(ref_model));
      end

      if (!wait_for_busy_clear(TIMEOUT_CYCLES)) ref_model.error_count++;
      drain_rx(3, ref_model);
      cleanup();
      tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_EN0);
    end

    // --- Phase 3: Mid-Transfer DELAY Update ---
    // Verifies that a DELAY write mid-transfer takes effect on the *next* inter-word gap.
    tb_top.u_apb_bfm.apb_write(APB_DELAY, 8'd0);

    byte tx_words_p3[3] = '{8'hA5, 8'h3C, 8'h78};

    ref_model.predict_transfer(.tx_word(tx_words_p3[0]), .width(8));
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_words_p3[0]);

    if (!wait_for_busy_set(TIMEOUT_CYCLES)) ref_model.error_count++;

    // Update DELAY mid-transfer; should apply starting from the second inter-word gap
    int new_delay = 50;
    tb_top.u_apb_bfm.apb_write(APB_DELAY, new_delay);
    coverage.sample_delay(.delay_val(new_delay), .queued(1'b1));

    ref_model.predict_transfer(.tx_word(tx_words_p3[1]), .width(8));
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_words_p3[1]);

    ref_model.predict_transfer(.tx_word(tx_words_p3[2]), .width(8));
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_words_p3[2]);

    // First gap: DELAY was 0 when transfer started, expect no idle
    check_idle_gap(.observed(measure_idle_pclk()), .expected(0), .delay_value(0), .gap_index(0),
                   .ref_model(ref_model));

    // Second gap: new DELAY should be active
    int          second_gap = measure_idle_pclk(IDLE_MEASURE_TIMEOUT);
    int unsigned div_val_p3 = get_div_value();
    int          expected_second = new_delay * (div_val_p3 + 1);
    check_idle_gap(.observed(second_gap), .expected(expected_second), .delay_value(new_delay),
                   .gap_index(1), .ref_model(ref_model));

    if (!wait_for_busy_clear()) ref_model.error_count++;
    drain_rx(3, ref_model);
    cleanup();

    $display("[INFO] delay_transfer_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
