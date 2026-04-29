//- TP-DLY-01/02
`ifndef DELAY_TRANSFER_TEST_SV
`define DELAY_TRANSFER_TEST_SV

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class delay_transfer_test;

  static task run(ref spi_ref_model     ref_model,
                  ref spi_coverage_col  coverage);

    $display("[INFO] delay_transfer_test: starting");

    // TODO:
    // DELAY=0,1,>=128. Queue 2+ words, verify inserted idle half-cycles and BUSY stays 1 (R21).

    $display("[INFO] delay_transfer_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif