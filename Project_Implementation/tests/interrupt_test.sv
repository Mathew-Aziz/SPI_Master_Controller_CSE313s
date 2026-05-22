//- TP-IRQ-01/02/03/04 (must hit all 5 sources and masked+unmasked+clear+race)
`ifndef INTERRUPT_TEST_SV
`define INTERRUPT_TEST_SV 

class interrupt_test;

  static task automatic apb_wr(ref spi_coverage_col coverage, input bit [7:0] addr,
                               input bit [31:0] data);
    tb_top.u_apb_bfm.apb_write(addr, data);
    coverage.sample_apb(.addr(addr), .is_write(1'b1), .wdata(data), .rdata(32'h0), .pslverr(1'b0),
                        .pready(1'b1));
  endtask

  static task automatic apb_rd(ref spi_coverage_col coverage, input bit [7:0] addr,
                               output bit [31:0] data);
    tb_top.u_apb_bfm.apb_read(addr, data);
    coverage.sample_apb(.addr(addr), .is_write(1'b0), .wdata(32'h0), .rdata(data), .pslverr(1'b0),
                        .pready(1'b1));
  endtask

  // ===========================================================================
  // idle_dut
  // ---------------------------------------------------------------------------
  // Brings the DUT to a fully idle state before any W1C write to prevent race condition
  // IDLE conditions:
  //   1. Deassert SS to prevents any new transfer from starting.
  //   2. Poll STATUS until BUSY=0 AND TX_EMPTY=1 
  //   3. Drain the RX FIFO 
  //   4. Wait 3 extra PCLK cycles — guarantees that all registered one-cycle
  //      pulses (transfer_done_pulse, tx_pop, rx_push_valid), which are
  //      cleared to 0 by default every clock cycle
  // ===========================================================================
  static task automatic idle_dut(ref spi_coverage_col coverage, ref spi_ref_model ref_model,
                                    input int max_wait = 10000);
    bit [31:0] rd;
    int        wc;

    // Step 1: deassert SS so no new transfer can start
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    // Step 2: wait for BUSY=0 (STATUS[0]) AND TX_EMPTY=1 (STATUS[2])
    wc = 0;
    do begin
      apb_rd(coverage, APB_STATUS, rd);
      wc++;
    end while ((rd[0] == 1'b1 || rd[2] == 1'b0) && wc < max_wait);

    if (rd[0] == 1'b1 || rd[2] == 1'b0)
      ref_model.checker_error(
          "idle_dut", $sformatf(
          "timeout after %0d cycles: DUT did not reach idle (STATUS=0x%08h)", wc, rd));

    // Step 3: drain RX FIFO completely — read until RX_EMPTY (STATUS[4]) = 1
    do begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[4] == 1'b0)  // RX not empty
        apb_rd(coverage, APB_RX_DATA, rd);
    end while (rd[4] == 1'b0);

    // Step 4: three extra PCLK cycles so all one-cycle registered pulses
    repeat (3) @(posedge tb_top.PCLK);

  endtask


  // ===========================================================================
  // clear_int_stat
  // ---------------------------------------------------------------------------
  // idles the DUT first, then writes 0x1F to INT_STAT (W1C all bits).
  // ===========================================================================
  static task automatic clear_int_stat(ref spi_coverage_col coverage,
                                            ref spi_ref_model ref_model);
    idle_dut(coverage, ref_model);
    apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));
  endtask


  // ===========================================================================
  // check_race
  // ---------------------------------------------------------------------------
  // Reads INT_STAT and verifies that bit[bit_idx] is still 1 after a
  // simultaneous W1C + HW event (HW must win per Spec R18).
  // ===========================================================================
  static task automatic check_race(ref spi_coverage_col coverage, ref spi_ref_model ref_model,
                                   input string name, input int bit_idx);
    bit [31:0] rd;
    apb_rd(coverage, APB_INT_STAT, rd);
    if (rd[bit_idx] !== 1'b1) begin
      $display(
          "[SCOREBOARD_ERROR] R18 FAILED [%s]: INT_STAT[%0d] was cleared by W1C (expected to stay 1)",
          name, bit_idx);
      ref_model.error_count++;
    end else begin
      $display("[INFO SUCESS!!] R18 PASSED [%s]: INT_STAT[%0d] held 1 through simultaneous W1C",
               name, bit_idx);
    end
  endtask


  // ===========================================================================
  // run — main test entry point
  // ===========================================================================
  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] rd = 0;
    bit [31:0] val = 0;
    int        i;

    $display("[INFO] interrupt_test: starting");

    // -----------------------------------------------------------------------
    // Global BFM and DUT initialisation
    // -----------------------------------------------------------------------
    tb_top.bfm_mode      = 2'b00;  // CPOL=0 CPHA=0
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_width     = 2'b00;  // 8-bit
    tb_top.bfm_lsb_first = 1'b0;  // MSB-first
    tb_top.bfm_miso_word = 32'h0000_00A5;

    apb_wr(coverage, APB_CTRL, 32'h0000_0003);  // EN=1, MSTR=1
    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0004);  // PCLK/10
    coverage.sample_clk_div(16'h0004);
    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00), .loopback(1'b0));

    // Start from a fully clean interrupt state
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);
    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));


    // =======================================================================
    // Sub-test: TRANSFER_DONE (bit 4)
    // =======================================================================
    $display("[INTERRUPT_TEST] Starting TRANSFER_DONE IRQ test");

    // --- 4a. Enabled + unmasked: IRQ must fire ---
    clear_int_stat(coverage, ref_model);

    apb_wr(coverage, APB_INT_EN, 32'h0000_0010);  // enable TRANSFER_DONE only
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b10000), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    val = $urandom() & 8'hFF;
    apb_wr(coverage, APB_TX_DATA, val);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    repeat (5000) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    end
    coverage.sample_busy(1'b0, 2'b00);

    if (tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test",
                              "TRANSFER_DONE IRQ not asserted after transfer completion");

    repeat (2) begin
      apb_rd(coverage, APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT_TRANSFER_DONE", 8'b0001_0000, rd, 8'b0001_0000);
      coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b10000), .w1c_mask(5'b0),
                          .w1c_race_mask(5'b0));
    end

    // W1C clear — idle first so INT_STAT_W1C_NORMAL sees no HW events
    idle_dut(coverage, ref_model);
    apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b10000), .w1c_mask(5'b10000),
                        .w1c_race_mask(5'b0));

    apb_rd(coverage, APB_INT_STAT, rd);
    if (rd[4] == 1'b1)
      ref_model.checker_error("Interrupt test", "TRANSFER_DONE INT_STAT bit not cleared after W1C");
    if (tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "TRANSFER_DONE IRQ asserted after W1C clear");

    // --- 4b. Masked: INT_STAT must still capture, IRQ must stay low ---
    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // Safe clear before the masked transfer
    clear_int_stat(coverage, ref_model);

    apb_wr(coverage, APB_TX_DATA, val);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    repeat (5000) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    end

    // Deassert SS, then idle before reading INT_STAT
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);
    idle_dut(coverage, ref_model);

    if (tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "TRANSFER_DONE IRQ asserted despite being masked");

    repeat (2) begin
      apb_rd(coverage, APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT_TRANSFER_DONE_masked", 8'b0001_0000, rd, 8'b0001_0000);
      coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));
    end

    // W1C race
    clear_int_stat(coverage, ref_model);

    apb_wr(coverage, APB_TX_DATA, 32'h0000_00AA);  // word 1
    apb_wr(coverage, APB_TX_DATA, 32'h0000_0055);  // word 2 — keeps BUSY=1 after word 1
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);  // SS asserted, transfer starts

    repeat (80) @(posedge tb_top.PCLK);  // advance to N+80

    // This write lands concurrent with transfer_done_pulse by design
    apb_wr(coverage, APB_INT_STAT, 32'h0000_0010);

    check_race(coverage, ref_model, "TRANSFER_DONE", 4);

    // Drain word 2, then fully idle before next sub-test
    repeat (5000) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    end
    idle_dut(coverage, ref_model);
    clear_int_stat(coverage, ref_model);


    // =======================================================================
    // Sub-test: TX_EMPTY (bit 0)
    // =======================================================================
    $display("[INTERRUPT_TEST] Starting TX_EMPTY IRQ test");

    // --- 0a. Enabled + unmasked ---
    clear_int_stat(coverage, ref_model);

    apb_wr(coverage, APB_INT_EN, 32'h0000_0001);  // enable TX_EMPTY only
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00001), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    val = $urandom() & 8'hFF;
    apb_wr(coverage, APB_TX_DATA, val);
    apb_rd(coverage, APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT", 8'b0000_0000, rd, 8'b0000_0001);

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    repeat (5000) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    end

    if (tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test",
                              "TX_EMPTY IRQ not asserted when TX_EMPTY condition met");

    repeat (2) begin
      apb_rd(coverage, APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0001, rd, 8'b0000_0001);
      coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00001), .w1c_mask(5'b0),
                          .w1c_race_mask(5'b0));
    end

    // W1C clear — idle first
    idle_dut(coverage, ref_model);
    apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00001), .w1c_mask(5'b11111),
                        .w1c_race_mask(5'b0));

    apb_rd(coverage, APB_INT_STAT, rd);
    if (rd[0] == 1'b1)
      ref_model.checker_error("Interrupt test", "TX_EMPTY INT_STAT bit not cleared after W1C");
    if (tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "TX_EMPTY IRQ asserted after W1C clear");

    // --- 0b. Masked ---
    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    val = $urandom() & 8'hFF;
    apb_wr(coverage, APB_TX_DATA, val);
    apb_rd(coverage, APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT", 8'b0000_0000, rd, 8'b0000_0001);

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    repeat (5000) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    end

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);
    idle_dut(coverage, ref_model);

    if (tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "TX_EMPTY IRQ asserted despite being masked");

    repeat (2) begin
      apb_rd(coverage, APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0001, rd, 8'b0000_0001);
      coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));
    end

    // --- 0c. W1C Race ---
    clear_int_stat(coverage, ref_model);

    apb_wr(coverage, APB_TX_DATA, 32'h0000_00AA);  // word 1
    apb_wr(coverage, APB_TX_DATA, 32'h0000_0055);  // word 2
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    apb_wr(coverage, APB_INT_STAT, 32'h0000_0002);
    // Discard the unrelated RX_FULL clear — it was irrelevant in the original
    repeat (78) @(posedge tb_top.PCLK);

    // Race write: ACCESS lands concurrent with tx_pop && tx_count==1
    apb_wr(coverage, APB_INT_STAT, 32'h0000_0001);

    check_race(coverage, ref_model, "TX_EMPTY", 0);

    repeat (5000) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    end
    idle_dut(coverage, ref_model);
    clear_int_stat(coverage, ref_model);

    repeat (3) @(posedge tb_top.PCLK);


    // =======================================================================
    // Sub-test: TX_OVF (bit 2)
    // =======================================================================
    $display("[INTERRUPT_TEST] TX_OVF IRQ TEST starting at t=%0t", $time);


    clear_int_stat(coverage, ref_model);  // also deasserts SS via idle

    apb_wr(coverage, APB_INT_EN, 32'h0000_0004);  // enable TX_OVF only
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00100), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // Write exactly 9 words with SS deasserted:
    //   words 0-7 fill the FIFO (no drop, no tx_push_dropped)
    //   word  8 sets INT_STAT[TX_OVF]
    for (int i = 0; i < 9; i++) begin
      val = $urandom() & 8'hFF;
      apb_wr(coverage, APB_TX_DATA, val);
    end
    coverage.sample_overflow(.tx_ovf(1'b1), .rx_ovf(1'b0), .rx_empty_rd(1'b0));

    // After the 9th write Wait 3 cycles to be safe.
    repeat (3) @(posedge tb_top.PCLK);

    repeat (2) begin
      apb_rd(coverage, APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0100, rd, 8'b0000_0100);
      coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00100), .w1c_mask(5'b0),
                          .w1c_race_mask(5'b0));
    end

    if (tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test",
                              "TX_OVF IRQ not asserted when TX_OVF condition met");

    // W1C clear
    apb_wr(coverage, APB_INT_STAT, 32'h0000_0004);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00100), .w1c_mask(5'b00100),
                        .w1c_race_mask(5'b0));

    // Verify cleared
    apb_rd(coverage, APB_INT_STAT, rd);
    if (rd[2] == 1'b1)
      ref_model.checker_error("Interrupt test", "TX_OVF INT_STAT bit not cleared after W1C");

    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // Drain the TX FIFO by asserting SS and waiting for completion
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    repeat (5000) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    end
    coverage.sample_busy(1'b0, 2'b00);

    if (rd[0] != 1'b0 || rd[2] != 1'b1)
      $display("[INTERRUPT_TEST] WARNING: TX drain did not complete (STATUS=0x%08h)", rd);

    idle_dut(coverage, ref_model);
    clear_int_stat(coverage, ref_model);

    // --- 2b. Masked: INT_STAT must capture TX_OVF, IRQ must stay low ---
    // Fill to overflow again, SS still deasserted after idle
    for (int i = 0; i <= 8; i++) begin
      val = $urandom() & 8'hFF;
      apb_wr(coverage, APB_TX_DATA, 32'(i));
      if (tb_top.spi.cb_mon.irq == 1'b1) begin
        ref_model.checker_error("Interrupt test", "TX_OVF IRQ is asserted despite being masked");
        break;
      end
    end

    repeat (2) begin
      apb_rd(coverage, APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0100, rd, 8'b0000_0100);
      coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));
    end

    // Safe clear before W1C race setup
    // 3-cycle wait: tx_push_dropped is already 0 (no concurrent TX_DATA write)
    repeat (3) @(posedge tb_top.PCLK);
    apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // Drain TX FIFO and fully idle before RX section
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);
    repeat (5000) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    end
    idle_dut(coverage, ref_model);
    clear_int_stat(coverage, ref_model);


    // =======================================================================
    // Sub-test: RX_FULL (bit 1) and RX_OVF (bit 3)
    // Closes coverage bins: cp_rx_full_irq, cp_rx_ovf_irq,
    //                       cp_rx_full_masked, cp_rx_ovf_masked, cp_int_en
    // =======================================================================

    $display("[INTERRUPT_TEST] Starting RX_FULL and RX_OVF IRQ test at time %0t", $time);

    // 1. Ensure RX FIFO is empty (drain it)
    do begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[4] == 1'b0) apb_rd(coverage, APB_RX_DATA, rd);
    end while (rd[4] == 1'b0);

    // 2. Mask all interrupts so RX_FULL fires while INT_EN[1]=0
    apb_wr(coverage, APB_INT_EN, 32'h0000_0002);
    apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00010), .w1c_mask(5'b11111),
                        .w1c_race_mask(5'b0));

    // 3. Configure DUT
    apb_wr(coverage, APB_CTRL, 32'h0000_0003);  // EN=1, MSTR=1, mode0, 8-bit
    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0001);  // CLK_DIV=1

    // 4. Run exactly 8 transfers WITHOUT reading RX_DATA.
    //    Each transfer pushes one byte into the RX FIFO.
    //    The 8th push fills the FIFO → sets INT_STAT[RX_FULL].
    for (int i = 0; i < 8; i++) begin
      apb_wr(coverage, APB_TX_DATA, 32'(i));
      apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
      coverage.sample_ss(4'b0001, 4'b0000);
      do apb_rd(coverage, APB_STATUS, rd); while (rd[0]);
      apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
      coverage.sample_ss(4'b0000, 4'b0000);
    end

    // 5. Read INT_STAT — closes cp_rx_full_irq and cp_rx_full_masked
    repeat (2) begin
      apb_rd(coverage, APB_INT_STAT, rd);
      coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00010));
      if (tb_top.spi.cb_mon.irq != 1'b1)
        ref_model.checker_error("Interrupt test",
                                "RX_FULL IRQ not asserted when RX_FULL condition met");
    end
    //W1C test
    apb_rd(coverage, APB_RX_DATA, rd);

    apb_wr(coverage, APB_INT_STAT, 32'h0000_0002);
    coverage.sample_irq(.int_stat(5'b0010), .int_en(5'b00010), .w1c_mask(5'b00010),
                        .w1c_race_mask(5'b0));
    apb_rd(coverage, APB_INT_STAT, rd);
    coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00010));
    if (rd[1] == 1'b1)
      ref_model.checker_error("Interrupt test", "RX_FULL INT_STAT bit not cleared after W1C");

    //W1C Race
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00CC);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    repeat (32) @(posedge tb_top.PCLK);  // wait for any pulses to settle
    apb_wr(coverage, APB_INT_STAT, 32'h0000_0002);
    coverage.sample_irq(.int_stat(5'b0010), .int_en(5'b00010), .w1c_mask(5'b00010),
                        .w1c_race_mask(5'b1));
    check_race(coverage, ref_model, "RX_FULL", 1);
    do apb_rd(coverage, APB_STATUS, rd); while (rd[0]);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    // 6. RX FIFO is now full. One more transfer → 9th push is dropped
    //    → sets INT_STAT[RX_OVF].
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00BB);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);
    do apb_rd(coverage, APB_STATUS, rd); while (rd[0]);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    apb_wr(coverage, APB_INT_EN, 32'h0000_0008);

    // 7. Sample again — closes cp_rx_ovf_irq and cp_rx_ovf_masked
    repeat (2) begin
      apb_rd(coverage, APB_INT_STAT, rd);
      $display("RD VALUE CP_RX_OVF_MASKED ", rd);
      coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00000));
      coverage.sample_overflow(.tx_ovf(1'b0), .rx_ovf(1'b1), .rx_empty_rd(1'b0));
      if (tb_top.spi.cb_mon.irq != 1'b1)
        ref_model.checker_error("Interrupt test",
                                "RX_OVF IRQ not asserted when RX_OVF condition met");
    end

    //W1C test
    apb_wr(coverage, APB_INT_STAT, 32'h0000_0008);
    coverage.sample_irq(.int_stat(5'b1000), .int_en(5'b01000), .w1c_mask(5'b01000),
                        .w1c_race_mask(5'b0));
    apb_rd(coverage, APB_INT_STAT, rd);
    coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00010));
    if (rd[3] == 1'b1)
      ref_model.checker_error("Interrupt test", "RX_OVF INT_STAT bit not cleared after W1C");

    //W1C Race
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00EE);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);
    repeat (32) @(posedge tb_top.PCLK);  // wait for any pulses to settle
    apb_wr(coverage, APB_INT_STAT, 32'h0000_0008);
    coverage.sample_irq(.int_stat(5'b1000), .int_en(5'b1000), .w1c_mask(5'b01000),
                        .w1c_race_mask(5'b1));
    check_race(coverage, ref_model, "RX_OVF", 3);
    do apb_rd(coverage, APB_STATUS, rd); while (rd[0]);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);


    // 8. Enable all interrupts then sample — closes cp_int_en all_on
    apb_wr(coverage, APB_INT_EN, 32'h0000_001F);
    apb_rd(coverage, APB_INT_STAT, rd);
    coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b11111));

    // 9. Clean up:
    //    Drain RX FIFO so subsequent reads from other tests start clean.
    //    Then safe-clear all interrupt state.
    do begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[4] == 1'b0) apb_rd(coverage, APB_RX_DATA, rd);
    end while (rd[4] == 1'b0);

    idle_dut(coverage, ref_model);

    // W1C clear — DUT is fully idle here, so INT_STAT_W1C_NORMAL passes.
    apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b11111), .w1c_mask(5'b11111),
                        .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // Restore CLK_DIV to original value for any subsequent tests in the same run
    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0004);
    coverage.sample_clk_div(16'h0004);

    $display("[INFO] interrupt_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
