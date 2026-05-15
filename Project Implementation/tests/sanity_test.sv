// =============================================================================
// sanity_test.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
`ifndef SANITY_TEST_SV
`define SANITY_TEST_SV 

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class sanity_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] rd;

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

    $display("[INFO] sanity_test: starting");

    // Configure BFM slave pattern and mode
    tb_top.bfm_mode      = 2'b00;  // CPOL=0 CPHA=0
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_width     = 2'b00;  // 8-bit
    tb_top.bfm_lsb_first = 1'b0;   // MSB-first
    tb_top.bfm_miso_word = 32'h0000_00A5;  // matches bfm_pattern

    // Enable DUT with loopback OFF, master, mode 0, MSB-first, 8-bit
    apb_wr(APB_CTRL, 32'h0000_0003);  // EN, MSTR
    apb_wr(APB_CLK_DIV, 32'h0000_0004);  // divide /4
    coverage.sample_clk_div(16'h0004);

    apb_wr(APB_INT_EN, 32'h0000_000F);

    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00), .loopback(1'b0));

    // Push one byte, assert SS, wait for transfer done
    ref_model.predict_single_byte(.tx_byte(8'h5A), .miso_pattern(tb_top.bfm_pattern),
                                  .loopback(1'b0));
    apb_wr(APB_TX_DATA, 32'h0000_005A);

    // Assert SS0
    apb_wr(APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    // Busy-poll STATUS.BUSY (bit 0)
    repeat (500) begin
      apb_rd(APB_STATUS, rd);
      if (rd[0] == 1'b0) break;
    end
    coverage.sample_busy(1'b0, 2'b00);

    apb_rd(APB_RX_DATA, rd);
    ref_model.check_rx(rd);

    apb_wr(APB_SS_CTRL, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    $display("[INFO] sanity_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif  // SANITY_TEST_SV