// =============================================================================
// error_injection_test.sv - CORRECTED BIT POSITIONS
// =============================================================================
`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV 

class error_injection_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    bit [31:0] rd, status, int_stat;
    integer errors = 0, i, wait_count;

    $display("[INFO] error_injection_test: starting");
    ref_model.apply_reset(.min_cycles(2));
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'h0000_0004);
    tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0003);
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    tb_top.bfm_mode = 2'b00;
    tb_top.bfm_lsb_first = 1'b0;
    tb_top.bfm_width = 2'b00;
    tb_top.bfm_pattern = 8'hA5;
    tb_top.bfm_miso_word = 32'hA5A5_A5A5;

    // =========================================================================
    // TC-1.1: RX empty read returns 0, no error bit (R15)
    // =========================================================================
    $display("[INFO] TC-1.1: RX empty read");
    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    if (rd !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] TC-1.1: RX empty read != 0");
      errors++;
      ref_model.error_count++;
    end
    $display("[INFO] TC-1.1: done");

    // =========================================================================
    // TC-1.2: TX FIFO depth=8, TX_FULL on 8th write (R9, R11)
    // Spec: TX_FULL = STATUS[1]
    // =========================================================================
    $display("[INFO] TC-1.2: TX FIFO depth");

    // 🔑 FIX 1: Deassert SS before filling FIFO to prevent immediate transmission
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

    // Verify TX_EMPTY initially (STATUS bit 2)
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    if (status[2] !== 1'b1) begin  // TX_EMPTY = bit 2
      $display("[SCOREBOARD_ERROR] TC-1.2: TX_EMPTY not set after reset");
      errors++;
      ref_model.error_count++;
    end

    // Write 8 words — all should be accepted, FIFO should fill to capacity
    for (i = 0; i < 8; i++) begin
      tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0055 + i);
    end

    // 🔑 FIX 2: Check TX_FULL NOW, before asserting SS
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    $display("[DEBUG] TC-1.2: STATUS after 8 writes (SS deasserted): 0x%08h", status);

    // TX_FULL is bit 1 per spec Section 3.2
    if (status[1] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-1.2: TX_FULL not set after 8 writes (checked bit 1)");
      errors++;
      ref_model.error_count++;
    end

    // 🔑 FIX 3: Now assert SS to start transmission
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    // Wait for all 8 transfers to complete (BUSY=0 and TX_EMPTY=1)
    wait_count = 0;
    repeat (5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      if (status[0] == 1'b0 && status[2] == 1'b1) break;  // !BUSY && TX_EMPTY
      wait_count++;
    end
    if (wait_count == 5000) begin
      $display("[SCOREBOARD_ERROR] TC-1.2: timeout waiting for FIFO drain");
      errors++;
      ref_model.error_count++;
    end

    // Drain RX FIFO from those 8 transfers
    for (i = 0; i < 8; i++) begin
      tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    end
    $display("[INFO] TC-1.2: done");

    // =========================================================================
    // TC-1.3: TX overflow - 9th write discarded, TX_OVF set (R9, R11, R13)
    // CORRECTED: TX_OVF = STATUS[1] and INT_STAT[0], not [5] and [2]
    // =========================================================================
    $display("[INFO] TC-1.3: TX overflow");
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);  // Clear all

    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00AA);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00BB);  // 9th word

    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    $display("[DEBUG] TC-1.3: STATUS after overflow: 0x%08h", status);

    // 🔑 FIX: TX_OVF in STATUS is bit 1, not bit 5
    if (status[1] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-1.3: STATUS[1] (TX_OVF) not set");
      errors++;
      ref_model.error_count++;
    end

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    $display("[DEBUG] TC-1.3: INT_STAT after overflow: 0x%08h", int_stat);

    // 🔑 FIX: TX_OVF in INT_STAT is bit 0, not bit 2
    if (int_stat[0] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-1.3: INT_STAT[0] (TX_OVF) not set");
      errors++;
      ref_model.error_count++;
    end

    // Drain
    wait_count = 0;
    while ((status[0] || !status[2]) && wait_count < 5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    $display("[INFO] TC-1.3: done");

    // =========================================================================
    // TC-2.1: INT_STAT W1C - TX_OVF sticky + clear (R13, R17)
    // CORRECTED: INT_STAT[0] = TX_OVF
    // =========================================================================
    $display("[INFO] TC-2.1: INT_STAT W1C");
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00CC);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00DD);  // overflow

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[0] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-2.1: INT_STAT[0] not set before clear");
      errors++;
      ref_model.error_count++;
      return;
    end

    // Sticky check
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[0] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-2.1: INT_STAT[0] not sticky");
      errors++;
      ref_model.error_count++;
    end

    // Write 0 - should have no effect
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[0] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-2.1: INT_STAT[0] cleared by write-0");
      errors++;
      ref_model.error_count++;
    end

    // Write 1 to bit 0 - should clear
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0001);  // bit 0 = TX_OVF
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[0] !== 1'b0) begin
      $display("[SCOREBOARD_ERROR] TC-2.1: INT_STAT[0] not cleared by W1C");
      errors++;
      ref_model.error_count++;
    end

    // Drain
    wait_count = 0;
    while ((status[0] || !status[2]) && wait_count < 5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    $display("[INFO] TC-2.1: done");

    // =========================================================================
    // TC-2.2: RX overflow - 9th received word discarded (R12, R14)
    // Spec Section 3.7: RX_OVF = INT_STAT[3], STATUS[6]
    // =========================================================================
    $display("[INFO] TC-2.2: RX overflow");

    // Clear all INT_STAT bits first (W1C: write 1 to clear)
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    // Ensure SS is asserted for transfers
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    // Send 9 words — RX FIFO is 8-deep, so 9th should trigger overflow
    for (i = 0; i < 9; i++) begin
      tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0011 + i);
    end

    // Wait for all transfers to complete (BUSY=0 and TX_EMPTY=1)
    wait_count = 0;
    repeat (10000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      if (status[0] == 1'b0 && status[2] == 1'b1) break;  // !BUSY && TX_EMPTY
      wait_count++;
    end
    if (wait_count == 10000) begin
      $display("[SCOREBOARD_ERROR] TC-2.2: timeout waiting for transfers");
      errors++;
      ref_model.error_count++;
    end

    // 🔑 FIX: Add sync cycle for INT_STAT to update (spec: "Asserted one PCLK cycle after")
    @(posedge tb_top.PCLK);

    // Check STATUS.RX_OVF (bit 6 per spec Section 3.2)
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    $display("[DEBUG] TC-2.2: STATUS after 9 transfers: 0x%08h (RX_OVF=%0b)", status, status[6]);
    if (status[6] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-2.2: STATUS[6] (RX_OVF) not set");
      errors++;
      ref_model.error_count++;
    end

    // 🔑 FIX: Check INT_STAT[3] for RX_OVF (per spec Section 3.7)
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    $display("[DEBUG] TC-2.2: INT_STAT after overflow: 0x%08h (RX_OVF bit 3=%0b)", int_stat,
             int_stat[3]);

    if (int_stat[3] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-2.2: INT_STAT[3] (RX_OVF) not set");
      errors++;
      ref_model.error_count++;
    end

    // Drain RX FIFO AFTER checking error bits (best practice)
    for (i = 0; i < 8; i++) begin
      tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    end

    // Clear RX_OVF via INT_STAT W1C: write 1 to bit 3
    // Bit 3 = 2^3 = 8 = 32'h0000_0008
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0008);  // bit 3 = RX_OVF
    @(posedge tb_top.PCLK);  // Sync for clear to take effect

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    $display("[DEBUG] TC-2.2: INT_STAT after clear: 0x%08h (RX_OVF bit 3=%0b)", int_stat,
             int_stat[3]);

    $display("[INFO] TC-2.2: done");

    // =========================================================================
    // TC-3.1: IRQ masked when INT_EN=0 (R16)
    // CORRECTED: INT_STAT[0] = TX_OVF
    // =========================================================================
    $display("[INFO] TC-3.1: IRQ masked");
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0022);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00FF);  // overflow

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    // 🔑 FIX: Check INT_STAT[0] for TX_OVF
    if (int_stat[0] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-3.1: INT_STAT[0] not set despite INT_EN=0");
      errors++;
      ref_model.error_count++;
    end

    // IRQ must be 0 because INT_EN=0
    begin
      bit irq_val = tb_top.u_wrap.u_dut.u_regfile.IRQ;
      if (irq_val !== 1'b0) begin
        $display("[SCOREBOARD_ERROR] TC-3.1: IRQ=1 when INT_EN=0");
        errors++;
        ref_model.error_count++;
      end
    end

    // Drain and clear
    wait_count = 0;
    while ((status[0] || !status[2]) && wait_count < 5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
    $display("[INFO] TC-3.1: done");

    // =========================================================================
    // TC-3.2: IRQ asserts when INT_EN enables the interrupt (R16)
    // Spec Section 3.7: TX_OVF = INT_STAT[2], INT_EN[2] enables it
    // =========================================================================
    $display("[INFO] TC-3.2: IRQ asserts");

    // 🔑 FIX 1: Clear INT_STAT first to start clean
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    // 🔑 FIX 2: Enable TX_OVF interrupt via INT_EN[2] (not [0]!)
    // Bit 2 = 2^2 = 4 = 32'h0000_0004
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0004);

    // 🔑 FIX 3: Ensure SS is asserted for overflow detection
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    // Trigger TX overflow: fill FIFO + 9th write
    for (i = 0; i < 8; i++) begin
      tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0033);
    end
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00EE);  // 9th word → overflow

    // 🔑 FIX 4: Sync delays for INT_STAT and IRQ to update
    // Spec: "Asserted one PCLK cycle after each completed word"
    repeat (2) @(posedge tb_top.PCLK);

    // 🔑 FIX 5: Verify INT_STAT[2] (TX_OVF) is set BEFORE checking IRQ
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    $display("[DEBUG] TC-3.2: INT_STAT after overflow: 0x%08h (TX_OVF bit 2=%0b)", int_stat,
             int_stat[2]);

    if (int_stat[2] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-3.2: INT_STAT[2] (TX_OVF) not set");
      errors++;
      ref_model.error_count++;
    end

    // Now check IRQ: should be 1 because INT_STAT[2]=1 AND INT_EN[2]=1
    begin
      bit irq_val = tb_top.u_wrap.u_dut.u_regfile.IRQ;
      $display("[DEBUG] TC-3.2: IRQ=%0b (expected 1)", irq_val);
      if (irq_val !== 1'b1) begin
        $display("[SCOREBOARD_ERROR] TC-3.2: IRQ=0 when INT_EN[2]=1 and TX_OVF set");
        errors++;
        ref_model.error_count++;
      end
    end

    // 🔑 FIX 6: Drain and cleanup
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
    @(posedge tb_top.PCLK);

    // Wait for transfers to complete
    wait_count = 0;
    repeat (5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      if (status[0] == 1'b0 && status[2] == 1'b1) break;  // !BUSY && TX_EMPTY
      wait_count++;
    end

    // Drain RX FIFO
    for (i = 0; i < 8; i++) begin
      tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    end

    // Clear INT_STAT
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    $display("[INFO] TC-3.2: done");
    // =========================================================================
    // TC-4.1: Reserved reads return 0 (R23)
    // =========================================================================
    $display("[INFO] TC-4.1: Reserved reads");
    begin
      bit [31:0] reserved_rd;
      tb_top.u_apb_bfm.apb_read(8'h24, reserved_rd);
      if (reserved_rd !== 32'h0) begin
        errors++;
        ref_model.error_count++;
      end
      tb_top.u_apb_bfm.apb_read(8'h28, reserved_rd);
      if (reserved_rd !== 32'h0) begin
        errors++;
        ref_model.error_count++;
      end
      tb_top.u_apb_bfm.apb_read(8'h2C, reserved_rd);
      if (reserved_rd !== 32'h0) begin
        errors++;
        ref_model.error_count++;
      end
    end
    $display("[INFO] TC-4.1: done");

    // =========================================================================
    // TC-4.2: TX_DATA read returns 0 (write-only)
    // =========================================================================
    $display("[INFO] TC-4.2: TX_DATA read");
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00A5);
    tb_top.u_apb_bfm.apb_read(APB_TX_DATA, rd);
    if (rd !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] TC-4.2: TX_DATA read != 0");
      errors++;
      ref_model.error_count++;
    end
    // Drain
    wait_count = 0;
    while ((status[0] || !status[2]) && wait_count < 2000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    $display("[INFO] TC-4.2: done");

    // =========================================================================
    // CLEANUP
    // =========================================================================
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    $display("[INFO] error_injection_test: finished, errors=%0d", errors);
  endtask
endclass
`endif
