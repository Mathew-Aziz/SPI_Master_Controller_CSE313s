// Requirements covered:
//   R3 : EN=0 holds shifter/FIFOs; SCLK idle; SS forced high
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

class error_injection_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] rd, status, int_stat;
    integer errors = 0, i, wait_count;
    bit skip_rest;

    // SETUP
    ref_model.apply_reset(.min_cycles(2));
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'h0000_0004);
    tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0003);
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    tb_top.bfm_mode      = 2'b00;
    tb_top.bfm_lsb_first = 1'b0;
    tb_top.bfm_width     = 2'b00;
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_miso_word = 32'hA5A5_A5A5;

    // TC-1: R15 — RX_DATA read while empty returns 0, no RX_OVF
    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    if (rd !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] TC-1: RX empty read nonzero: observed=0x%08h", rd);
      errors++;
      ref_model.error_count++;
    end

    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    if (status[6] !== 1'b0) begin
      $display("[SCOREBOARD_ERROR] TC-1: STATUS[6] (RX_OVF) set after empty read, STATUS=0x%08h",
               status);
      errors++;
      ref_model.error_count++;
    end

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[3] !== 1'b0) begin
      $display(
          "[SCOREBOARD_ERROR] TC-1: INT_STAT[3] (RX_OVF) set after empty read, INT_STAT=0x%08h",
          int_stat);
      errors++;
      ref_model.error_count++;
    end

    // TC-2: R11 — TX FIFO depth=8; TX_FULL asserts on 8th write
    // STATUS[1]=TX_FULL, STATUS[2]=TX_EMPTY, STATUS[5]=TX_OVF
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);  // Deassert SS

    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    if (status[2] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-2: STATUS[2] (TX_EMPTY) not set after reset, STATUS=0x%08h",
               status);
      errors++;
      ref_model.error_count++;
    end

    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0055 + i);

    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);

    if (status[1] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-2: STATUS[1] (TX_FULL) not set after 8 writes, STATUS=0x%08h",
               status);
      errors++;
      ref_model.error_count++;
    end
    if (status[5] !== 1'b0) begin
      $display("[SCOREBOARD_ERROR] TC-2: STATUS[5] (TX_OVF) set prematurely, STATUS=0x%08h",
               status);
      errors++;
      ref_model.error_count++;
    end

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);
    wait_count = 0;
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    while ((status[0] || !status[2]) && wait_count < 5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    if (status[0] || !status[2]) begin
      $display("[SCOREBOARD_ERROR] TC-2: timeout waiting for FIFO drain");
      errors++;
      ref_model.error_count++;
    end
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);

    // TC-3: R13 — TX overflow: 9th write discarded
    // STATUS[5]=TX_OVF, INT_STAT[2]=TX_OVF
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00AA);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00BB);  // 9th

    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    if (status[5] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-3: STATUS[5] (TX_OVF) not set, STATUS=0x%08h", status);
      errors++;
      ref_model.error_count++;
    end

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[2] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-3: INT_STAT[2] (TX_OVF) not set, INT_STAT=0x%08h", int_stat);
      errors++;
      ref_model.error_count++;
    end

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);
    wait_count = 0;
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    while ((status[0] || !status[2]) && wait_count < 5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    // TC-4: R17 — INT_STAT W1C: sticky, write-0 no effect, write-1 clears
    skip_rest = 0;
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00CC);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00DD);  // overflow

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[2] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-4: INT_STAT[2] not set before clear test, INT_STAT=0x%08h",
               int_stat);
      errors++;
      ref_model.error_count++;
      skip_rest = 1;
    end

    if (!skip_rest) begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
      if (int_stat[2] !== 1'b1) begin
        $display("[SCOREBOARD_ERROR] TC-4: INT_STAT[2] not sticky, INT_STAT=0x%08h", int_stat);
        errors++;
        ref_model.error_count++;
      end

      tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0000);
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
      if (int_stat[2] !== 1'b1) begin
        $display("[SCOREBOARD_ERROR] TC-4: INT_STAT[2] cleared by write-0, INT_STAT=0x%08h",
                 int_stat);
        errors++;
        ref_model.error_count++;
      end

      tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0004);
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
      if (int_stat[2] !== 1'b0) begin
        $display("[SCOREBOARD_ERROR] TC-4: INT_STAT[2] not cleared by W1C, INT_STAT=0x%08h",
                 int_stat);
        errors++;
        ref_model.error_count++;
      end
    end

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);
    wait_count = 0;
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    while ((status[0] || !status[2]) && wait_count < 5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    // TC-5: R14 — RX overflow: 9th received word discarded
    // STATUS[6]=RX_OVF, STATUS[3]=RX_FULL, INT_STAT[3]=RX_OVF
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    for (i = 0; i < 9; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0011 + i);

    wait_count = 0;
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    while ((status[0] || !status[2]) && wait_count < 10000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    if (status[0] || !status[2]) begin
      $display("[SCOREBOARD_ERROR] TC-5: timeout waiting for 9 transfers");
      errors++;
      ref_model.error_count++;
    end

    @(posedge tb_top.PCLK);

    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    if (status[6] !== 1'b1) begin
      $display(
          "[SCOREBOARD_ERROR] TC-5: STATUS[6] (RX_OVF) not set after 9 transfers, STATUS=0x%08h",
          status);
      errors++;
      ref_model.error_count++;
    end
    if (status[3] !== 1'b1) begin
      $display(
          "[SCOREBOARD_ERROR] TC-5: STATUS[3] (RX_FULL) not set after 9 transfers, STATUS=0x%08h",
          status);
      errors++;
      ref_model.error_count++;
    end

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[3] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-5: INT_STAT[3] (RX_OVF) not set, INT_STAT=0x%08h", int_stat);
      errors++;
      ref_model.error_count++;
    end

    for (i = 0; i < 8; i++) begin
      tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
      if (rd === 32'h0) begin
        $display("[SCOREBOARD_ERROR] TC-5: RX word %0d is 0 (expected valid data)", i);
        errors++;
        ref_model.error_count++;
      end
    end

    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    if (rd !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] TC-5: 9th RX read nonzero (should be discarded), rd=0x%08h", rd);
      errors++;
      ref_model.error_count++;
    end

    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0008);
    @(posedge tb_top.PCLK);
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[3] !== 1'b0) begin
      $display("[SCOREBOARD_ERROR] TC-5: INT_STAT[3] not cleared by W1C, INT_STAT=0x%08h",
               int_stat);
      errors++;
      ref_model.error_count++;
    end

    // TC-6: R16 — IRQ masked when INT_EN=0; INT_STAT still captures
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0022);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00FF);

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[2] !== 1'b1) begin
      $display(
          "[SCOREBOARD_ERROR] TC-6: INT_STAT[2] not set with INT_EN=0 (R16 violation), INT_STAT=0x%08h",
          int_stat);
      errors++;
      ref_model.error_count++;
    end

    begin
      bit irq_val;
      irq_val = tb_top.u_wrap.u_dut.u_regfile.IRQ;
      if (irq_val !== 1'b0) begin
        $display("[SCOREBOARD_ERROR] TC-6: IRQ=1 when INT_EN=0 (expected 0)");
        errors++;
        ref_model.error_count++;
      end
    end

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);
    wait_count = 0;
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    while ((status[0] || !status[2]) && wait_count < 5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    // TC-7: R16 — IRQ asserts when INT_EN enables triggered interrupt
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0004);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0033);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00EE);

    repeat (2) @(posedge tb_top.PCLK);

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat);
    if (int_stat[2] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] TC-7: INT_STAT[2] (TX_OVF) not set, INT_STAT=0x%08h", int_stat);
      errors++;
      ref_model.error_count++;
    end

    begin
      bit irq_val;
      irq_val = tb_top.u_wrap.u_dut.u_regfile.IRQ;
      if (irq_val !== 1'b1) begin
        $display("[SCOREBOARD_ERROR] TC-7: IRQ=0 when INT_EN[2]=1 and INT_STAT[2]=1");
        errors++;
        ref_model.error_count++;
      end
    end

    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
    @(posedge tb_top.PCLK);
    begin
      bit irq_val;
      irq_val = tb_top.u_wrap.u_dut.u_regfile.IRQ;
      if (irq_val !== 1'b0) begin
        $display("[SCOREBOARD_ERROR] TC-7: IRQ did not deassert after INT_EN cleared");
        errors++;
        ref_model.error_count++;
      end
    end

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);
    wait_count = 0;
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    while ((status[0] || !status[2]) && wait_count < 5000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    for (i = 0; i < 8; i++) tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

    // TC-8: R3 — EN=0 flushes FIFOs, resets shifter, forces SS_n high
    // Spec Section 9, R3: "CTRL.EN=0 holds the shifter and FIFOs in reset; 
    // SCLK stays at CPOL idle; SS_n forced high regardless of SS_CTRL"
    // Spec Section 6.1: "CTRL.EN 1->0: Flushes TX/RX FIFOs and resets shifter"
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0044);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_0055);

    tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0002);
    repeat (4) @(posedge tb_top.PCLK);
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    if (status[0] !== 1'b0) begin
      $display("[SCOREBOARD_ERROR] TC-8: STATUS[0] (BUSY) not 0 after EN=0, STATUS=0x%08h", status);
      errors++;
      ref_model.error_count++;
    end
    if (status[2] !== 1'b1) begin
      $display(
          "[SCOREBOARD_ERROR] TC-8: STATUS[2] (TX_EMPTY) not set after EN=0 flush, STATUS=0x%08h",
          status);
      errors++;
      ref_model.error_count++;
    end

    begin
      logic [3:0] ss_n_val;
      ss_n_val = tb_top.spi.ss_n;
      if (ss_n_val !== 4'hF) begin
        $display(
            "[SCOREBOARD_ERROR] TC-8: SS_n not forced high when EN=0, SS_n=0x%0h (R3 violation)",
            ss_n_val);
        errors++;
        ref_model.error_count++;
      end
    end

    tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0003);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    // TC-9: R23 — Reserved offsets read 0, writes ignored
    begin
      bit [31:0] reserved_rd;

      tb_top.u_apb_bfm.apb_read(8'h24, reserved_rd);
      if (reserved_rd !== 32'h0) begin
        $display("[SCOREBOARD_ERROR] TC-9: addr=0x24 expected=0 observed=0x%08h", reserved_rd);
        errors++;
        ref_model.error_count++;
      end

      tb_top.u_apb_bfm.apb_read(8'h28, reserved_rd);
      if (reserved_rd !== 32'h0) begin
        $display("[SCOREBOARD_ERROR] TC-9: addr=0x28 expected=0 observed=0x%08h", reserved_rd);
        errors++;
        ref_model.error_count++;
      end

      tb_top.u_apb_bfm.apb_read(8'h2C, reserved_rd);
      if (reserved_rd !== 32'h0) begin
        $display("[SCOREBOARD_ERROR] TC-9: addr=0x2C expected=0 observed=0x%08h", reserved_rd);
        errors++;
        ref_model.error_count++;
      end

      tb_top.u_apb_bfm.apb_write(8'h24, 32'hDEAD_BEEF);
      tb_top.u_apb_bfm.apb_read(8'h24, reserved_rd);
      if (reserved_rd !== 32'h0) begin
        $display("[SCOREBOARD_ERROR] TC-9: addr=0x24 nonzero after write, observed=0x%08h",
                 reserved_rd);
        errors++;
        ref_model.error_count++;
      end
    end

    // TC-10: TX_DATA read returns 0 (write-only)
    // Spec Section 3.3: "Reads return 0 and do not pop the FIFO"
    // =========================================================================
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00A5);
    tb_top.u_apb_bfm.apb_read(APB_TX_DATA, rd);
    if (rd !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] TC-10: TX_DATA read nonzero: observed=0x%08h", rd);
      errors++;
      ref_model.error_count++;
    end

    wait_count = 0;
    tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
    while ((status[0] || !status[2]) && wait_count < 2000) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, status);
      wait_count++;
    end
    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);

    // CLEANUP
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

  endtask
endclass

`endif
