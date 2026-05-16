// =============================================================================
// sanity_test.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
`ifndef SANITY_TEST_SV
`define SANITY_TEST_SV 


class sanity_test;

  // -------------------------------------------------------------------------
  // Class-scope APB wrappers: BFM + coverage sampling (R1/R22)
  // -------------------------------------------------------------------------
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

    bit [31:0] rd;

    $display("[INFO] sanity_test: starting");

    // Configure BFM slave pattern and mode
    tb_top.bfm_mode      = 2'b00;  // CPOL=0 CPHA=0
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_width     = 2'b00;  // 8-bit
    tb_top.bfm_lsb_first = 1'b0;  // MSB-first
    tb_top.bfm_miso_word = 32'h0000_00A5;  // matches bfm_pattern

    // Enable DUT with loopback OFF, master, mode 0, MSB-first, 8-bit
    apb_wr(coverage, APB_CTRL, 32'h0000_0003);  // EN, MSTR
    apb_wr(coverage, APB_CLK_DIV, 32'h0000_0004);  // divide /4
    coverage.sample_clk_div(16'h0004);

    apb_wr(coverage, APB_INT_EN, 32'h0000_000F);

    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00), .loopback(1'b0));

    // Push one byte, assert SS, wait for transfer done
    ref_model.predict_single_byte(.tx_byte(8'h5A), .miso_pattern(tb_top.bfm_pattern),
                                  .loopback(1'b0));

    apb_wr(coverage, APB_TX_DATA, 32'h0000_005A);

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    // Busy-poll STATUS.BUSY (bit 0)
    repeat (500) begin
      apb_rd(coverage, APB_STATUS, rd);
      if (rd[0] == 1'b0) break;
    end
    coverage.sample_busy(1'b0, 2'b00);

    apb_rd(coverage, APB_RX_DATA, rd);
    ref_model.check_rx(rd);

    apb_wr(coverage, APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    $display("[INFO] sanity_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif  // SANITY_TEST_SV
