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

    bit [31:0] rd;

    $display("[INFO] fifo_stress_test: starting");

    // TODO:

    //1. Configure BFM slave stable mode/width (mode0, width=8) 
    tb_top.bfm_mode      = 2'b00;  // CPOL=0 CPHA=0
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_width     = 2'b00;  // 8-bit
    tb_top.bfm_lsb_first = 1'b0;  // MSB-first
    tb_top.bfm_miso_word = 32'h0000_00A5;  // matches bfm_pattern
        
    //* - Fill TX to depth 8 (R11), check TX_FULL in STATUS

    //1. Assert SS
    
    //3. Push 8 bytes without reading, confirm STATUS.FULL (R11)

    //* - Drain via transfers and verify ordering (R9)

    //1. 

    //* - Fill RX to depth 8 without reading (R12), then read out and verify ordering (R10)
    
    
    //* - Hit occupancy bins: empty,1,4,7,full for both FIFOs

    $display("[INFO] fifo_stress_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif