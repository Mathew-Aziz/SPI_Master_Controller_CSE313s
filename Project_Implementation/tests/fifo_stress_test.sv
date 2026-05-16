//- TP-FIFO-01/02/03/04, optionally trigger TP-FIFO-05/06 during stress
`ifndef FIFO_STRESS_TEST_SV
`define FIFO_STRESS_TEST_SV 


class fifo_stress_test;


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

    bit [31:0] rd = 0;
    bit [31:0] TX_q[$];
    bit [31:0] RX_q[$];

    $display("[INFO] fifo_stress_test: starting");

    // 1. Configure BFM slave stable mode/width (mode0, width=8) 
    tb_top.bfm_mode      = 2'b00;  // CPOL=0 CPHA=0
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_lsb_first = 1'b0;  // MSB-first
    tb_top.bfm_miso_word = 32'h0000_00A5;  // matches bfm_pattern

    apb_wr(coverage, APB_CTRL, 32'h0000_0003);  // EN, MSTR
    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0004);  // divide /4
    coverage.sample_clk_div(16'h0004);

    for (int width = 0; width < 3; width++) begin

      tb_top.bfm_width = 2'(width);
      apb_rd(coverage, APB_CTRL, rd);
      apb_wr(coverage, APB_CTRL, (rd & ~(32'h3 << 6)) | (width << 6));  // EN, MSTR, WIDTH
      coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'(width)), .loopback(1'b0));

      // confirm TX_FIFO is empty
      
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[2] != 1'b1) begin  // If not empty, drain it first
        $display("[FIFO_STRESS_TEST] FIFO not empty, Draining before test...");
        apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);  // assert ss[0] LOW
        coverage.sample_ss(4'b0001, 4'b0000);

        repeat (2000) begin
          apb_rd(coverage, APB_STATUS, rd);
          if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
        end

        apb_rd(coverage, APB_STATUS, rd);
        coverage.sample_busy(1'b0, 2'b00);
        
        if (rd[2] != 1'b1) begin
          $display("[FIFO_STRESS_TEST] ERROR: drain incomplete for width=%0d", width);
        end else begin
          $display("[FIFO_STRESS_TEST] FIFO drained, ready for width=%0d test", width);
        end

        apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);  // deassert SS_n[0] HIGH
        coverage.sample_ss(4'b0000, 4'b0000);
      
      end  
      else begin
        $display("[FIFO_STRESS_TEST] FIFO already empty, no need to drain");
      end
      
      ref_model.check_reg_masked("STATUS", 8'b0000_0100, rd, 8'b0000_0100);

      // Push 8 bytes with reading TX_FULL flag, confirm STATUS.FULL (R11)
      for (int i = 0; i < 8; i++) begin
        bit [31:0] val = $urandom() & ((width == 0) ? 8'hFF :
                                (width == 1) ? 16'hFFFF : 32'hFFFF_FFFF);
        TX_q.push_back(val);
        apb_wr(coverage, APB_TX_DATA, val);

        // Track FIFO occupancy for coverage (best-effort)
        coverage.sample_fifo(i + 1, 0);

        apb_rd(coverage, APB_STATUS, rd);
        if (i < 7) begin
          ref_model.check_tx_status(rd, .expect_full(1'b0), .expect_empty(1'b0),
                                    .expect_busy(1'b0));
        end else begin
          ref_model.check_tx_status(rd, .expect_full(1'b1), .expect_empty(1'b0),
                                    .expect_busy(1'b0));
        end
      end

      ref_model.verify_tx_fifo_order(TX_q, width);

      apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);  // assert SS_n[0] LOW
      coverage.sample_ss(4'b0001, 4'b0000);
 
      repeat (5000) begin
        apb_rd(coverage, APB_STATUS, rd);
        if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
      end
 
      // One final fresh read
      apb_rd(coverage, APB_STATUS, rd);
      coverage.sample_busy(1'b0, 2'(width));
 
      if (rd[0] != 1'b0 || rd[2] != 1'b1) begin
        $display("[FIFO_STRESS_TEST TX] ERROR: transfer did not complete for width=%0d (STATUS=0x%08h)",
                 width, rd);
      end
 
      apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);  // deassert SS_n[0] HIGH
      coverage.sample_ss(4'b0000, 4'b0000);

      // Fill RX to depth 8 without reading (R12), then read out and verify ordering (R10)

      // Empty RX FIFO by reading until empty
      repeat (20) begin
        apb_rd(coverage, APB_STATUS, rd);
        if (rd[4] == 1'b1) break;  // RX_EMPTY=1 means empty
        apb_rd(coverage, APB_RX_DATA, rd);
      end
      coverage.sample_fifo(8, 0);  // TX still full from earlier

      for (int i = 0; i < 8; i++) begin
        bit [31:0] val = $urandom() & ((width == 0) ? 8'hFF :
                                      (width == 1) ? 16'hFFFF : 32'hFFFF_FFFF);

        RX_q.push_back(val);
        tb_top.u_wrap.u_dut.u_regfile.rx_mem[i] = val;

      end

      tb_top.u_wrap.u_dut.u_regfile.rx_rp = 4'h0;
      tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h8;

      apb_rd(coverage, APB_STATUS, rd);
      ref_model.check_rx_status(rd, .expect_full(1'b1), .expect_empty(1'b0));
      coverage.sample_fifo(0, 8);

      // Read out RX FIFO and verify order (R10)
      for (int i = 0; i < 8; i++) begin
        apb_rd(coverage, APB_RX_DATA, rd);
        ref_model.check_reg("RX_DATA", RX_q[i], rd);
        coverage.sample_fifo(0, 7 - i);
      end

      // Check STATUS shows RX_EMPTY after reading all 8
      apb_rd(coverage, APB_STATUS, rd);
      ref_model.check_rx_status(rd, .expect_full(1'b0), .expect_empty(1'b1));
      coverage.sample_fifo(0, 0);

      TX_q.delete();
      RX_q.delete();
      $display("[FIFO_STRESS_TEST] fifo_stress_test: width=%0d test Finished", width);
    end

    $display("[INFO] fifo_stress_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
