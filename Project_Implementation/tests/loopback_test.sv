//- TP-LB-01
`ifndef LOOPBACK_TEST_SV
`define LOOPBACK_TEST_SV 


class loopback_test;

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

    bit [31:0] tx_word;
    bit [31:0] rd;
    bit [31:0] miso_word;
    bit        timed_out;
    bit [ 1:0] width_enc;
    int        width_bits;
    int        w;
    int        o;
    bit        lsb_first;

    // NEW: for coverage sampling convenience
    bit [31:0] ctrl_word;
    int        m;
    bit [ 1:0] mode;

    $display("[INFO] loopback_test: starting");

    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0002);
    coverage.sample_clk_div(16'h0002);

    apb_wr(coverage, APB_DELAY, 32'h0);
    coverage.sample_delay(8'h00, 1'b0);


    for (m = 0; m < 4; m++) begin
      mode = m[1:0];
      // Loop over widths: 8, 16, 32
      for (w = 0; w < 3; w++) begin
        case (w)
          0: begin
            width_enc  = 2'b00;
            width_bits = 8;
            tx_word    = 32'h0000_00A5;
          end
          1: begin
            width_enc  = 2'b01;
            width_bits = 16;
            tx_word    = 32'h0000_A55A;
          end
          2: begin
            width_enc  = 2'b10;
            width_bits = 32;
            tx_word    = 32'hDEAD_BEEF;
          end
        endcase

        $display("started at width:%d", width_bits);

        // Loop over bit order: MSB-first (0), LSB-first (1)
        for (o = 0; o < 2; o++) begin
          lsb_first = (o == 1);
          miso_word = ~tx_word;  // hostile MISO

          $display("started at LSB/MSB:%d", lsb_first);

          // Configure slave BFM to match CTRL
          tb_top.bfm_mode      = mode;
          tb_top.bfm_width     = width_enc;
          tb_top.bfm_lsb_first = lsb_first;
          tb_top.bfm_miso_word = miso_word;

          // Build CTRL (explicit fields) and write it
          ctrl_word            = 32'h0;
          ctrl_word[0]         = 1'b1;  // EN
          ctrl_word[1]         = 1'b1;  // MSTR
          ctrl_word[3:2]       = mode;  // MODE
          ctrl_word[4]         = lsb_first;  // LSB_FIRST
          ctrl_word[5]         = 1'b1;  // LOOPBACK
          ctrl_word[7:6]       = width_enc;  // WIDTH

          apb_wr(coverage, APB_CTRL, ctrl_word);

          // NEW: cover SPI config + loopback (R4/R5/R6/R25 + R19)
          coverage.sample_config(.mode(mode), .lsb_first(lsb_first), .width(width_enc),
                                 .loopback(1'b1));

          // Assert SS0 low (and sample SS coverage)
          apb_wr(coverage, APB_SS_CTRL, 32'h1);
          coverage.sample_ss(4'b0001, 4'b0000);

          // Optional busy sampling: we know we're starting a transfer now
          coverage.sample_busy(1'b1, width_enc);

          // Predict expected RX (loopback => RX == TX)
          ref_model.predict_word(.tx_word(tx_word), .width_bits(width_bits), .loopback(1'b1),
                                 .miso_word(miso_word));

          // Push TX
          apb_wr(coverage, APB_TX_DATA, tx_word);

          // Poll BUSY with timeout
          timed_out = 1'b1;
          repeat (500) begin
            apb_rd(coverage, APB_STATUS, rd);
            if (rd[0] == 1'b0) begin
              timed_out = 1'b0;
              break;
            end
          end

          if (timed_out)
            ref_model.checker_error(
                "BUSY_TIMEOUT", $sformatf(
                "BUSY did not clear for width=%0d lsb=%0d", width_bits, lsb_first));

          // Read RX and check
          apb_rd(coverage, APB_RX_DATA, rd);
          $display(rd);
          ref_model.check_rx_word(rd);

          // BUSY ended
          coverage.sample_busy(1'b0, width_enc);

          // Deassert SS (and sample SS coverage)
          apb_wr(coverage, APB_SS_CTRL, 32'h0);
          coverage.sample_ss(4'b0000, 4'b0000);
        end
      end
    end

    $display("[INFO] loopback_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
