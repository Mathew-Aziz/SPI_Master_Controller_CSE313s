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

    bit [31:0] rd = 0;

    tb_top.bfm_mode      = 2'b00;  // CPOL=0 CPHA=0
    tb_top.bfm_pattern   = 8'hA5;
    tb_top.bfm_width     = 2'b00;  // 8-bit
    tb_top.bfm_lsb_first = 1'b0;  // MSB-first
    tb_top.bfm_miso_word = 32'h0000_00A5;  // matches bfm_pattern

    tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0003);  // EN, MSTR
    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'h0000_0004);  // divide /4


    coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00));

    // TODO:
    // For each interrupt source:
    // - cause event
    // - confirm INT_STAT sticky
    // - confirm mask gates IRQ only (R16)
    // - clear via W1C (R17)
    // - W1C race (R18)

  //*======================TX_OVF IRQ test=========================

    //1. W1C all IRQs in INT_STAT
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F);  // Clear all IRQs

    //2. Enable TX_OVF IRQ in INT_EN
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0004);  // Enable only TX_OVF
    //3. Fill TX FIFO to trigger TX_OVF condition
    for (int i = 0; i < 12; i++) begin
      tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'(i));
      if(tb_top.spi.cb_mon.irq == 1'b1) break;
    end
    //4. Check INT_STAT for TX_OVF bit set twice to check sticky behavior
    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0100, rd, 8'b0000_0100);  
    end
    
    if(tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test", "TX_OVF IRQ not asserted when TX_OVF condition met");
  
    //5. Clear TX_OVF bit via W1C and confirm deassertion
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0004);

    //6. Mask TX_OVF IRQ in INT_EN 
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000); 

    //drain the FIFO to reset state for next test
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);  
      repeat (500) begin
        tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
        if (rd[0] == 1'b0) break;
      end
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

    //7. Trigger condition again and confirm no IRQ asserted
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F); 
    for (int i = 0; i <= 8; i++) begin
      tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'(i));
      if(tb_top.spi.cb_mon.irq == 1'b1)begin
        ref_model.checker_error("Interrupt test", "TX_OVF IRQ is asserted despite being masked");
        break;
      end 
    end

    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0100, rd, 8'b0000_0100);
    end

    //W1C Race (deterministic): backdoor-clear then trigger TX push
    // Clear INT_STAT TX_OVF bit via backdoor so the subsequent APB TX push
    // is sampled against the cleared value on the same PCLK edge.
    tb_top.u_wrap.u_dut.u_regfile.int_stat = tb_top.u_wrap.u_dut.u_regfile.int_stat & ~5'b00100;
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hDEAD_BEEF);
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT", 8'b0000_0100, rd, 8'b0000_0100);

    //drain the FIFO to reset state for next test
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);  
      repeat (500) begin
        tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
        if (rd[0] == 1'b0) break;
      end
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

//*======================TRANSFER_DONE IRQ test=========================
    //1. W1C all IRQs in INT_STAT
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F); 
    
    //2. Enable TRANSFER_DONE IRQ in INT_EN
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0010);
    
    //3. make a transfer to trigger TRANSFER_DONE
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00FF);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001); 

    // Wait for transfer to complete (BUSY goes LOW)
    repeat (500) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[0] == 1'b0) break;  // BUSY bit goes low
    end
    if(tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test", "TRANSFER_DONE IRQ not asserted after transfer completion");

    //4. Check INT_STAT for TRANSFER_DONE bit set twice to check sticky behavior
    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT_TRANSFER_DONE", 8'b0001_0000, rd, 8'b0001_0000);
    end

    if(tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test", "TRANSFER_DONE IRQ not asserted after transfer completion");

    //5. Clear TRANSFER_DONE bit via W1C and confirm deassertion
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0010);
    if(tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "TRANSFER_DONE IRQ not deasserted after W1C clear");

    //6. Mask TRANSFER_DONE IRQ in INT_EN 
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);

    //7. Trigger condition again and confirm no IRQ asserted
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F);
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00AA);
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

    repeat (500) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[0] == 1'b0) break;
    end

    if(tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "TRANSFER_DONE IRQ asserted despite being masked");

    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT_TRANSFER_DONE_masked", 8'b0001_0000, rd, 8'b0001_0000);
    end

    //W1C Race (deterministic): backdoor-clear then trigger transfer
    // Clear TRANSFER_DONE bit via backdoor before starting new transfer
    tb_top.u_wrap.u_dut.u_regfile.int_stat = tb_top.u_wrap.u_dut.u_regfile.int_stat & ~5'b10000;
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hDEAD_BEEF);

    repeat (500) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[0] == 1'b0) break;
    end
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT_TRANSFER_DONE_race", 8'b0001_0000, rd, 8'b0001_0000);

    //deassert SS to reset state for next test
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);
    
//==================Tx_EMPTY IRQ test=============================

    //1. W1C all IRQs in INT_STAT
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F); 
   
    //2. Enable TX_EMPTY IRQ in INT_EN
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0001);
   
    //3. make a transfer to trigger TX_EMPTY condition
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00FF);
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT", 8'b0000_0000, rd, 8'b0000_0001);

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001); 
     
    repeat (500) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[0] == 1'b0) break;
    end

    if(tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test", "TX_EMPTY IRQ not asserted when TX_EMPTY condition met");

    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0001, rd, 8'b0000_0001);
    end
    //deassert SS to reset state
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000); 
    
    //4. Clear TX_EMPTY bit via W1C and confirm deassertion
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F); 
    if(tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "TX_EMPTY IRQ not deasserted after W1C clear");

    //5. Mask TX_EMPTY IRQ in INT_EN 
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);

    //6. Trigger condition again and confirm no IRQ asserted 
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00FF);
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT", 8'b0000_0000, rd, 8'b0000_0001);

    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001); 
     
    repeat (500) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[0] == 1'b0) break;
    end

    if(tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "TX_EMPTY IRQ asserted despite being masked");

    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0001, rd, 8'b0000_0001);
    end

    //!W1C Race (deterministic): backdoor-clear then trigger TX push (Not Sure of Implmentation)
    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hDEAD_BEEF);

    repeat (500) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[0] == 1'b0)begin
        tb_top.u_wrap.u_dut.u_regfile.int_stat = tb_top.u_wrap.u_dut.u_regfile.int_stat & ~5'b00001;
        break;
      end 
    end
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT", 8'b0000_0001, rd, 8'b0000_0001);

    //deassert SS to reset state for next test
    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);
    
//================== RX_FULL IRQ test ====================

    //1. W1C all IRQs in INT_STAT
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F); 
  
    //2. Enable RX_FULL IRQ in INT_EN
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0002);
    
    //3. Fill RX FIFO to trigger RX_FULL condition
    //Empty RX FIFO by reading until empty
    repeat (20) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[4] == 1'b1) break;  // RX_EMPTY=1 means empty

      tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    end
    
    for (int i = 0; i < 8; i++)
      tb_top.u_wrap.u_dut.u_regfile.rx_mem[i] = 32'h1000_0000 + i;
  
    tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h8;
    //4. Check IRQ and INT_STAT for RX_FULL bit set twice to check sticky behavior
    if(tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test", "RX_FULL IRQ not asserted when RX_FULL condition met");

    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0010, rd, 8'b0000_0010);
    end

    //5. Disable RX_FULL bit via INT_EN and confirm deassertion
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000); 
    if(tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "RX_FULL IRQ not deasserted after masking in INT_EN");
    
    //6. W1C RX_FULL bit via INT_STAT
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0002); 
    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0002);
    if(tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "RX_FULL IRQ asserted after W1C clear");

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT", 8'b0000_0000, rd, 8'b0000_0010);
    
    //7. Race W1C clear vs new event
    tb_top.u_wrap.u_dut.u_regfile.int_stat = tb_top.u_wrap.u_dut.u_regfile.int_stat & ~5'b00010;
    tb_top.u_wrap.u_dut.u_regfile.rx_mem[7] = 32'h2000_0007;
    tb_top.u_wrap.u_dut.u_regfile.rx_wp++;
       

    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT", 8'b0000_0010, rd, 8'b0000_0010);

    // Empty RX FIFO by reading until empty for next test
    repeat (20) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[4] == 1'b1) break;  // RX_EMPTY=1 means empty

      tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    end

    //================== RX_OVF IRQ test ====================
    //1. W1C all IRQs in INT_STAT
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F); 

    //2. Enable RX_OVF IRQ in INT_EN
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0008);
    
    //3. Fill RX FIFO to trigger RX_OVF condition
    //Empty RX FIFO by reading until empty
    repeat (20) begin
      tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
      if (rd[4] == 1'b1) break;  // RX_EMPTY=1 means empty

      tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
    end

     for (int i = 0; i <= 8; i++)
      tb_top.u_wrap.u_dut.u_regfile.rx_mem[i] = 32'h1000_0000 + i;
  
    tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h9;
    //4. Check INT_STAT for RX_OVF bit set twice to check sticky behavior
    
    if (tb_top.spi.cb_mon.irq != 1'b1)
      ref_model.checker_error("Interrupt test", "RX_OVF IRQ not asserted when RX FIFO overflows");

    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT_RX_OVF", 8'b0000_1000, rd, 8'b0000_1000);
    end
    //5. Clear RX_OVF bit via W1C and confirm deassertion
    tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0008);  // W1C RX_OVF

    // Verify IRQ is deasserted
    if (tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "RX_OVF IRQ not deasserted after W1C clear");

    //6. Mask RX_OVF IRQ in INT_EN 
    tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000);
  
    //7. Trigger condition again and confirm no IRQ asserted 
    tb_top.u_wrap.u_dut.u_regfile.rx_mem[8] = 32'hBEEF_DEAD;  // Overflow data
    tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h8;

    repeat(2)begin
      tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
      ref_model.check_reg_masked("INT_STAT_RX_OVF_masked", 8'b0000_1000, rd, 8'b0000_1000);  
    end

    if (tb_top.spi.cb_mon.irq == 1'b1)
      ref_model.checker_error("Interrupt test", "RX_OVF IRQ asserted despite being masked");

    //8. Race W1C clear vs new event
    tb_top.u_wrap.u_dut.u_regfile.int_stat = tb_top.u_wrap.u_dut.u_regfile.int_stat & ~5'b01000;
    tb_top.u_wrap.u_dut.u_regfile.rx_mem[8] = 32'h2000_0007;
    tb_top.u_wrap.u_dut.u_regfile.rx_wp = 4'h8;

    // Verify RX_OVF is set again due to the new event
    tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd);
    ref_model.check_reg_masked("INT_STAT_RX_OVF_race", 8'b0000_1000, rd, 8'b0000_1000);

  endtask

endclass

`endif