//- TP-REG-01/02/04 (+ TP-REG-05 optional)
`ifndef REG_ACCESS_TEST_SV
`define REG_ACCESS_TEST_SV 

localparam [7:0] APB_CTRL = 8'h00;
localparam [7:0] APB_STATUS = 8'h04;
localparam [7:0] APB_TX_DATA = 8'h08;
localparam [7:0] APB_RX_DATA = 8'h0C;
localparam [7:0] APB_CLK_DIV = 8'h10;
localparam [7:0] APB_SS_CTRL = 8'h14;
localparam [7:0] APB_INT_EN = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY = 8'h20;

class reg_access_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] rd;
    bit [31:0] rd_small = 32'h0000_0001;
    bit [31:0] rd_big = 32'hA5A5_5A5A;

    $display("[INFO] reg_access_test: starting");

    // Reset before stimulus
    ref_model.apply_reset(2);

    // ---------------- TP-REG-01: Reset values ----------------
    tb_top.u_apb_bfm.apb_read(APB_CTRL, rd);
    ref_model.check_reg("CTRL", 32'h0, rd);

    tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
    ref_model.check_reg("STATUS", 32'h0000_0012, rd);

    tb_top.u_apb_bfm.apb_read(APB_TX_DATA, rd);
    ref_model.check_reg("TX_DATA", 32'h0, rd);

    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    ref_model.check_reg("RX_DATA", 32'h0, rd);

    tb_top.u_apb_bfm.apb_read(APB_CLK_DIV, rd);
    ref_model.check_reg("CLK_DIV", 32'h0, rd);

    tb_top.u_apb_bfm.apb_read(APB_SS_CTRL, rd);
    ref_model.check_reg("SS_CTRL", 32'h0, rd);

    tb_top.u_apb_bfm.apb_read(APB_INT_EN, rd);
    ref_model.check_reg("INT_EN", 32'h0, rd);

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
    ref_model.check_reg("INT_STAT", 32'h0, rd);

    tb_top.u_apb_bfm.apb_read(APB_DELAY, rd);
    ref_model.check_reg("DELAY", 32'h0, rd);

    // ---------------- TP-REG-02: RW readback ----------------
    tb_top.u_apb_bfm.apb_write(APB_CTRL, rd_small);
    tb_top.u_apb_bfm.apb_read(APB_CTRL, rd);
    ref_model.check_reg_masked("CTRL", rd_small, rd, 32'h0000_003F);

    tb_top.u_apb_bfm.apb_write(APB_CTRL, rd_big);
    tb_top.u_apb_bfm.apb_read(APB_CTRL, rd);
    ref_model.check_reg_masked("CTRL", rd_big, rd, 32'h0000_003F);

    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, rd_small);
    tb_top.u_apb_bfm.apb_read(APB_CLK_DIV, rd);
    ref_model.check_reg_masked("CLK_DIV", rd_small, rd, 32'h0000_FFFF);

    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, rd_big);
    tb_top.u_apb_bfm.apb_read(APB_CLK_DIV, rd);
    ref_model.check_reg_masked("CLK_DIV", rd_big, rd, 32'h0000_FFFF);

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, rd_small);
    tb_top.u_apb_bfm.apb_read(APB_SS_CTRL, rd);
    ref_model.check_reg_masked("SS_CTRL", rd_small, rd, 32'h0000_00FF);

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, rd_big);
    tb_top.u_apb_bfm.apb_read(APB_SS_CTRL, rd);
    ref_model.check_reg_masked("SS_CTRL", rd_big, rd, 32'h0000_00FF);

    tb_top.u_apb_bfm.apb_write(APB_INT_EN, rd_small);
    tb_top.u_apb_bfm.apb_read(APB_INT_EN, rd);
    ref_model.check_reg_masked("INT_EN", rd_small, rd, 32'h0000_001F);

    tb_top.u_apb_bfm.apb_write(APB_INT_EN, rd_big);
    tb_top.u_apb_bfm.apb_read(APB_INT_EN, rd);
    ref_model.check_reg_masked("INT_EN", rd_big, rd, 32'h0000_001F);

    tb_top.u_apb_bfm.apb_write(APB_DELAY, rd_small);
    tb_top.u_apb_bfm.apb_read(APB_DELAY, rd);
    ref_model.check_reg_masked("DELAY", rd_small, rd, 32'h0000_00FF);

    tb_top.u_apb_bfm.apb_write(APB_DELAY, rd_big);
    tb_top.u_apb_bfm.apb_read(APB_DELAY, rd);
    ref_model.check_reg_masked("DELAY", rd_big, rd, 32'h0000_00FF);

    // STATUS is RO: write should not change it
    tb_top.u_apb_bfm.apb_write(APB_STATUS, 32'hFFFF_FFFF);
    tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
    ref_model.check_reg("STATUS_RO", 32'h0000_0012, rd);

    // TX_DATA read returns 0
    tb_top.u_apb_bfm.apb_read(APB_TX_DATA, rd);
    ref_model.check_tx_data_read_zero(rd);

    // RX_DATA write ignored (read should still be 0 when empty)
    tb_top.u_apb_bfm.apb_write(APB_RX_DATA, 32'hDEAD_BEEF);
    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    ref_model.check_reg("RX_DATA_WO", 32'h0, rd);

    // ---------------- TP-REG-04: Reserved offsets ----------------
    tb_top.u_apb_bfm.apb_read(8'h24, rd);
    tb_top.u_apb_bfm.apb_write(8'h24, 32'hAABB_CCDD);
    tb_top.u_apb_bfm.apb_read(8'h24, rd);
    ref_model.check_reserved_read_zero(8'h24, rd);

    tb_top.u_apb_bfm.apb_read(8'h28, rd);
    tb_top.u_apb_bfm.apb_write(8'h28, 32'hAABB_CCDD);
    tb_top.u_apb_bfm.apb_read(8'h28, rd);
    ref_model.check_reserved_read_zero(8'h28, rd);

    tb_top.u_apb_bfm.apb_read(8'h3C, rd);
    tb_top.u_apb_bfm.apb_write(8'h3C, 32'hAABB_CCDD);
    tb_top.u_apb_bfm.apb_read(8'h3C, rd);
    ref_model.check_reserved_read_zero(8'h3C, rd);

    tb_top.u_apb_bfm.apb_read(8'h7C, rd);
    tb_top.u_apb_bfm.apb_write(8'h7C, 32'hAABB_CCDD);
    tb_top.u_apb_bfm.apb_read(8'h7C, rd);
    ref_model.check_reserved_read_zero(8'h7C, rd);

    tb_top.u_apb_bfm.apb_read(8'h42, rd);
    tb_top.u_apb_bfm.apb_write(8'h42, 32'hAABB_CCDD);
    tb_top.u_apb_bfm.apb_read(8'h42, rd);
    ref_model.check_reserved_read_zero(8'h42, rd);

    // ---------------- TP-REG-05: EN=0 behavior ----------------
    tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0002);  // MSTR=1, EN=0
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAABB_CCDD);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0);

    // Check STATUS flags after EN=0 attempt
    tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
    ref_model.check_tx_status(rd, 1'b0, 1'b1, 1'b0);  // full=0, empty=1, busy=0
    ref_model.check_rx_status(rd, 1'b0, 1'b1);  // full=0, empty=1

    if (rd !== 32'h0) begin
      ref_model.checker_error("EN0_RX_NONZERO", $sformatf("RX_DATA=0x%08h (expected 0)", rd));
    end

    $display("[INFO] reg_access_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
