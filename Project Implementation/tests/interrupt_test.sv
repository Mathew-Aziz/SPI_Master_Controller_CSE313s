//- TP-IRQ-01/02/03/04 (must hit all 5 sources and masked+unmasked+clear+race)
`ifndef INTERRUPT_TEST_SV
`define INTERRUPT_TEST_SV

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class interrupt_test;

  static task run(ref spi_ref_model     ref_model,
                  ref spi_coverage_col  coverage);

    $display("[INFO] interrupt_test: starting");

    // TODO:
    // For each interrupt source:
    // - cause event
    // - confirm INT_STAT sticky
    // - confirm mask gates IRQ only (R16)
    // - clear via W1C (R17)
    // - W1C race (R18)

    $display("[INFO] interrupt_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif