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

    //*? TX_OVF IRQ test

    //1. W1C all IRQs in INT_STAT

    //2. Enable TX_OVF IRQ in INT_EN

    //3. Fill TX FIFO to trigger TX_OVF condition

    //4. Check INT_STAT for TX_OVF bit set twice to check sticky behavior

    //5. Clear TX_OVF bit via W1C and confirm deassertion

    //6. Mask TX_OVF IRQ in INT_EN 

    //7. Trigger condition again and confirm no IRQ asserted 

    //*? TRANSFER_DONE IRQ test
    //1. W1C all IRQs in INT_STAT

    //2. Enable TRANSFER_DONE IRQ in INT_EN

    //3. Fill and drain TX FIFO to trigger TRANSFER_DONE condition for each transfer

    //4. Check INT_STAT for TRANSFER_DONE bit set twice to check sticky behavior

    //5. Clear TRANSFER_DONE bit via W1C and confirm deassertion

    //6. Mask TRANSFER_DONE IRQ in INT_EN 

    //7. Trigger condition again and confirm no IRQ asserted

    //*? Tx_EMPTY IRQ test

    //1. W1C all IRQs in INT_STAT

    //2. Enable TX_EMPTY IRQ in INT_EN

    //3. Fill then drain TX FIFO to trigger TX_EMPTY condition

    //4. Check INT_STAT for TX_EMPTY bit set twice to check sticky behavior

    //5. Clear TX_EMPTY bit via W1C and confirm deassertion

    //6. Mask TX_EMPTY IRQ in INT_EN 

    //7. Trigger condition again and confirm no IRQ asserted 

    //*? RX_FULL IRQ test

    //1. W1C all IRQs in INT_STAT

    //2. Enable RX_FULL IRQ in INT_EN

    //3. Fill RX FIFO to trigger RX_FULL condition

    //4. Check INT_STAT for RX_FULL bit set twice to check sticky behavior

    //5. Clear RX_FULL bit via W1C and confirm deassertion

    //6. Mask RX_FULL IRQ in INT_EN 

    //7. Trigger condition again and confirm no IRQ asserted 

    //*? RX_OVF IRQ test
    //1. W1C all IRQs in INT_STAT

    //2. Enable RX_OVF IRQ in INT_EN

    //3. Fill RX FIFO to trigger RX_OVF condition

    //4. Check INT_STAT for RX_OVF bit set twice to check sticky behavior

    //5. Clear RX_OVF bit via W1C and confirm deassertion

    //6. Mask RX_OVF IRQ in INT_EN 

    //7. Trigger condition again and confirm no IRQ asserted 


    $display("[INFO] interrupt_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif