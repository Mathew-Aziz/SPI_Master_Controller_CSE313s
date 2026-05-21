// =============================================================================
// Requirements covered:
//   R3 : EN=0 holds shifter/FIFOs; SCLK idle;
//   R13: TX write while full discarded + STATUS.TX_OVF + INT_STAT[TX_OVF]
//   R14: RX transfer while full discards word + STATUS.RX_OVF + INT_STAT[RX_OVF]
//   R15: RX read while empty returns 0, no RX_OVF
//   R16: IRQ = |(INT_STAT & INT_EN) always; INT_EN does not gate capture
//   R17: INT_STAT W1C; write-0 no effect
//   R23: Reserved offsets read 0, writes ignored
//
// Spec bit positions (Section 3.2 STATUS):
//   bit 6 = RX_OVF  bit 5 = TX_OVF  bit 4 = RX_EMPTY
//   bit 3 = RX_FULL  bit 2 = TX_EMPTY  bit 1 = TX_FULL  bit 0 = BUSY
//
// Spec bit positions (Section 3.7 INT_STAT):
//   bit 4 = TRANSFER_DONE  bit 3 = RX_OVF  bit 2 = TX_OVF
//   bit 1 = RX_FULL  bit 0 = TX_EMPTY
// =============================================================================

`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV 

// Localparam aliases (keeps file self-contained)

class error_injection_test;

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

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] rd, status, int_stat;
    integer i;
    bit skip_rest;

    // SETUP
    ref_model.apply_reset(.min_cycles(2));

    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0004);
    coverage.sample_clk_div(16'h0004);

    // Enable core by default (EN=1, MSTR=1, MODE=0, LOOPBACK=0, WIDTH=8)
    apb_wr(coverage, APB_CTRL, 32'h0000_0003);
    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00), .loopback(1'b0));

    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    tb_top.bfm_mode      = 2'b00;
    tb_top.bfm_lsb_first = 1'b0;
    tb_top.bfm_width     = 2'b00;
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_miso_word = 32'hA5A5_A5A5;

    // =========================================================================
    // TC-1: R15 — RX_DATA read while empty returns 0, no RX_OVF
    // =========================================================================

    apb_rd(coverage, APB_RX_DATA, rd);
    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_rx_empty_read_zero(rd, status);
    coverage.sample_overflow(.tx_ovf(1'b0), .rx_ovf(1'b0), .rx_empty_rd(1'b1));  // ← ADD THIS

    apb_rd(coverage, APB_INT_STAT, int_stat);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);  // ← MOVE HERE

    coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b0),
                        .w1c_race_mask(5'b0));
    ref_model.check_int_stat_bit(int_stat, 3, 1'b0, "TC-1: RX_OVF set after empty read");

    // =========================================================================
    // TC-2: R11 — TX FIFO depth=8; TX_FULL asserts on 8th write
    // =========================================================================
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);  // Deassert SS
    coverage.sample_ss(4'b0000, 4'b0000);

    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_tx_status(status, .expect_full(1'b0), .expect_empty(1'b1), .expect_busy(1'b0));

    // NOTE: Without a reliable TX occupancy counter here, we sample a few
    // representative points only. fifo_stress_test will do full occupancy closure.
    coverage.sample_fifo(0, 0);

    for (i = 0; i < 8; i++) begin
      apb_wr(coverage, APB_TX_DATA, 32'h0000_0055 + i);
      if (i == 0) coverage.sample_fifo(1, 0);
      if (i == 3) coverage.sample_fifo(4, 0);
      if (i == 6) coverage.sample_fifo(7, 0);
      if (i == 7) coverage.sample_fifo(8, 0);
    end

    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_tx_status(status, .expect_full(1'b1), .expect_empty(1'b0), .expect_busy(1'b0));

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    ref_model.wait_and_drain();
    coverage.sample_fifo(0, 0);

    // =========================================================================
    // TC-3: R13 — TX overflow: 9th write discarded
    // =========================================================================
    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    for (i = 0; i < 8; i++) apb_wr(coverage, APB_TX_DATA, 32'h0000_00AA);
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00BB);  // 9th (overflow)

    // mark overflow event for cg_overflow
    coverage.sample_overflow(.tx_ovf(1'b1), .rx_ovf(1'b0), .rx_empty_rd(1'b0));

    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_reg_masked("STATUS_TX_OVF", 32'h0000_0020, status, 32'h0000_0020);

    apb_rd(coverage, APB_INT_STAT, int_stat);
    coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b0),
                        .w1c_race_mask(5'b0));
    ref_model.check_int_stat_bit(int_stat, 2, 1'b1, "TC-3: TX_OVF not set");

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    ref_model.wait_and_drain();

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // =========================================================================
    // TC-4: R17 — INT_STAT W1C: sticky, write-0 no effect, write-1 clears
    // =========================================================================
    skip_rest = 0;

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    for (i = 0; i < 8; i++) apb_wr(coverage, APB_TX_DATA, 32'h0000_00CC);
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00DD);  // overflow again
    coverage.sample_overflow(.tx_ovf(1'b1), .rx_ovf(1'b0), .rx_empty_rd(1'b0));

    apb_rd(coverage, APB_INT_STAT, int_stat);
    coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b0),
                        .w1c_race_mask(5'b0));

    ref_model.check_int_stat_bit(int_stat, 2, 1'b1, "TC-4: INT_STAT[2] not set before clear test");
    if (int_stat[2] !== 1'b1) skip_rest = 1;

    if (!skip_rest) begin
      // write-0 no effect
      apb_wr(coverage, APB_INT_STAT, 32'h0000_0000);
      // sampled as "no W1C"
      coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b0),
                          .w1c_race_mask(5'b0));

      apb_rd(coverage, APB_INT_STAT, int_stat);
      ref_model.check_int_stat_bit(int_stat, 2, 1'b1, "TC-4: INT_STAT[2] cleared by write-0");

      // W1C clear bit2
      apb_wr(coverage, APB_INT_STAT, 32'h0000_0004);
      coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b00100),
                          .w1c_race_mask(5'b0));

      apb_rd(coverage, APB_INT_STAT, int_stat);
      ref_model.check_int_stat_bit(int_stat, 2, 1'b0, "TC-4: INT_STAT[2] not cleared by W1C");
    end

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    ref_model.wait_and_drain();

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // =========================================================================
    // TC-5: R14 — RX overflow: 9th received word discarded
    // =========================================================================
    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    for (i = 0; i < 9; i++) apb_wr(coverage, APB_TX_DATA, 32'h0000_0011 + i);

    // Wait for all 9 transfers to complete WITHOUT draining RX
    // so we can check RX_FULL and RX_OVF flags first
    begin
      int wc = 0;
      apb_rd(coverage, APB_STATUS, status);
      while ((status[0] || !status[2]) && wc < 10000) begin
        apb_rd(coverage, APB_STATUS, status);
        wc++;
      end
      if (status[0] || !status[2])
        ref_model.checker_error("TC-5", "timeout waiting for 9 transfers");
    end

    @(posedge tb_top.PCLK);
    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_rx_status(status, .expect_full(1'b1), .expect_empty(1'b0));
    ref_model.check_reg_masked("STATUS_RX_OVF", 32'h0000_0040, status, 32'h0000_0040);

    coverage.sample_overflow(.tx_ovf(1'b0), .rx_ovf(1'b1), .rx_empty_rd(1'b0));

    apb_rd(coverage, APB_INT_STAT, int_stat);
    coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b0),
                        .w1c_race_mask(5'b0));
    ref_model.check_int_stat_bit(int_stat, 3, 1'b1, "TC-5: RX_OVF not set");

    // NOW drain RX manually (8 valid + 1 empty = 9 reads)
    // =========================================================================
    // Drain the 8 valid RX words first
    for (i = 0; i < 8; i++) begin
      apb_rd(coverage, APB_RX_DATA, rd);
      if (rd === 32'h0) begin
        $display("[SCOREBOARD_ERROR] TC-5: RX word %0d is 0 (expected valid data)", i);
        ref_model.error_count++;
      end
    end

    // W1C clear RX_OVF (bit3) BEFORE the 9th empty read
    apb_wr(coverage, APB_INT_STAT, 32'h0000_0008);
    coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b01000),
                        .w1c_race_mask(5'b0));

    // Wait for W1C to settle
    @(posedge tb_top.PCLK);

    // Verify clear worked
    apb_rd(coverage, APB_INT_STAT, int_stat);
    ref_model.check_int_stat_bit(int_stat, 3, 1'b0, "TC-5: INT_STAT[3] not cleared by W1C");

    // NOW safe to do the 9th empty read - RX_OVF is 0
    apb_rd(coverage, APB_RX_DATA, rd);  // should return 0, must NOT set RX_OVF
    if (rd !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] TC-5: 9th RX read nonzero (should be discarded), rd=0x%08h", rd);
      ref_model.error_count++;
    end

    // Verify RX_OVF stayed 0 after empty read
    repeat (1) @(posedge tb_top.PCLK);
    apb_rd(coverage, APB_INT_STAT, int_stat);
    ref_model.check_int_stat_bit(int_stat, 3, 1'b0, "TC-5: empty RX read incorrectly set RX_OVF");
    // =========================================================================
    // TC-6: R16 — IRQ masked when INT_EN=0; INT_STAT still captures
    // =========================================================================
    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    for (i = 0; i < 8; i++) apb_wr(coverage, APB_TX_DATA, 32'h0000_0022);
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00FF);  // overflow

    coverage.sample_overflow(.tx_ovf(1'b1), .rx_ovf(1'b0), .rx_empty_rd(1'b0));

    apb_rd(coverage, APB_INT_STAT, int_stat);
    coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b0),
                        .w1c_race_mask(5'b0));
    ref_model.check_int_stat_bit(int_stat, 2, 1'b1,
                                 "TC-6: INT_STAT[2] not set with INT_EN=0 (R16 violation)");

    ref_model.check_irq(1'b0, "TC-6: IRQ=1 when INT_EN=0");

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    ref_model.wait_and_drain();

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // =========================================================================
    // TC-7: R16 — IRQ asserts when INT_EN enables triggered interrupt
    // =========================================================================
    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_INT_EN, 32'h0000_0004);  // enable TX_OVF irq (bit2)
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00100), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    for (i = 0; i < 8; i++) apb_wr(coverage, APB_TX_DATA, 32'h0000_0033);
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00EE);  // overflow

    coverage.sample_overflow(.tx_ovf(1'b1), .rx_ovf(1'b0), .rx_empty_rd(1'b0));

    repeat (2) @(posedge tb_top.PCLK);

    apb_rd(coverage, APB_INT_STAT, int_stat);
    coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b00100), .w1c_mask(5'b0),
                        .w1c_race_mask(5'b0));
    ref_model.check_int_stat_bit(int_stat, 2, 1'b1, "TC-7: TX_OVF not set");

    ref_model.check_irq(1'b1, "TC-7: IRQ=0 when INT_EN[2]=1 and INT_STAT[2]=1");

    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(int_stat[4:0]), .int_en(5'b0), .w1c_mask(5'b0),
                        .w1c_race_mask(5'b0));

    @(posedge tb_top.PCLK);
    ref_model.check_irq(1'b0, "TC-7: IRQ did not deassert after INT_EN cleared");

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    ref_model.wait_and_drain();

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // TC-8
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    apb_wr(coverage, APB_TX_DATA, 32'h0000_0044);
    apb_wr(coverage, APB_TX_DATA, 32'h0000_0055);

    // WAIT for transfers to finish before disabling EN
    begin
      int wc = 0;
      apb_rd(coverage, APB_STATUS, status);
      while ((status[0] || !status[2]) && wc < 5000) begin
        apb_rd(coverage, APB_STATUS, status);
        wc++;
      end
    end

    // Drain the 2 RX words
    for (i = 0; i < 2; i++) apb_rd(coverage, APB_RX_DATA, rd);

    // Deassert SS before disabling EN
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    // NOW safe to write EN=0
    apb_wr(coverage, APB_CTRL, 32'h0000_0002);
    coverage.sample_ctrl_en(.en(1'b0), .sclk(tb_top.spi.sclk), .mode(2'b00), .ss_n(tb_top.spi.ss_n),
                            .ss_en(4'b0001), .tx_occ(0), .rx_occ(0));

    repeat (4) @(posedge tb_top.PCLK);

    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_tx_status(status, .expect_full(1'b0), .expect_empty(1'b1), .expect_busy(1'b0));

    begin

      logic sclk_val;
      sclk_val = tb_top.spi.sclk;
      if (sclk_val !== 1'b0) begin
        $display("[SCOREBOARD_ERROR] TC-8: SCLK not at CPOL idle when EN=0, SCLK=%b", sclk_val);
        ref_model.error_count++;
      end
    end

    // After verifying BUSY=0, TX_EMPTY=1, SCLK idle:
    begin
      logic [3:0] ss_n_val;
      ss_n_val = tb_top.spi.ss_n;
      if (ss_n_val !== 4'hF) begin
        $display(
            "[SCOREBOARD_ERROR] TC-8: SS_n not forced high when EN=0, SS_n=0x%0h (R3 violation)",
            ss_n_val);
        ref_model.error_count++;
      end
    end

    apb_wr(coverage, APB_CTRL, 32'h0000_0003);
    coverage.sample_ctrl_en(.en(1'b1), .sclk(tb_top.spi.sclk), .mode(2'b00), .ss_n(tb_top.spi.ss_n),
                            .ss_en(4'b0000), .tx_occ(0), .rx_occ(0));

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);
    // =========================================================================
    // TC-9: R23 — Reserved offsets read 0, writes ignored
    // =========================================================================
    begin
      bit [31:0] reserved_rd;

      bit [ 7:0] reserved_addrs[3] = '{8'h24, 8'h28, 8'h2C};
      foreach (reserved_addrs[i]) begin
        apb_rd(coverage, reserved_addrs[i], reserved_rd);
        ref_model.check_reserved_read_zero(reserved_addrs[i], reserved_rd);
      end

      apb_wr(coverage, 8'h24, 32'hDEAD_BEEF);
      coverage.sample_reserved(8'h24, 1'b1);
      apb_rd(coverage, 8'h24, reserved_rd);
      coverage.sample_reserved(8'h24, 1'b0);
      ref_model.check_reserved_read_zero(8'h24, reserved_rd);
    end

    // =========================================================================
    // TC-10: TX_DATA read returns 0 (write-only)
    // =========================================================================
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00A5);
    apb_rd(coverage, APB_TX_DATA, rd);
    ref_model.check_tx_data_read_zero(rd);

    ref_model.wait_and_drain(.max_wait(2000), .rx_words(1));

    // CLEANUP
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

  endtask
endclass

`endif
