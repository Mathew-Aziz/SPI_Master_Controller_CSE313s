//- TP-DLY-01/02
`ifndef DELAY_TRANSFER_TEST_SV
`define DELAY_TRANSFER_TEST_SV 

localparam [7:0] APB_CTRL = 8'h00;
localparam [7:0] APB_STATUS = 8'h04;
localparam [7:0] APB_TX_DATA = 8'h08;
localparam [7:0] APB_RX_DATA = 8'h0C;
localparam [7:0] APB_CLK_DIV = 8'h10;
localparam [7:0] APB_SS_CTRL = 8'h14;
localparam [7:0] APB_INT_EN = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY = 8'h20;

// Magic Numbers
localparam int TIMEOUT_CYCLES = 2_500_000;
localparam int IDLE_MEASURE_TIMEOUT = 200_000;
localparam CTRL_DEFAULT = (1 << 0) | (1 << 1);  // EN=1, MSTR=1
localparam SS_EN0 = 32'h0000_0001;
localparam SS_DISABLE = 32'h0000_0000;

class delay_transfer_test;

  static function int wait_for_busy_set(int timeout = TIMEOUT_CYCLES);
    for (int i = 0; i < timeout; i++) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 1) return 1;
    end

    $display("[CHECKER_ERROR] delay_transfer: timeout waiting for BUSY=1");
    return 0;
  endfunction

  static function int wait_for_busy_clear(int timeout = TIMEOUT_CYCLES);
    for (int i = 0; i < timeout; i++) begin
      @(posedge tb_top.PCLK);
      if ((tb_top.u_apb_bfm.apb_read(APB_STATUS) & 1) == 1) return 1;
    end

    $display("[CHECKER_ERROR] delay_transfer: timeout waiting for BUSY=0");
    return 0;
  endfunction

  static task cleanup();
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_DISABLE);
    @(posedge tb_top.PCLK);
  endtask


  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
    // TODO:
    // DELAY= 0,1,>=128. Queue 2+ words, verify inserted idle half-cycles and BUSY stays 1 (R21).

    $display("[INFO] delay_transfer_test: starting");
    // Reset Sequence
    tb_top.PRESETn = 0;
    repeat (5) @(posedge tb_top.PCLK);
    tb_top.PRESETn = 1;
    repeat (2) @(posedge tb_top.PCLK);

    tb_top.bfm_mode      = 2'b00;  // Mode 0 (CPOL=0, CPHA=0)
    tb_top.bfm_miso_word = 8'h00;  // Dummy echo
    tb_top.bfm_pattern   = EDGE_DETECTION_PATTERN;

    tb_top.u_apb_bfm.apb_write(APB_CTRL, CTRL_DEFAULT);  // EN=1, MSTR=1, MODE=0, WIDTH=8
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, SS_DISABLE);  // DIV=0 baseline
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, SS_EN0);  // SS_EN[0]=1, SS_VAL[0]=0

    // Phase 1
    int delay_values[$] = '{0, 1, 200};

    foreach (delay_values[i]) begin

    end


    $display("[INFO] delay_transfer_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
