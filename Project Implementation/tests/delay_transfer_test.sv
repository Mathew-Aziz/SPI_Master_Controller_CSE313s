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

// Magic Numbers
localparam int TIMEOUT_CYCLES = 2_500_000;
localparam int IDLE_MEASURE_TIMEOUT = 200_000;
localparam CTRL_DEFAULT = (1 << 0) | (1 << 1);  // EN=1, MSTR=1
localparam SS_EN0 = 32'h0000_0001;
localparam SS_DISABLE = 32'h0000_0000;

class delay_transfer_test;

  static function int measure_idle_pclk(int timeout = IDLE_MEASURE_TIMEOUT);
    while (timeout > 0) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 0) break;
      timeout--;
    end
    if (timeout == 0) return -1;

    int count = 0;
    while (timeout > 0) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 1) break;  // BUSY re-asserted
      count++;
      timeout--;
    end
    if (timeout == 0) return -1;

    return count;
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
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 1) return 1;
    end

    $display("[CHECKER_ERROR] delay_transfer: timeout waiting for BUSY=0");
    return 0;
  endfunction

  static task cleanup();
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_DISABLE);
    @(posedge tb_top.PCLK);
  endtask


  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    // TODO:
    // DELAY= 0,1,>=128. Queue 2+ words, verify inserted idle half-cycles and BUSY stays 1 (R21).

    $display("[INFO] delay_transfer_test: starting");
    // --- Phase 1: Reset & Init ---
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

    int div_value = 1;

    // --- Phase 2: Idle Cycle Verification ---
    int delay_values  [$] = '{0, 1, 200};
    foreach (delay_values[i]) begin
      int delay_value = delay_values[i];
      int expected_idle_pclk = div_value * (div_value + 1);

      // Update delay value
      tb_top.u_apb_bfm.apb_write(APB_DELAY, delay_value);
      coverage.sample_delay();

      // Predict + queue TX words
      int number_of_words = 3;
      byte tx_words[number_of_words] = '{8'hA5, 8'h3C, 8'h78};
      foreach (tx_words[word]) begin
        ref_model.predit_transfer(.tx_word(word), .width(8));
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, word);
      end

      // Wait for first transfer to start
      if (!wait_for_busy_set()) begin
        ref_model.error_count++;
        continue;
      end

      // 2 gaps for 3 words
      int number_of_gaps = number_of_words - 1;
      for (int gap = 0; gap < number_of_gaps; gap++) begin
        int observed_idle = measure_idle_pclk();
        if (observed_idle == -1) begin
          $display("[CHECKER_ERROR] delay_transfer: idle measurement timeout (DELAY=%0d, gap=%0d)",
                   delay_value, gap);
          ref_model.error_count++;
          break;
        end

        if (delay_value > 0) begin
          int difference = (observed_idle > expected_idle_pclk) ? observed_idle - expected_idle_pclk : 
                              expected_idle_pclk - observed_idle;
          if (difference > 1) begin  // Allow 1 PCLK sync skew
            $display(
                "[SCOREBOARD_ERROR] delay_transfer: idle PCLK mismatch (DELAY=%0d, expected=%0d, observed=%0d)",
                delay_value, expected_idle_pclk, observed_idle);
            ref_model.error_count++;
          end
        end else begin
          if (observed_idle > 2) begin
            $display(
                "[SCOREBOARD_ERROR] delay_transfer: unexpected idle with DELAY=0 (observed=%0d)",
                observed_idle);
            ref_model.error_count++;
          end
        end
      end

      // Finishing
      if (!wait_for_busy_clear(TIMEOUT_CYCLES)) ref_model.error_count++;
      drain_rx(3, ref_model);
      cleanup();
      tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_EN0);
    end

    // --- Phase 3: Mid-Transfer DELAY Update ---
    int old_delay = 8'd0;
    tb_top.u_apb_bfm.apb_write(APB_DELAY, old_delay);  // Zero Delay
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_words[0]);
    if (!wait_for_busy_set(TIMEOUT_CYCLES)) ref_model.error_count++;

    // Write new DELAY mid-transfer
    int new_delay = 50;
    tb_top.u_apb_bfm.apb_write(APB_DELAY, new_delay);

    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_words[1]);
    ref_model.predit_transfer(.tx_word(tx_words[0]), .width(8));
    ref_model.predict_transfer(.tx_word(tx_words[1]), .width(8));

    // Measure first gap (old delay expected)
    int first_gap = measure_idle_pclk();
    if (first_gap > 2) begin
      $display(
          "[SCOREBOARD_ERROR] delay_transfer: mid-update first gap used new DELAY (expected~0, observed=%0d)",
          first_gap);
      ref_model.error_count++;
    end

    // Measure second gap (new delay expected)
    int second_gap = measure_idle_pclk(IDLE_MEASURE_TIMEOUT);
    int expected_second = new_delay * (div_value + 1);
    if (second_gap != -1) begin
      int difference = (second_gap > expected_second) ? 
                          second_gap - expected_second : 
                          expected_second - second_gap;
      if (difference > 1) begin
        $display(
            "[SCOREBOARD_ERROR] delay_transfer: mid-update second gap mismatch (DELAY=%0d, expected=%0d, observed=%0d)",
            new_delay, expected_second, second_gap);
        ref_model.error_count++;
      end
    end

    if (!wait_for_busy_clear()) ref_model.error_count++;
    drain_rx(2, ref_model);
    cleanup();

    $display("[INFO] delay_transfer_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
