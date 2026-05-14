//- TP-SPI-04/05 (strong) + boundary patterns of TP-SPI-03
`ifndef WIDTH_COVERAGE_TEST_SV
`define WIDTH_COVERAGE_TEST_SV 

localparam [7:0] APB_CTRL = 8'h00;
localparam [7:0] APB_STATUS = 8'h04;
localparam [7:0] APB_TX_DATA = 8'h08;
localparam [7:0] APB_RX_DATA = 8'h0C;
localparam [7:0] APB_CLK_DIV = 8'h10;
localparam [7:0] APB_SS_CTRL = 8'h14;
localparam [7:0] APB_INT_EN = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY = 8'h20;

class width_coverage_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] tx_word;
    bit [31:0] rd;
    bit [31:0] miso_word;
    bit        timed_out;
    bit [ 1:0] width_enc;
    int        width_bits;
    int        w;
    int        o;
    int        p;
    bit        lsb_first;
    bit [31:0] ctrl_word;
    bit        did_mid_update;

    // extra: next-transfer check
    bit [ 1:0] next_width_enc;
    int        next_width_bits;
    bit        next_lsb_first;
    bit [31:0] tx_word_next;

    $display("[INFO] width_coverage_test: starting");

    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'h0000_0002);
    tb_top.u_apb_bfm.apb_write(APB_DELAY, 32'h0000_0000);

    // Step 1: Width sweep + boundary patterns
    for (w = 0; w < 3; w++) begin
      case (w)
        0: begin
          width_enc  = 2'b00;
          width_bits = 8;
        end
        1: begin
          width_enc  = 2'b01;
          width_bits = 16;
        end
        2: begin
          width_enc  = 2'b10;
          width_bits = 32;
        end
      endcase

      did_mid_update = 1'b0;

      for (p = 0; p < 3; p++) begin
        case (width_bits)
          8: begin
            case (p)
              0: tx_word = 32'h0000_0001;
              1: tx_word = 32'h0000_0080;
              2: tx_word = 32'h0000_00FF;
            endcase
          end
          16: begin
            case (p)
              0: tx_word = 32'h0000_0001;
              1: tx_word = 32'h0000_8000;
              2: tx_word = 32'h0000_A55A;
            endcase
          end
          32: begin
            case (p)
              0: tx_word = 32'h0000_0001;
              1: tx_word = 32'h8000_0000;
              2: tx_word = 32'hDEAD_BEEF;
            endcase
          end
        endcase

        $display("[INFO] width=%0d pattern=0x%08h", width_bits, tx_word);

        // Step 2: BFM config must match CTRL fields
        for (o = 0; o < 2; o++) begin
          lsb_first            = (o == 1);
          miso_word            = ~tx_word;  // hostile MISO

          tb_top.bfm_mode      = 2'b00;  // keep mode fixed in width test
          tb_top.bfm_width     = width_enc;
          tb_top.bfm_lsb_first = lsb_first;
          tb_top.bfm_miso_word = miso_word;

          // Build CTRL explicitly (loopback=0)
          ctrl_word            = 32'h0;
          ctrl_word[0]         = 1'b1;  // EN
          ctrl_word[1]         = 1'b1;  // MSTR
          ctrl_word[3:2]       = 2'b00;  // MODE
          ctrl_word[4]         = lsb_first;  // LSB_FIRST
          ctrl_word[5]         = 1'b0;  // LOOPBACK
          ctrl_word[7:6]       = width_enc;  // WIDTH

          tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_word);

          // Predictor (external MISO)
          ref_model.predict_word(.tx_word(tx_word), .width_bits(width_bits), .loopback(1'b0),
                                 .miso_word(miso_word));

          // Assert SS + push TX
          tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h1);
          tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_word);

          // TP-SPI-05: Mid-transfer update (once per width)
          if (!did_mid_update) begin
            // choose a different width/lsb for next transfer
            next_width_enc = (width_enc == 2'b10) ? 2'b00 : 2'b10;
            next_width_bits = (width_enc == 2'b10) ? 8 : 32;
            next_lsb_first = ~lsb_first;
            tx_word_next    = (next_width_bits == 8)  ? 32'h0000_00A5 :
                              (next_width_bits == 16) ? 32'h0000_A55A :
                                                        32'hCAFE_BABE;

            tb_top.u_apb_bfm.apb_write(
                APB_CTRL, {24'h0, next_width_enc, 1'b0, next_lsb_first, 2'b00, 1'b1, 1'b1});
            did_mid_update = 1'b1;
          end

          // BUSY poll with timeout
          timed_out = 1'b1;
          repeat (500) begin
            tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
            if (rd[0] == 1'b0) begin
              timed_out = 1'b0;
              break;
            end
          end
          if (timed_out)
            ref_model.checker_error("BUSY_TIMEOUT", $sformatf(
                                    "BUSY did not clear (width=%0d lsb=%0d)", width_bits, lsb_first
                                    ));

          // Read RX and check
          tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
          ref_model.check_rx_word(rd);

          // Deassert SS
          tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0);

          // ---------- Extra Test Case A: verify NEXT transfer uses updated CTRL ----------
          if (did_mid_update && (p == 0) && (o == 0)) begin
            // Update BFM to match the CTRL that was written mid-transfer
            tb_top.bfm_width     = next_width_enc;
            tb_top.bfm_lsb_first = next_lsb_first;
            tb_top.bfm_miso_word = ~tx_word_next;

            // Predictor for next transfer (should use updated width/lsb)
            ref_model.predict_word(.tx_word(tx_word_next), .width_bits(next_width_bits),
                                   .loopback(1'b0), .miso_word(~tx_word_next));

            // SS + TX for next transfer
            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h1);
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_word_next);

            timed_out = 1'b1;
            repeat (500) begin
              tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
              if (rd[0] == 1'b0) begin
                timed_out = 1'b0;
                break;
              end
            end
            if (timed_out)
              ref_model.checker_error(
                  "BUSY_TIMEOUT_NEXT", $sformatf(
                  "BUSY did not clear for next transfer width=%0d", next_width_bits));

            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx_word(rd);
            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0);
          end

          // ---------- Extra Test Case B: one loopback corner per width ----------
          if ((p == 0) && (o == 0)) begin
            // Enable loopback for one transfer to ensure width honored in LOOPBACK
            ctrl_word[5] = 1'b1;  // LOOPBACK=1
            tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_word);

            // Predictor expects RX==TX in loopback
            ref_model.predict_word(.tx_word(tx_word), .width_bits(width_bits), .loopback(1'b1),
                                   .miso_word(miso_word));

            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h1);
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_word);

            timed_out = 1'b1;
            repeat (500) begin
              tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
              if (rd[0] == 1'b0) begin
                timed_out = 1'b0;
                break;
              end
            end
            if (timed_out)
              ref_model.checker_error("BUSY_TIMEOUT_LB", $sformatf(
                                      "BUSY did not clear in loopback width=%0d", width_bits));

            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx_word(rd);
            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0);

            // restore loopback off for subsequent cases
            ctrl_word[5] = 1'b0;
            tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_word);
          end
        end
      end
    end

    $display("[INFO] width_coverage_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
