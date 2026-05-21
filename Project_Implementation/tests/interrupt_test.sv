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

    // ------------------------- W1C race checker (for test compatibility) --------------------------
    static task automatic check_race(ref spi_coverage_col coverage,
                                    ref spi_ref_model ref_model,
                                    input string name, input int bit_idx);
    bit [31:0] rd;
    apb_rd(coverage, APB_INT_STAT, rd);
    if (rd[bit_idx] !== 1'b1) begin
      $display("[SCOREBOARD_ERROR] R18 FAILED [%s]: INT_STAT[%0d] was cleared by W1C (expected to stay 1)",
               name, bit_idx);
      ref_model.error_count++;
    end else begin
      $display("[INFO SUCESS!!] R18 PASSED [%s]: INT_STAT[%0d] held 1 through simultaneous W1C", name, bit_idx);
    end
    
  endtask

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] rd = 0;
    bit [31:0] val = 0;
    bit [31:0] RX_q[$];
    $display("[INFO] interrupt_test: starting");


    tb_top.bfm_mode      = 2'b00;  // CPOL=0 CPHA=0
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_width     = 2'b00;  // 8-bit
    tb_top.bfm_lsb_first = 1'b0;  // MSB-first
    tb_top.bfm_miso_word = 32'h0000_00A5;  // matches bfm_pattern

    apb_wr(coverage, APB_CTRL, 32'h0000_0003);  // EN, MSTR
    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0004);  // divide /4
    coverage.sample_clk_div(16'h0004);

    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00), .loopback(1'b0));

    // TODO:
    // For each interrupt source:
    // - cause event
    // - confirm INT_STAT sticky
    // - confirm mask gates IRQ only (R16)
    // - clear via W1C (R17)
    // - W1C race (R18)

    //*======================TRANSFER_DONE IRQ test=========================

    // $display("[INTERRUPT_TEST] Starting TRANSFER_DONE IRQ test");
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0010);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b10000), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // val  = $urandom() & 8'hFF;
    // apb_wr(coverage, APB_TX_DATA, val);
    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    // coverage.sample_ss(4'b0001, 4'b0000);

    // repeat (5000) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    // end
    // coverage.sample_busy(1'b0, 2'b00);

    // if (tb_top.spi.cb_mon.irq != 1'b1)
    //   ref_model.checker_error("Interrupt test",
    //                           "TRANSFER_DONE IRQ not asserted after transfer completion");

    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT_TRANSFER_DONE", 8'b0001_0000, rd, 8'b0001_0000);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b10000), .w1c_mask(5'b0),
    //                       .w1c_race_mask(5'b0));
    // end

    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b10000), .w1c_mask(5'b10000),
    //                     .w1c_race_mask(5'b0));
    // apb_rd(coverage, APB_INT_STAT, rd);
    // if(rd[4] == 1'b1)
    //   ref_model.checker_error("Interrupt test", "TRANSFER_DONE INT_STAT bit not cleared after W1C");
    // if (tb_top.spi.cb_mon.irq == 1'b1)
    //   ref_model.checker_error("Interrupt test", "TRANSFER_DONE IRQ asserted after W1C clear");

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // apb_wr(coverage, APB_TX_DATA, val);
    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    // coverage.sample_ss(4'b0001, 4'b0000);

    // repeat (5000) begin
    //     apb_rd(coverage, APB_STATUS, rd);
    //     if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    // end

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);  // deassert SS_n[0] HIGH
    // coverage.sample_ss(4'b0000, 4'b0000);


    // if (tb_top.spi.cb_mon.irq == 1'b1)
    //   ref_model.checker_error("Interrupt test", "TRANSFER_DONE IRQ asserted despite being masked");

    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT_TRANSFER_DONE_masked", 8'b0001_0000, rd, 8'b0001_0000);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));
    // end

    // // W1C Race (deterministic): backdoor-clear then trigger transfer

    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);   // clear all stale bits
    // apb_wr(coverage, APB_TX_DATA,  32'h0000_00AA);   // word 1
    // apb_wr(coverage, APB_TX_DATA,  32'h0000_0055);   // word 2 — keeps BUSY=1 after word 1
    // apb_wr(coverage, APB_SS_CTRL,  32'h0000_0001);   // N: SS asserted, transfer starts at N+1
 
    // repeat (80) @(posedge tb_top.PCLK);              // advance to N+79
 
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_0010);   // ACCESS lands at N+81 = transfer_done_pulse
 
    // check_race(coverage, ref_model, "TRANSFER_DONE", 4);
 
    // // drain word 2 before next sub-test
    // repeat (5000) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    // end
    // apb_wr(coverage, APB_SS_CTRL,  32'h0000_0000);
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    

    // //*======================TX_OVF IRQ test=========================
    // $display("[INTERRUPT_TEST] TX_OVF IRQ TEST starting");
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);  // Clear all IRQs
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0004);  // Enable only TX_OVF
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00100), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // for (int i = 0; i < 12; i++) begin
    //   val = $urandom() & 8'hFF;
    //   apb_wr(coverage, APB_TX_DATA, val);
    //   if (tb_top.spi.cb_mon.irq == 1'b1) break;
    // end
    // coverage.sample_overflow(.tx_ovf(1'b1), .rx_ovf(1'b0), .rx_empty_rd(1'b0));

    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT", 8'b0000_0100, rd, 8'b0000_0100);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00100), .w1c_mask(5'b0),
    //                       .w1c_race_mask(5'b0));
    // end

    // if (tb_top.spi.cb_mon.irq != 1'b1)
    //   ref_model.checker_error("Interrupt test",
    //                           "TX_OVF IRQ not asserted when TX_OVF condition met");

    // apb_wr(coverage, APB_INT_STAT, 32'h0000_0004);  // W1C clear
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00100), .w1c_mask(5'b00100),
    //                     .w1c_race_mask(5'b0));

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0000);  // Mask TX_OVF
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // // drain FIFO
    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    // coverage.sample_ss(4'b0001, 4'b0000);

    // repeat (5000) begin
    //     apb_rd(coverage, APB_STATUS, rd);
    //     if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    // end

    // // One final fresh read
    // apb_rd(coverage, APB_STATUS, rd);
    // coverage.sample_busy(1'b0, 2'b00);

    // if (rd[0] != 1'b0 || rd[2] != 1'b1) begin
    //   $display("[FIFO_STRESS_TEST TX] ERROR: transfer did not complete for width= bits (STATUS=0x%08h)",
    //            rd);
    // end 

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);  // deassert SS_n[0] HIGH
    // coverage.sample_ss(4'b0000, 4'b0000);

    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // for (int i = 0; i <= 8; i++) begin
    //   val = $urandom() & 8'hFF;
    //   apb_wr(coverage, APB_TX_DATA, val);
    //   if (tb_top.spi.cb_mon.irq == 1'b1) begin
    //     ref_model.checker_error("Interrupt test", "TX_OVF IRQ is asserted despite being masked");
    //     break;
    //   end
    // end

    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT", 8'b0000_0100, rd, 8'b0000_0100);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));
    // end

    // // W1C Race (deterministic): backdoor-clear then trigger TX push
    
    // // tb_top.u_wrap.u_dut.u_regfile.int_stat = tb_top.u_wrap.u_dut.u_regfile.int_stat & ~5'b00100;
    // // apb_wr(coverage, APB_TX_DATA, 32'hDEAD_BEEF);
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_0004);
    // tb_top.u_wrap.u_dut.u_regfile.tx_mem[tb_top.u_wrap.u_dut.u_regfile.tx_wp & 4'h7] = 32'hDEAD_BEEF;
    
    // apb_rd(coverage, APB_INT_STAT, rd);
    // ref_model.check_reg_masked("INT_STAT", 8'b0000_0100, rd, 8'b0000_0100);
    // coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b00100),
    //                     .w1c_race_mask(5'b00100));

    // // drain FIFO
    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);  // assert SS_n[0] LOW
    //   coverage.sample_ss(4'b0001, 4'b0000);

    // repeat (5000) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    // end

    // // One final fresh read
    // apb_rd(coverage, APB_STATUS, rd);
    // coverage.sample_busy(1'b0, 2'b00);

    // if (rd[0] != 1'b0 || rd[2] != 1'b1) begin
    //   $display("[FIFO_STRESS_TEST TX] ERROR: transfer did not complete for width= 8bits (STATUS=0x%08h)",
    //              rd);
    // end

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);  // deassert SS_n[0] HIGH
    // coverage.sample_ss(4'b0000, 4'b0000);

    // //==================TX_EMPTY IRQ test=============================

    // $display("[INTERRUPT_TEST] Starting TX_EMPTY IRQ test");
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0001);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00001), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // val = $urandom() & 8'hFF;
    // apb_wr(coverage, APB_TX_DATA, val);
    // apb_rd(coverage, APB_INT_STAT, rd);
    // ref_model.check_reg_masked("INT_STAT", 8'b0000_0000, rd, 8'b0000_0001);

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    // coverage.sample_ss(4'b0001, 4'b0000);

    // repeat (5000) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    // end

    // if (tb_top.spi.cb_mon.irq != 1'b1)
    //   ref_model.checker_error("Interrupt test",
    //                           "TX_EMPTY IRQ not asserted when TX_EMPTY condition met");

    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT", 8'b0000_0001, rd, 8'b0000_0001);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00001), .w1c_mask(5'b0),
    //                       .w1c_race_mask(5'b0));
    // end

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    // coverage.sample_ss(4'b0000, 4'b0000);

    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00001), .w1c_mask(5'b11111),
    //                     .w1c_race_mask(5'b0));
    // apb_rd(coverage, APB_INT_STAT, rd);
    // if(rd[0] == 1'b1)
    //   ref_model.checker_error("Interrupt test", "TX_EMPTY INT_STAT bit not cleared after W1C");
    // if (tb_top.spi.cb_mon.irq == 1'b1)
    //   ref_model.checker_error("Interrupt test", "TX_EMPTY IRQ asserted after W1C clear");

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // val = $urandom() & 8'hFF;
    // apb_wr(coverage, APB_TX_DATA, val);
    // apb_rd(coverage, APB_INT_STAT, rd);
    // ref_model.check_reg_masked("INT_STAT", 8'b0000_0000, rd, 8'b0000_0001);

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    // coverage.sample_ss(4'b0001, 4'b0000);

    //  repeat (5000) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    // end

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    // coverage.sample_ss(4'b0000, 4'b0000);

    // if (tb_top.spi.cb_mon.irq == 1'b1)
    //   ref_model.checker_error("Interrupt test", "TX_EMPTY IRQ asserted despite being masked");

    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT", 8'b0000_0001, rd, 8'b0000_0001);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));
    // end

    // // W1C Race (deterministic): backdoor-clear then trigger TX push
    // apb_wr(coverage, APB_TX_DATA, 32'hDEAD_BEEF);

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    // coverage.sample_ss(4'b0001, 4'b0000);
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_0001);

    // apb_rd(coverage, APB_INT_STAT, rd);
    // ref_model.check_reg_masked("INT_STAT", 8'b0000_0001, rd, 8'b0000_0001);
    // coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b00001),
    //                     .w1c_race_mask(5'b00001));

    //  repeat (5000) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
    // end

    // apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    // coverage.sample_ss(4'b0000, 4'b0000);

    // //================== RX_FULL IRQ test ====================

    // $display("[INTERRUPT_TEST] Starting RX_FULL IRQ test");
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0002);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b00010), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // //drain RX FIFO if not empty from previous tests, to ensure deterministic test start
    // repeat (20) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[4] == 1'b1) break;
    //   apb_rd(coverage, APB_RX_DATA, rd);
    // end

    // //fill the RX FIFO
    // for (int i = 0; i < 8; i++) begin
    //   bit [31:0] val = $urandom() & 8'hFF;
    //   RX_q.push_back(val);
    //   tb_top.u_wrap.u_dut.u_regfile.rx_mem[i] = val;
    // end
    // tb_top.u_wrap.u_dut.u_regfile.rx_rp = 4'h0;
    // tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h8;

    // #3; 


    // //check for RX_FULL IRQ twice and INT_STAT bit
    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT", 8'b0000_0010, rd, 8'b0000_0010);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00010), .w1c_mask(5'b0),
    //                       .w1c_race_mask(5'b0));
    // end

    // if (tb_top.spi.cb_mon.irq != 1'b1)
    //   ref_model.checker_error("Interrupt test",
    //                           "RX_FULL IRQ not asserted when RX_FULL condition met");

    // //disable and check IRQ deassertion
    // apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    // coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // if (tb_top.spi.cb_mon.irq == 1'b1)
    //   ref_model.checker_error("Interrupt test",
    //                           "RX_FULL IRQ not deasserted after masking in INT_EN");
    
    // // Re-enable and check for W1C clear
    // apb_wr(coverage, APB_INT_EN, 32'h0000_0002);
    // apb_rd(coverage, APB_RX_DATA, rd); 
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_0002);
    // coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00010), .w1c_mask(5'b00010),
    //                     .w1c_race_mask(5'b0));

    // ref_model.check_reg_masked("INT_STAT", 8'b0000_0000, rd, 8'b0000_0010); 
    // if (tb_top.spi.cb_mon.irq == 1'b1)
    //   ref_model.checker_error("Interrupt test", "RX_FULL IRQ asserted after W1C clear");
    

    // // W1C RACE
    // tb_top.u_wrap.u_dut.u_regfile.rx_mem[tb_top.u_wrap.u_dut.u_regfile.rx_wp & 4'h7] = val;
    // tb_top.u_wrap.u_dut.u_regfile.rx_wp++;
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_0002);

    // apb_rd(coverage, APB_INT_STAT, rd);
    // ref_model.check_reg_masked("INT_STAT", 8'b0000_0010, rd, 8'b0000_0010);
    // coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b00010), .w1c_mask(5'b00010),
    //                     .w1c_race_mask(5'b00010));

    // repeat (20) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[4] == 1'b1) break;
    //   apb_rd(coverage, APB_RX_DATA, rd);
    // end

    // //================== RX_OVF IRQ test ====================

    // $display("[INTERRUPT_TEST] Starting RX_OVF IRQ test");
    // apb_wr(coverage, APB_INT_STAT, 32'h0000_001F);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0008);
    // coverage.sample_irq(.int_stat(5'b0), .int_en(5'b01000), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // repeat (20) begin
    //   apb_rd(coverage, APB_STATUS, rd);
    //   if (rd[4] == 1'b1) break;
    //   apb_rd(coverage, APB_RX_DATA, rd);
    // end

    // for (int i = 0; i <= 8; i++) tb_top.u_wrap.u_dut.u_regfile.rx_mem[i] = 32'h1000_0000 + i;

    // tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h9;

    // if (tb_top.spi.cb_mon.irq != 1'b1)
    //   ref_model.checker_error("Interrupt test", "RX_OVF IRQ not asserted when RX FIFO overflows");

    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT_RX_OVF", 8'b0000_1000, rd, 8'b0000_1000);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b01000), .w1c_mask(5'b0),
    //                       .w1c_race_mask(5'b0));
    // end

    // apb_wr(coverage, APB_INT_STAT, 32'h0000_0008);
    // coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b01000), .w1c_mask(5'b01000),
    //                     .w1c_race_mask(5'b0));

    // if (tb_top.spi.cb_mon.irq == 1'b1)
    //   ref_model.checker_error("Interrupt test", "RX_OVF IRQ not deasserted after W1C clear");

    // apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    // coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    // tb_top.u_wrap.u_dut.u_regfile.rx_mem[8] = 32'hBEEF_DEAD;
    // tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h8;

    // repeat (2) begin
    //   apb_rd(coverage, APB_INT_STAT, rd);
    //   ref_model.check_reg_masked("INT_STAT_RX_OVF_masked", 8'b0000_1000, rd, 8'b0000_1000);
    //   coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));
    // end

    // if (tb_top.spi.cb_mon.irq == 1'b1)
    //   ref_model.checker_error("Interrupt test", "RX_OVF IRQ asserted despite being masked");

    // tb_top.u_wrap.u_dut.u_regfile.int_stat = tb_top.u_wrap.u_dut.u_regfile.int_stat & ~5'b01000;
    // tb_top.u_wrap.u_dut.u_regfile.rx_mem[8] = 32'h2000_0007;
    // tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h8;

    // apb_rd(coverage, APB_INT_STAT, rd);
    // ref_model.check_reg_masked("INT_STAT_RX_OVF_race", 8'b0000_1000, rd, 8'b0000_1000);
    // coverage.sample_irq(.int_stat(rd[4:0]), .int_en(5'b0), .w1c_mask(5'b01000),
    //                     .w1c_race_mask(5'b01000));

  endtask

endclass

`endif
