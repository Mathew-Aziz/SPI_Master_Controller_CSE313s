`ifndef MODE_COVERAGE_TEST_SV
`define MODE_COVERAGE_TEST_SV 

class mode_coverage_test;

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

    bit [31:0] rd, tx_word, rx_word, expected_rx, ctrl_val;
    integer mode, lsb_first, width_idx, width_bits, timeout;

    $display("[INFO] mode_coverage_test: starting");

    // ---- SETUP ----
    ref_model.apply_reset(.min_cycles(2));

    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0004);
    coverage.sample_clk_div(16'h0004);

    apb_wr(coverage, APB_DELAY, 32'h0000_0000);

    apb_wr(coverage, APB_INT_EN, 32'h0000_0000);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    apb_wr(coverage, APB_INT_STAT, 32'hFFFF_FFFF);
    coverage.sample_irq(.int_stat(5'b0), .int_en(5'b0), .w1c_mask(5'b11111), .w1c_race_mask(5'b0));

    tb_top.bfm_mode      = 2'b00;
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_miso_word = 32'hA5A5_A5A5;
    tb_top.bfm_lsb_first = 1'b0;
    tb_top.bfm_width     = 2'b00;

    // ---- MAIN LOOP: 4 modes x 2 orders x 3 widths = 24 combinations ----
    for (mode = 0; mode < 4; mode++) begin
      for (lsb_first = 0; lsb_first < 2; lsb_first++) begin
        for (width_idx = 0; width_idx < 3; width_idx++) begin

          // Width in bits
          case (width_idx)
            0: width_bits = 8;
            1: width_bits = 16;
            2: width_bits = 32;
            default: width_bits = 8;
          endcase

          // TX pattern and expected RX from BFM
          case (width_idx)
            0: begin
              tx_word     = 32'h0000_0081;
              expected_rx = {24'h0, 8'hA5};
            end
            1: begin
              tx_word     = 32'h0000_8001;
              expected_rx = {16'h0, 16'hA5A5};
            end
            2: begin
              tx_word     = 32'h8000_0001;
              expected_rx = 32'hA5A5_A5A5;
            end
            default: begin
              tx_word     = 32'h0000_0081;
              expected_rx = {24'h0, 8'hA5};
            end
          endcase

          // Sync BFM
          tb_top.bfm_mode      = mode[1:0];
          tb_top.bfm_lsb_first = lsb_first[0];
          tb_top.bfm_width     = width_idx[1:0];
          tb_top.bfm_miso_word = expected_rx;
          tb_top.bfm_pattern   = expected_rx[7:0];

          // Build CTRL value
          ctrl_val             = 32'h0;
          ctrl_val[0]          = 1'b1;  // EN
          ctrl_val[1]          = 1'b1;  // MSTR
          ctrl_val[3:2]        = mode[1:0];  // MODE
          ctrl_val[4]          = lsb_first[0];  // LSB_FIRST
          ctrl_val[7:6]        = width_idx[1:0];  // WIDTH
          ctrl_val[5]          = 1'b0;  // LOOPBACK off

          apb_wr(coverage, APB_CTRL, ctrl_val);
          coverage.sample_config(.mode(mode[1:0]), .lsb_first(lsb_first[0]), .width(width_idx[1:0]),
                                 .loopback(1'b0));

          // Assert SS
          apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
          coverage.sample_ss(4'b0001, 4'b0000);
          coverage.sample_busy(1'b1, width_idx[1:0]);

          // Predict
          ref_model.predict_word(.tx_word(tx_word), .width_bits(width_bits), .loopback(1'b0),
                                 .miso_word(expected_rx));

          // Drive TX
          apb_wr(coverage, APB_TX_DATA, tx_word);

          // Timeout per width
          case (width_idx)
            0: timeout = 500;
            1: timeout = 1000;
            2: timeout = 2000;
            default: timeout = 500;
          endcase

          // Wait for BUSY=0
          begin
            int wc = 0;
            apb_rd(coverage, APB_STATUS, rd);
            while (rd[0] && wc < timeout) begin
              apb_rd(coverage, APB_STATUS, rd);
              wc++;
            end
            if (rd[0]) begin
              ref_model.checker_error(
                  "mode_coverage_test", $sformatf(
                  "timeout mode=%0d lsb=%0d width=%0d", mode, lsb_first, width_idx));
              apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
              coverage.sample_ss(4'b0000, 4'b0000);
              coverage.sample_busy(1'b0, width_idx[1:0]);
              continue;
            end
          end

          // Read and check RX
          $display("[INFO] mode_coverage_test: checking mode=%0d lsb=%0d width=%0d", mode,
                   lsb_first, width_bits);
          apb_rd(coverage, APB_RX_DATA, rx_word);
          ref_model.check_rx_word(rx_word);

          // Cleanup
          coverage.sample_busy(1'b0, width_idx[1:0]);
          apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
          coverage.sample_ss(4'b0000, 4'b0000);

        end
      end
    end

    $display("[INFO] mode_coverage_test: finished, errors=%0d", ref_model.error_count);

  endtask
endclass

`endif
