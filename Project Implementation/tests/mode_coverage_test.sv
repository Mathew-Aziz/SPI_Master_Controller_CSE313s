`ifndef MODE_COVERAGE_TEST_SV
`define MODE_COVERAGE_TEST_SV 

// NOTE: your original snippet omitted these localparams; keep them here so the
// file is self-contained like the other tests.
localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

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

    // -------------------------------------------------------------------------
    // Local APB wrappers: BFM + coverage sampling (R1/R22)
    // -------------------------------------------------------------------------
    task automatic apb_wr(input bit [7:0] addr, input bit [31:0] data);
      tb_top.u_apb_bfm.apb_write(addr, data);
      coverage.sample_apb(.addr(addr),
                          .is_write(1'b1),
                          .wdata(data),
                          .rdata(32'h0),
                          .pslverr(1'b0),
                          .pready(1'b1));
    endtask

    task automatic apb_rd(input bit [7:0] addr, output bit [31:0] data);
      tb_top.u_apb_bfm.apb_read(addr, data);
      coverage.sample_apb(.addr(addr),
                          .is_write(1'b0),
                          .wdata(32'h0),
                          .rdata(data),
                          .pslverr(1'b0),
                          .pready(1'b1));
    endtask

    // Reset & Clock Setup
    ref_model.apply_reset(.min_cycles(2));

    apb_wr(APB_CLK_DIV, 32'h0000_0004);  // DIV=4 for robust timing
    coverage.sample_clk_div(16'h0004);

    // Default BFM init (will be overwritten per iteration)
    tb_top.bfm_mode      = 2'b00;
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_miso_word = 32'hA5A5_A5A5;
    tb_top.bfm_lsb_first = 1'b0;
    tb_top.bfm_width     = 2'b00;

    for (mode = 0; mode < 4; mode++) begin
      for (lsb_first = 0; lsb_first < 2; lsb_first++) begin
        for (width_idx = 0; width_idx < 3; width_idx++) begin

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
              tx_word     = 32'h0000_0081;
              expected_rx = {24'h0, 8'hA5};
            end
            2'b01: begin
              tx_word     = 32'h0000_8001;
              expected_rx = {16'h0, 16'hA5A5};
            end
            2'b10: begin
              tx_word     = 32'h8000_0001;
              expected_rx = 32'hA5A5_A5A5;
            end
          endcase

          // Configure BFM to match DUT
          tb_top.bfm_mode      = mode[1:0];
          tb_top.bfm_lsb_first = lsb_first;
          tb_top.bfm_width     = width_idx;
          tb_top.bfm_miso_word = expected_rx;
          tb_top.bfm_pattern   = expected_rx[7:0];

          // Configure DUT CTRL
          ctrl_val        = 32'h0;
          ctrl_val[0]     = 1'b1;
          ctrl_val[1]     = 1'b1;
          ctrl_val[3:2]   = mode[1:0];
          ctrl_val[4]     = lsb_first;
          ctrl_val[7:6]   = width_idx;
          ctrl_val[5]     = 1'b0;

          apb_wr(APB_CTRL, ctrl_val);

          // Cover config (R4/R5/R6/R25)
          coverage.sample_config(.mode(mode[1:0]), .lsb_first(lsb_first), .width(width_idx), .loopback(1'b0));

          // Assert SS
          apb_wr(APB_SS_CTRL, 32'h0000_0001);
          coverage.sample_ss(4'b0001, 4'b0000);

          coverage.sample_busy(1'b1, width_idx);

          // Predict expected RX
          ref_model.predict_word(.tx_word(tx_word), .width_bits(width_bits), .loopback(1'b0),
                                 .miso_word(expected_rx));

          // Drive stimulus
          apb_wr(APB_TX_DATA, tx_word);

          // Wait for transfer completion (bounded timeout)
          case (width_idx)
            0: timeout = 500;
            1: timeout = 1000;
            2: timeout = 2000;
          endcase

          wait_count = 0;
          repeat (timeout) begin
            apb_rd(APB_STATUS, rd);
            if (!rd[0]) break;
            wait_count++;
          end

          if (wait_count == timeout) begin
            $display("[CHECKER_ERROR] mode_coverage_test: timeout waiting BUSY=0 (mode=%0d, width=%0d)",
                     mode, width_idx);
            errors++;
            ref_model.error_count++;
            // ensure SS released even on timeout
            apb_wr(APB_SS_CTRL, 32'h0000_0000);
            coverage.sample_ss(4'b0000, 4'b0000);
            coverage.sample_busy(1'b0, width_idx);
            continue;
          end

          // Verify RX
          apb_rd(APB_RX_DATA, rx_word);
          ref_model.check_rx_word(rx_word);

          // BUSY ended + SS cleanup
          coverage.sample_busy(1'b0, width_idx);
          apb_wr(APB_SS_CTRL, 32'h0000_0000);
          coverage.sample_ss(4'b0000, 4'b0000);
        end
      end
    end

  endtask
endclass

`endif