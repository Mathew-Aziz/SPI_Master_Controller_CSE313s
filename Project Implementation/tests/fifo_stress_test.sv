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

    for(int width = 0; width < 3; i++) begin
     
      tb_top.bfm_width     = 2'(width);  // 8-bit
      coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(width), .loopback(1'b0));

      // confirm TX_FIFO is empty
      apb_rd(coverage, APB_STATUS, rd);

      if (rd[2] != 1'b1) begin  // If not empty, drain it first
        apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);  // assert ss[0] LOW
        coverage.sample_ss(4'b0001, 4'b0000);

        repeat (500) begin
          apb_rd(coverage, APB_STATUS, rd);
          if (rd[0] == 1'b0) break;
        end

        coverage.sample_busy(1'b0, 2'b00);
        ref_model.check_reg_masked("STATUS", 8'b0000_0100, rd, 8'b0000_0100);

        apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);  // deassert ss[0] HIGH
        coverage.sample_ss(4'b0000, 4'b0000);
      end

      // Push 8 bytes with reading TX_FULL flag, confirm STATUS.FULL (R11)
      for (int i = 0; i < 8; i++) begin
        uint32_t val = $urandom();
        TX_q.push_back(val);
        apb_wr(coverage, APB_TX_DATA, val);

        // Track FIFO occupancy for coverage (best-effort)
        coverage.sample_fifo(i + 1, 0);

        apb_rd(coverage, APB_STATUS, rd);
        if (i < 7) begin
          ref_model.check_tx_status(rd, .expect_full(1'b0), .expect_empty(1'b0), .expect_busy(1'b0));
        end else begin
          ref_model.check_tx_status(rd, .expect_full(1'b1), .expect_empty(1'b0), .expect_busy(1'b0));
        end
      end

      // Verify FIFO order via direct probing (R9)
      ref_model.verify_tx_fifo_order(TX_q);

      // Fill RX to depth 8 without reading (R12), then read out and verify ordering (R10)

      // Empty RX FIFO by reading until empty
      repeat (20) begin
        apb_rd(coverage, APB_STATUS, rd);
        if (rd[4] == 1'b1) break;  // RX_EMPTY=1 means empty
        apb_rd(coverage, APB_RX_DATA, rd);
      end
      coverage.sample_fifo(8, 0);  // TX still full from earlier

      for (int i = 0; i < 8; i++) begin
        uint32_t val = $urandom();
        RX_q.push_back((width == 0)? val & 8'hFF:
                        (width == 1)? val & 16'hFFFF:
                                      val);
        tb_top.u_wrap.u_dut.u_regfile.rx_mem[i] = RX_q[i];
                                      
      end

      tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h8;

      apb_rd(coverage, APB_STATUS, rd);
      ref_model.check_rx_status(rd, .expect_full(1'b1), .expect_empty(1'b0));
      coverage.sample_fifo(8, 8);

      // Read out RX FIFO and verify order (R10)
      for (int i = 0; i < 8; i++) begin
        apb_rd(coverage, APB_RX_DATA, rd);
        ref_model.check_reg("RX_DATA", RX_q[i], rd);
        coverage.sample_fifo(8, 7 - i);
      end

      // Check STATUS shows RX_EMPTY after reading all 8
      apb_rd(coverage, APB_STATUS, rd);
      ref_model.check_rx_status(rd, .expect_full(1'b0), .expect_empty(1'b1));
      coverage.sample_fifo(8, 0);

    end

    $display("[INFO] fifo_stress_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
