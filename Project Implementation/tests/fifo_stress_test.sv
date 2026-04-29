//- TP-FIFO-01/02/03/04, optionally trigger TP-FIFO-05/06 during stress
`ifndef FIFO_STRESS_TEST_SV
`define FIFO_STRESS_TEST_SV

localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;

class fifo_stress_test;

  static task run(ref spi_ref_model     ref_model,
                  ref spi_coverage_col  coverage);

    $display("[INFO] fifo_stress_test: starting");

    // TODO:
    // - Fill TX to depth 8 (R11), check TX_FULL in STATUS
    // - Drain via transfers and verify ordering (R9)
    // - Fill RX to depth 8 without reading (R12), then read out and verify ordering (R10)
    // - Hit occupancy bins: empty,1,4,7,full for both FIFOs

    $display("[INFO] fifo_stress_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif