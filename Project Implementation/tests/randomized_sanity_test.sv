// =============================================================================
// randomized_sanity_test.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
`ifndef RANDOMIZED_SANITY_TEST_SV
`define RANDOMIZED_SANITY_TEST_SV 

class randomized_sanity_test;

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

    spi_txn        t;
    bit     [31:0] ctrl_word;
    bit     [31:0] rd;
    int            seed;


    $display("[INFO] randomized_sanity_test: starting");

    t = new();

    if ($value$plusargs("SEED=%d", seed)) t.srandom(seed);

    if (!t.randomize() with {
          mode == 2'b00;
          width == 2'b00;
          lsb_first == 1'b0;
          loopback == 1'b0;
          clk_div inside {[1 : 32]};
        }) begin
      $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
      ref_model.error_count++;
      return;
    end

    $display("[INFO] randomized_sanity_test: %s", t.sprint());

    tb_top.bfm_mode      = t.mode;
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_width     = t.width;
    tb_top.bfm_lsb_first = t.lsb_first;
    tb_top.bfm_miso_word = {24'h0, tb_top.bfm_pattern};

    ctrl_word            = 32'h0;
    ctrl_word[0]         = 1'b1;
    ctrl_word[1]         = 1'b1;
    ctrl_word[3:2]       = t.mode;
    ctrl_word[4]         = t.lsb_first;
    ctrl_word[5]         = t.loopback;
    ctrl_word[7:6]       = t.width;

    apb_wr(8'h00, ctrl_word);  // CTRL
    apb_wr(8'h10, {16'h0, t.clk_div});  // CLK_DIV
    coverage.sample_clk_div(t.clk_div[15:0]);

    apb_wr(8'h20, {24'h0, t.delay_cfg});  // DELAY
    coverage.sample_delay(t.delay_cfg[7:0], 1'b0);

    apb_wr(8'h18, 32'h0000_000F);  // INT_EN

    ref_model.predict_single_byte(.tx_byte(t.tx_data[7:0]), .miso_pattern(tb_top.bfm_pattern),
                                  .loopback(t.loopback));

    coverage.sample_config(.mode(t.mode), .lsb_first(t.lsb_first), .width(t.width),
                           .loopback(t.loopback));

    apb_wr(8'h08, t.tx_data);  // TX_DATA
    apb_wr(8'h14, 32'h0000_0001);  // SS_CTRL assert ss[0]
    coverage.sample_ss(4'b0001, 4'b0000);

    repeat (500) begin
      apb_rd(8'h04, rd);  // STATUS
      if (rd[0] == 1'b0) break;
    end
    coverage.sample_busy(1'b0, t.width);

    apb_rd(8'h0C, rd);  // RX_DATA
    ref_model.check_rx(rd);

    apb_wr(8'h14, 32'h0000_0000);
    coverage.sample_ss(4'b0000, 4'b0000);

    $display("[INFO] randomized_sanity_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif  // RANDOMIZED_SANITY_TEST_SV
