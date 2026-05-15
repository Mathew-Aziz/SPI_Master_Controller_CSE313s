//- TP-REG-01/02/04 (+ TP-REG-05 optional)
`ifndef REG_ACCESS_TEST_SV
`define REG_ACCESS_TEST_SV 

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class reg_access_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] rd;
    bit [31:0] rd_small = 32'h0000_0001;
    bit [31:0] rd_big   = 32'hA5A5_5A5A;

    // -------------------------------------------------------------------------
    // NEW: local APB wrappers that also sample coverage (R1/R22)
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

    $display("[INFO] reg_access_test: starting");

    // Reset before stimulus
    ref_model.apply_reset(2);

    // ---------------- TP-REG-01: Reset values ----------------
    apb_rd(APB_CTRL, rd);
    ref_model.check_reg("CTRL", 32'h0, rd);
    coverage.sample_reset(APB_CTRL, (rd == 32'h0));

    apb_rd(APB_STATUS, rd);
    ref_model.check_reg("STATUS", 32'h0000_0012, rd);
    coverage.sample_reset(APB_STATUS, (rd == 32'h0000_0012));

    apb_rd(APB_TX_DATA, rd);
    ref_model.check_reg("TX_DATA", 32'h0, rd);
    coverage.sample_reset(APB_TX_DATA, (rd == 32'h0));

    apb_rd(APB_RX_DATA, rd);
    ref_model.check_reg("RX_DATA", 32'h0, rd);
    coverage.sample_reset(APB_RX_DATA, (rd == 32'h0));

    apb_rd(APB_CLK_DIV, rd);
    ref_model.check_reg("CLK_DIV", 32'h0, rd);
    coverage.sample_reset(APB_CLK_DIV, (rd == 32'h0));

    apb_rd(APB_SS_CTRL, rd);
    ref_model.check_reg("SS_CTRL", 32'h0, rd);
    coverage.sample_reset(APB_SS_CTRL, (rd == 32'h0));

    apb_rd(APB_INT_EN, rd);
    ref_model.check_reg("INT_EN", 32'h0, rd);
    coverage.sample_reset(APB_INT_EN, (rd == 32'h0));

    apb_rd(APB_INT_STAT, rd);
    ref_model.check_reg("INT_STAT", 32'h0, rd);
    coverage.sample_reset(APB_INT_STAT, (rd == 32'h0));

    apb_rd(APB_DELAY, rd);
    ref_model.check_reg("DELAY", 32'h0, rd);
    coverage.sample_reset(APB_DELAY, (rd == 32'h0));

    // ---------------- TP-REG-02: RW readback ----------------
    apb_wr(APB_CTRL, rd_small);
    apb_rd(APB_CTRL, rd);
    ref_model.check_reg_masked("CTRL", rd_small, rd, 32'h0000_003F);

    apb_wr(APB_CTRL, rd_big);
    apb_rd(APB_CTRL, rd);
    ref_model.check_reg_masked("CTRL", rd_big, rd, 32'h0000_003F);

    apb_wr(APB_CLK_DIV, rd_small);
    coverage.sample_clk_div(rd_small[15:0]);
    apb_rd(APB_CLK_DIV, rd);
    ref_model.check_reg_masked("CLK_DIV", rd_small, rd, 32'h0000_FFFF);

    apb_wr(APB_CLK_DIV, rd_big);
    coverage.sample_clk_div(rd_big[15:0]);
    apb_rd(APB_CLK_DIV, rd);
    ref_model.check_reg_masked("CLK_DIV", rd_big, rd, 32'h0000_FFFF);

    apb_wr(APB_SS_CTRL, rd_small);
    coverage.sample_ss(rd_small[3:0], rd_small[7:4]);
    apb_rd(APB_SS_CTRL, rd);
    ref_model.check_reg_masked("SS_CTRL", rd_small, rd, 32'h0000_00FF);

    apb_wr(APB_SS_CTRL, rd_big);
    coverage.sample_ss(rd_big[3:0], rd_big[7:4]);
    apb_rd(APB_SS_CTRL, rd);
    ref_model.check_reg_masked("SS_CTRL", rd_big, rd, 32'h0000_00FF);

    apb_wr(APB_INT_EN, rd_small);
    apb_rd(APB_INT_EN, rd);
    ref_model.check_reg_masked("INT_EN", rd_small, rd, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(rd[4:0]), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    apb_wr(APB_INT_EN, rd_big);
    apb_rd(APB_INT_EN, rd);
    ref_model.check_reg_masked("INT_EN", rd_big, rd, 32'h0000_001F);
    coverage.sample_irq(.int_stat(5'b0), .int_en(rd[4:0]), .w1c_mask(5'b0), .w1c_race_mask(5'b0));

    apb_wr(APB_DELAY, rd_small);
    coverage.sample_delay(rd_small[7:0], 1'b0);
    apb_rd(APB_DELAY, rd);
    ref_model.check_reg_masked("DELAY", rd_small, rd, 32'h0000_00FF);

    apb_wr(APB_DELAY, rd_big);
    coverage.sample_delay(rd_big[7:0], 1'b0);
    apb_rd(APB_DELAY, rd);
    ref_model.check_reg_masked("DELAY", rd_big, rd, 32'h0000_00FF);

    // STATUS is RO: write should not change it
    apb_wr(APB_STATUS, 32'hFFFF_FFFF);
    apb_rd(APB_STATUS, rd);
    ref_model.check_reg("STATUS_RO", 32'h0000_0012, rd);

    // TX_DATA read returns 0
    apb_rd(APB_TX_DATA, rd);
    ref_model.check_tx_data_read_zero(rd);

    // RX_DATA write ignored (read should still be 0 when empty)
    apb_wr(APB_RX_DATA, 32'hDEAD_BEEF);
    apb_rd(APB_RX_DATA, rd);
    ref_model.check_reg("RX_DATA_WO", 32'h0, rd);

    // ---------------- TP-REG-04: Reserved offsets ----------------
    apb_rd(8'h24, rd);               coverage.sample_reserved(8'h24, 1'b0);
    apb_wr(8'h24, 32'hAABB_CCDD);    coverage.sample_reserved(8'h24, 1'b1);
    apb_rd(8'h24, rd);               coverage.sample_reserved(8'h24, 1'b0);
    ref_model.check_reserved_read_zero(8'h24, rd);

    apb_rd(8'h28, rd);               coverage.sample_reserved(8'h28, 1'b0);
    apb_wr(8'h28, 32'hAABB_CCDD);    coverage.sample_reserved(8'h28, 1'b1);
    apb_rd(8'h28, rd);               coverage.sample_reserved(8'h28, 1'b0);
    ref_model.check_reserved_read_zero(8'h28, rd);

    apb_rd(8'h3C, rd);               coverage.sample_reserved(8'h3C, 1'b0);
    apb_wr(8'h3C, 32'hAABB_CCDD);    coverage.sample_reserved(8'h3C, 1'b1);
    apb_rd(8'h3C, rd);               coverage.sample_reserved(8'h3C, 1'b0);
    ref_model.check_reserved_read_zero(8'h3C, rd);

    apb_rd(8'h7C, rd);               coverage.sample_reserved(8'h7C, 1'b0);
    apb_wr(8'h7C, 32'hAABB_CCDD);    coverage.sample_reserved(8'h7C, 1'b1);
    apb_rd(8'h7C, rd);               coverage.sample_reserved(8'h7C, 1'b0);
    ref_model.check_reserved_read_zero(8'h7C, rd);

    apb_rd(8'h42, rd);               coverage.sample_reserved(8'h42, 1'b0);
    apb_wr(8'h42, 32'hAABB_CCDD);    coverage.sample_reserved(8'h42, 1'b1);
    apb_rd(8'h42, rd);               coverage.sample_reserved(8'h42, 1'b0);
    ref_model.check_reserved_read_zero(8'h42, rd);

    // ---------------- TP-REG-05: EN=0 behavior ----------------
    apb_wr(APB_CTRL, 32'h0000_0002);  // MSTR=1, EN=0
    apb_wr(APB_TX_DATA, 32'hAABB_CCDD);
    apb_wr(APB_SS_CTRL, 32'h0000_0001);
    coverage.sample_ss(4'b0001, 4'b0000);

    apb_rd(APB_RX_DATA, rd);
    apb_wr(APB_SS_CTRL, 32'h0);
    coverage.sample_ss(4'b0000, 4'b0000);

    // Check STATUS flags after EN=0 attempt
    apb_rd(APB_STATUS, rd);
    ref_model.check_tx_status(rd, 1'b0, 1'b1, 1'b0);  // full=0, empty=1, busy=0
    ref_model.check_rx_status(rd, 1'b0, 1'b1);        // full=0, empty=1

    if (rd !== 32'h0) begin
      ref_model.checker_error("EN0_RX_NONZERO", $sformatf("RX_DATA=0x%08h (expected 0)", rd));
    end

    $display("[INFO] reg_access_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif