`ifndef MODE_COVERAGE_TEST_SV
`define MODE_COVERAGE_TEST_SV 

class mode_coverage_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] rd;
    bit [31:0] tx_word;
    bit [31:0] rx_word;
    bit [31:0] expected_rx;
    integer mode;
    integer lsb_first;
    bit [1:0] width_idx;
    int width_bits;
    integer timeout;
    integer errors = 0;
    bit [31:0] ctrl_val;
    integer wait_count = 0;

    // Reset & Clock Setup
    ref_model.apply_reset(.min_cycles(2));
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'h0000_0004);  // DIV=4 for robust timing
    tb_top.bfm_mode = 2'b00;
    tb_top.bfm_pattern = 8'hA5;
    tb_top.bfm_miso_word = 32'hA5A5_A5A5;
    tb_top.bfm_lsb_first = 1'b0;
    tb_top.bfm_width = 2'b00;

    for (mode = 0; mode < 4; mode++) begin
      for (lsb_first = 0; lsb_first < 2; lsb_first++) begin
        for (width_idx = 0; width_idx < 3; width_idx++) begin

          // Configure DUT CTRL
          ctrl_val = 32'h0;
          ctrl_val[0] = 1'b1;
          ctrl_val[1] = 1'b1;
          ctrl_val[3:2] = mode[1:0];
          ctrl_val[4] = lsb_first;
          ctrl_val[7:6] = width_idx;
          ctrl_val[5] = 1'b0;

          tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);
          tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

          // Map width index to bit count
          case (width_idx)
            0: width_bits = 8;
            1: width_bits = 16;
            2: width_bits = 32;
            default: width_bits = 8;
          endcase

          // Test patterns (asymmetric for bit-order detection)
          case (width_idx)
            2'b00: begin
              tx_word = 32'h0000_0081;
              expected_rx = {24'h0, 8'hA5};
            end
            2'b01: begin
              tx_word = 32'h0000_8001;
              expected_rx = {16'h0, 16'hA5A5};
            end
            2'b10: begin
              tx_word = 32'h8000_0001;
              expected_rx = 32'hA5A5_A5A5;
            end
          endcase

          // Configure BFM to match DUT
          tb_top.bfm_mode = mode[1:0];
          tb_top.bfm_lsb_first = lsb_first;
          tb_top.bfm_width = width_idx;
          tb_top.bfm_miso_word = expected_rx;
          tb_top.bfm_pattern = expected_rx[7:0];

          // Predict expected RX
          ref_model.predict_word(.tx_word(tx_word), .width_bits(width_bits), .loopback(1'b0),
                                 .miso_word(expected_rx));

          // Drive stimulus
          tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_word);

          // Wait for transfer completion (bounded timeout)
          case (width_idx)
            0: timeout = 500;
            1: timeout = 1000;
            2: timeout = 2000;
          endcase

          wait_count = 0;
          repeat (timeout) begin
            tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
            if (!rd[0]) break;
            wait_count++;
          end

          if (wait_count == timeout) begin
            $display(
                "[CHECKER_ERROR] mode_coverage_test: timeout waiting BUSY=0 (mode=%0d, width=%0d)",
                mode, width_idx);
            errors++;
            ref_model.error_count++;
            continue;
          end

          // Verify RX
          tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rx_word);
          ref_model.check_rx_word(rx_word);
        end
      end
    end

    // Cleanup
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

  endtask
endclass

`endif
