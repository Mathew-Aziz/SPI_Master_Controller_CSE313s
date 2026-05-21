// =============================================================================
// error_injection_test.sv
// -----------------------------------------------------------------------------
// Requirements covered:
//   R3  : EN=0 holds shifter/FIFOs; SCLK idle; SS_n forced high
//   R13 : TX write while full discarded + STATUS.TX_OVF + INT_STAT[TX_OVF]
//   R14 : RX transfer while full discards word + STATUS.RX_OVF + INT_STAT[RX_OVF]
//   R15 : RX read while empty returns 0, no RX_OVF
//   R23 : Reserved offsets read 0, writes ignored
//   R25 : Illegal WIDTH encoding (2'b11) handled gracefully
//
// Spec bit positions (Section 3.2 STATUS):
//   bit 6 = RX_OVF, bit 5 = TX_OVF, bit 4 = RX_EMPTY, bit 3 = RX_FULL,
//   bit 2 = TX_EMPTY, bit 1 = TX_FULL, bit 0 = BUSY
//
// Spec bit positions (Section 3.7 INT_STAT):
//   bit 4 = TRANSFER_DONE, bit 3 = RX_OVF, bit 2 = TX_OVF,
//   bit 1 = RX_FULL, bit 0 = TX_EMPTY
// =============================================================================

`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV 

class error_injection_test;

  // APB helpers
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

  // Composite helpers 
  static task automatic clear_int_stat(ref spi_coverage_col coverage);
    apb_wr(coverage, APB_INT_STAT, W1C_ALL);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));
  endtask

  static task automatic ss_assert(ref spi_coverage_col coverage);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);
  endtask

  static task automatic ss_deassert(ref spi_coverage_col coverage);
    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);
  endtask

  static task automatic irq_idle(ref spi_coverage_col coverage);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));
  endtask

  // Wait for BUSY=0 and TX_EMPTY=1 with timeout, returns fail flag
  static task automatic wait_idle(ref spi_coverage_col coverage, ref bit [31:0] status,
                                  input int max_wait = 10000, output bit timeout);
    int wc = 0;
    timeout = 1'b0;
    apb_rd(coverage, APB_STATUS, status);
    while ((status[0] || !status[2]) && wc < max_wait) begin
      apb_rd(coverage, APB_STATUS, status);
      wc++;
    end
    if (status[0] || !status[2]) timeout = 1'b1;
  endtask

  // ---------------------------------------------------------------------------
  // TC-R15: RX_DATA read while empty returns 0, no RX_OVF
  // ---------------------------------------------------------------------------
  static task automatic tc_r15(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    bit [31:0] rd, status, int_stat;

    apb_rd(coverage, APB_RX_DATA, rd);
    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_rx_empty_read_zero(rd, status);
    coverage.sample_overflow(.tx_ovf(1'b0), .rx_ovf(1'b0), .rx_empty_rd(1'b1));

    apb_rd(coverage, APB_INT_STAT, int_stat);
    irq_idle(coverage);
    ref_model.check_int_stat_bit(int_stat, 3, 1'b0, "R15: RX_OVF set after empty read");
  endtask

  // ---------------------------------------------------------------------------
  // TC-R13: TX overflow — 9th write discarded, STATUS.TX_OVF + INT_STAT[TX_OVF]
  // ---------------------------------------------------------------------------
  static task automatic tc_r13(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    bit [31:0] status, int_stat;
    int i;

    clear_int_stat(coverage);
    ss_deassert(coverage);

    for (i = 0; i < 8; i++) apb_wr(coverage, APB_TX_DATA, 32'h0000_00AA);
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00BB);  // 9th → overflow
    coverage.sample_overflow(.tx_ovf(1'b1), .rx_ovf(1'b0), .rx_empty_rd(1'b0));

    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_reg_masked("STATUS_TX_OVF", MASK_TX_OVF, status, MASK_TX_OVF);

    apb_rd(coverage, APB_INT_STAT, int_stat);
    irq_idle(coverage);
    ref_model.check_int_stat_bit(int_stat, 2, 1'b1, "R13: TX_OVF not set");

    ss_assert(coverage);
    ref_model.wait_and_drain();
    clear_int_stat(coverage);
  endtask

  // ---------------------------------------------------------------------------
  // TC-R14: RX overflow — 9th received word discarded
  // ---------------------------------------------------------------------------
  static task automatic tc_r14(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    bit [31:0] status, int_stat;
    bit timeout;
    int i;

    clear_int_stat(coverage);
    ss_assert(coverage);

    for (i = 0; i < 9; i++) apb_wr(coverage, APB_TX_DATA, 32'h0000_0011 + i);

    wait_idle(coverage, status, 10000, timeout);
    if (timeout) ref_model.checker_error("R14", "timeout waiting for 9 transfers");

    @(posedge tb_top.PCLK);
    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_rx_status(status, .expect_full(1'b1), .expect_empty(1'b0));
    ref_model.check_reg_masked("STATUS_RX_OVF", MASK_RX_OVF, status, MASK_RX_OVF);
    coverage.sample_overflow(.tx_ovf(1'b0), .rx_ovf(1'b1), .rx_empty_rd(1'b0));

    apb_rd(coverage, APB_INT_STAT, int_stat);
    irq_idle(coverage);
    ref_model.check_int_stat_bit(int_stat, 3, 1'b1, "R14: RX_OVF not set");

    // Drain 8 valid words (values from slave BFM, not checked here)
    for (i = 0; i < 8; i++) begin
      bit [31:0] rd;
      apb_rd(coverage, APB_RX_DATA, rd);
      if (rd === 32'h0) begin
        ref_model.checker_error("R14", $sformatf("RX word %0d is 0 (expected valid)", i));
      end
    end

    clear_int_stat(coverage);
    ss_deassert(coverage);
  endtask

  // ---------------------------------------------------------------------------
  // TC-R3: EN=0 holds shifter/FIFOs in reset; SCLK idle; SS_n forced high
  // ---------------------------------------------------------------------------
  static task automatic tc_r3(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    bit [31:0] status, rd;
    bit timeout;

    ss_assert(coverage);
    apb_wr(coverage, APB_TX_DATA, 32'h0000_0044);
    apb_wr(coverage, APB_TX_DATA, 32'h0000_0055);

    wait_idle(coverage, status, 5000, timeout);
    for (int i = 0; i < 2; i++) apb_rd(coverage, APB_RX_DATA, rd);

    ss_deassert(coverage);

    // Write EN=0
    apb_wr(coverage, APB_CTRL, 32'h0000_0002);
    coverage.sample_ctrl_en(.en(1'b0), .sclk(tb_top.spi.sclk), .mode(2'b00), .ss_n(tb_top.spi.ss_n),
                            .ss_en(4'b0001), .tx_occ(0), .rx_occ(0));

    repeat (4) @(posedge tb_top.PCLK);

    apb_rd(coverage, APB_STATUS, status);
    ref_model.check_tx_status(status, .expect_full(1'b0), .expect_empty(1'b1), .expect_busy(1'b0));
    // R3: FIFOs must be flushed
    ref_model.check_rx_status(status, .expect_full(1'b0), .expect_empty(1'b1));

    // R3: SCLK at CPOL=0 idle (low)
    if (tb_top.spi.sclk !== 1'b0) begin
      ref_model.checker_error("R3", $sformatf("SCLK not idle when EN=0, SCLK=%b", tb_top.spi.sclk));
    end

    // R3: SS_n forced high regardless of SS_CTRL
    if (tb_top.spi.ss_n !== 4'hF) begin
      ref_model.checker_error("R3", $sformatf(
                              "SS_n not forced high when EN=0, SS_n=0x%0h", tb_top.spi.ss_n));
    end

    // Re-enable
    apb_wr(coverage, APB_CTRL, 32'h0000_0003);
    coverage.sample_ctrl_en(.en(1'b1), .sclk(tb_top.spi.sclk), .mode(2'b00), .ss_n(tb_top.spi.ss_n),
                            .ss_en(4'b0000), .tx_occ(0), .rx_occ(0));
    ss_assert(coverage);
  endtask

  // ---------------------------------------------------------------------------
  // TC-R23: Reserved offsets read 0, writes ignored
  // ---------------------------------------------------------------------------
  static task automatic tc_r23(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    bit [31:0] reserved_rd;
    bit [ 7:0] reserved_addrs[3] = '{8'h24, 8'h28, 8'h2C};

    foreach (reserved_addrs[j]) begin
      apb_rd(coverage, reserved_addrs[j], reserved_rd);
      ref_model.check_reserved_read_zero(reserved_addrs[j], reserved_rd);
    end

    apb_wr(coverage, 8'h24, 32'hDEAD_BEEF);
    coverage.sample_reserved(8'h24, 1'b1);
    apb_rd(coverage, 8'h24, reserved_rd);
    coverage.sample_reserved(8'h24, 1'b0);
    ref_model.check_reserved_read_zero(8'h24, reserved_rd);
  endtask

  // ---------------------------------------------------------------------------
  // TC-R25: Illegal WIDTH encoding (2'b11) — DUT must not lock up
  // This test verifies: (1) DUT doesn't crash, (2) transfer completes, (3) no X-propagation, (4) can return to valid width afterward.
  // ---------------------------------------------------------------------------
  static task automatic tc_r25(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    bit [31:0] status;
    bit        timeout;
    int        wc;

    // Save current config
    apb_wr(coverage, APB_CTRL, 32'h0000_00C3);  // WIDTH=2'b11, EN=1, MSTR=1
    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b11), .loopback(1'b0));

    // Push data — DUT may start a transfer with some width
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00AA);

    // Wait for transfer to complete (BUSY=0) or timeout
    // This proves the DUT didn't lock up
    wc = 0;
    timeout = 1'b0;
    apb_rd(coverage, APB_STATUS, status);
    while (status[0] && wc < 10000) begin
      apb_rd(coverage, APB_STATUS, status);
      wc++;
    end
    if (status[0]) begin
      timeout = 1'b1;
      ref_model.checker_error("R25", "DUT locked up with illegal WIDTH=2'b11 (BUSY stuck)");
    end

    // If transfer completed, verify no X in status (sanity check)
    if (!timeout && (^status) === 1'bx) begin
      ref_model.checker_error("R25", "X propagation in STATUS with illegal WIDTH");
    end

    // Return to valid 8-bit width
    apb_wr(coverage, APB_CTRL, 32'h0000_0003);
    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00), .loopback(1'b0));

    // Verify DUT is usable after illegal width excursion
    apb_wr(coverage, APB_TX_DATA, 32'h0000_00BB);
    wc = 0;
    apb_rd(coverage, APB_STATUS, status);
    while ((status[0] || !status[2]) && wc < 10000) begin
      apb_rd(coverage, APB_STATUS, status);
      wc++;
    end
    if (status[0] || !status[2]) begin
      ref_model.checker_error("R25", "DUT not recoverable after illegal WIDTH");
    end

    // Drain the valid transfer
    ref_model.wait_and_drain(.max_wait(2000), .rx_words(1));
  endtask
  // ---------------------------------------------------------------------------
  // TC-TX_RD: TX_DATA read returns 0 (write-only register)
  // ---------------------------------------------------------------------------
  static task automatic tc_tx_rd(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    bit [31:0] rd;

    apb_wr(coverage, APB_TX_DATA, 32'h0000_00A5);
    apb_rd(coverage, APB_TX_DATA, rd);
    ref_model.check_tx_data_read_zero(rd);

    ss_assert(coverage);
    ref_model.wait_and_drain(.max_wait(2000), .rx_words(1));
    ss_deassert(coverage);
  endtask

  // =============================================================================
  // Main entry point
  // =============================================================================
  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    // Setup 
    ref_model.apply_reset(.min_cycles(2));

    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0004);
    coverage.sample_clk_div(16'h0004);

    apb_wr(coverage, APB_CTRL, 32'h0000_0003);  // EN=1, MSTR=1, MODE=0, WIDTH=8
    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00), .loopback(1'b0));

    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    irq_idle(coverage);
    clear_int_stat(coverage);
    ss_deassert(coverage);

    // Execute all test cases 
    tc_r15(ref_model, coverage);  // RX empty read
    tc_r13(ref_model, coverage);  // TX overflow
    tc_r14(ref_model, coverage);  // RX overflow
    tc_r3(ref_model, coverage);  // EN=0 behavior
    tc_r23(ref_model, coverage);  // Reserved offsets
    tc_r25(ref_model, coverage);  // Illegal width
    tc_tx_rd(ref_model, coverage);  // TX_DATA read-zero

    // Cleanup 
    ss_deassert(coverage);
    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    irq_idle(coverage);
    clear_int_stat(coverage);

  endtask
endclass

`endif\
