// =============================================================================
// spi_sva.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// SVA target module. `tb_top` binds it into `dut_wrapper.u_dut.u_regfile`:
//
//   bind u_wrap.u_dut.u_regfile spi_sva u_sva (.*);
//   (use the instance path of your dut_wrapper instance, here `u_wrap`)
//
// Add assertions for every spec requirement that you can prove without
// modifying the DUT. The scaffold ships two starter assertions so that the
// file compiles and the grader sees at least one SVA active.
// =============================================================================

`ifndef SPI_SVA_SV
`define SPI_SVA_SV
`timescale 1ns/1ps

module spi_sva (
    input wire        PCLK,
    input wire        PRESETn,
    input wire        ctrl_en,
    input wire [4:0]  int_stat,
    input wire        IRQ,
    input wire [3:0]  SS_n,
    input wire [3:0]  ss_en,
    input wire [3:0]  ss_val,
    input wire        ctrl_mstr,
    input wire [1:0]  ctrl_mode,
    input wire        ctrl_lsb_first,
    input wire        ctrl_loopback,
    input wire [1:0]  ctrl_width,
    input wire [15:0] clk_div,
    input wire [7:0]  delay_cfg,
    input wire [4:0]  int_en,
    input wire        rx_empty_w,
    input wire        rx_full_w,
    input wire        tx_empty_w,
    input wire        tx_empty,
    input wire        tx_full_w,
    input wire [3:0]  tx_count,
    input wire [3:0]  rx_count,
    input wire        busy_in,
    input wire        PSLVERR,
    input wire        PREADY,
    input wire        PSEL,
    input wire        PENABLE,
    input wire        PWRITE,
    input wire [7:0]  PADDR,
    input wire [31:0] PWDATA,
    input wire [31:0] PRDATA,
    input wire        tx_push_dropped,
    input wire        rx_push_valid
);

    localparam integer IRQ_TX_OVF = 2;
    localparam integer IRQ_RX_OVF = 3;


    always_comb begin
//R2 All registers return their specified reset values after PRESETn asserts.
        if (!PRESETn) begin
            chk_reset_vals: assert final (
                ctrl_en        == 1'b0 &&
                ctrl_mstr      == 1'b0 &&
                ctrl_mode      == 2'b00 &&
                ctrl_lsb_first == 1'b0 &&
                ctrl_loopback  == 1'b0 &&
                ctrl_width     == 2'b00 &&
                clk_div        == 16'h0 &&
                ss_en          == 4'h0  &&
                ss_val         == 4'h0  &&
                int_en         == '0    &&
                int_stat       == '0    &&
                delay_cfg      == 8'h0  &&
                rx_empty_w     == 1'h1  &&
                rx_full_w      == 1'h0  &&
                tx_empty_w     == 1'h1  &&
                tx_empty       == 1'h1  &&
                tx_full_w      == 1'h0  &&
                busy_in        == 1'h0);

            cov_reset_vals: cover final (
                ctrl_en        == 1'b0 &&
                ctrl_mstr      == 1'b0 &&
                ctrl_mode      == 2'b00 &&
                ctrl_lsb_first == 1'b0 &&
                ctrl_loopback  == 1'b0 &&
                ctrl_width     == 2'b00 &&
                clk_div        == 16'h0 &&
                ss_en          == 4'h0  &&
                ss_val         == 4'h0  &&
                int_en         == '0    &&
                int_stat       == '0    &&
                delay_cfg      == 8'h0  &&
                rx_empty_w     == 1'h1  &&
                rx_full_w      == 1'h0  &&
                tx_empty_w     == 1'h1  &&
                tx_empty       == 1'h1  &&
                tx_full_w      == 1'h0  &&
                busy_in        == 1'h0);
        end
       //R3
        if (!ctrl_en) begin
            chk_en0_fifo_idle: assert final (
                SS_n                 == '1   &&
                int_stat[IRQ_RX_OVF] == 1'h0 &&
                int_stat[IRQ_TX_OVF] == 1'h0 &&
                rx_empty_w           == 1'h1  &&
                rx_full_w            == 1'h0  &&
                tx_empty_w           == 1'h1  &&
                tx_empty             == 1'h1  &&
                tx_full_w            == 1'h0);

            cov_en0_fifo_idle: cover final (
                SS_n                 == '1   &&
                int_stat[IRQ_RX_OVF] == 1'h0 &&
                int_stat[IRQ_TX_OVF] == 1'h0 &&
                rx_empty_w           == 1'h1  &&
                rx_full_w            == 1'h0  &&
                tx_empty_w           == 1'h1  &&
                tx_empty             == 1'h1  &&
                tx_full_w            == 1'h0);
        end
        //R11
        // TX FIFO capacity is exactly 8 words; TX_FULL flag must assert
        if (tx_count == 8) begin
            chk_tx_fifo_full: assert final (tx_full_w == 1'h1);
            cov_tx_fifo_full: cover  final (tx_full_w == 1'h1);
        end
        //R12
        // RX FIFO capacity is exactly 8 words; RX_FULL flag must assert
        if (rx_count == 8) begin
            chk_rx_fifo_full: assert final (rx_full_w == 1'h1);
            cov_rx_fifo_full: cover  final (rx_full_w == 1'h1);
        end

       
       
       //R20
    // SS_n[i] = !SS_EN[i] | SS_VAL[i]; 
        chk_ss_comb_drive: assert final (SS_n == ~ss_en | ss_val);
        cov_ss_comb_drive: cover  final (SS_n == ~ss_en | ss_val);
         //R22
        // PSLVERR is tied low.
        chk_no_apb_slverr: assert final (PSLVERR == 0);
        cov_no_apb_slverr: cover  final (PSLVERR == 0);
          //R22
        // PREADY must be high for every access phase (PSEL & PENABLE).
        if (PSEL & PENABLE) begin
            chk_zero_wait_state: assert final (PREADY == 1);
            cov_zero_wait_state: cover  final (PREADY == 1);
        end

    end



   // When CTRL.EN deasserts, aggregate IRQ MUST be 0 within 1 cycle
    // (student should extend with the exact spec wording from R19)
    a_irq_off_when_disabled : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (!ctrl_en) |-> ##[0:1] (IRQ == 1'b0 || int_stat != 0)
    ) else $error("[ASSERTION_ERROR] a_irq_off_when_disabled");

    //R13
    // A write to TX_DATA when the TX FIFO is already full must be silently
    // dropped AND must set the TX_OVF sticky bit in INT_STAT on the next cycle.
    chk_tx_ovf_set_on_drop : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (tx_push_dropped) |=> (int_stat[IRQ_TX_OVF] == 1'b1)
    ) else $error("[FAIL] chk_tx_ovf_set_on_drop: TX_OVF not set after write dropped into full TX FIFO");
     
     //R14
    // A completed transfer arriving when the RX FIFO is full must discard
    // the received word AND set the RX_OVF sticky bit on the next cycle.
    chk_rx_ovf_set_when_full : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (rx_push_valid && rx_full_w) |=> (int_stat[IRQ_RX_OVF] == 1'b1)
    ) else $error("[FAIL] chk_rx_ovf_set_when_full: RX_OVF not set after push to full RX FIFO");
     
     //R15
    // Reading RX_DATA while RX_EMPTY must return 0x0 and must not
    // set the RX_OVF overflow flag.
    chk_rx_empty_read_safe : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (rx_empty_w && PADDR == 8'h0C && (PSEL & PENABLE & ~PWRITE))
            |-> (PRDATA == 0 && int_stat[IRQ_RX_OVF] == 1'b0)
    ) else $error("[FAIL] chk_rx_empty_read_safe: empty RX read returned non-zero data or set RX_OVF");

    //R16
    // IRQ output must equal the bitwise OR of (INT_STAT & INT_EN) at every
    // clock edge; INT_EN masks delivery but never blocks status capture.
    chk_irq_equals_masked_stat : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            IRQ == |(int_stat & int_en)
    ) else $error("[FAIL] chk_irq_equals_masked_stat: IRQ does not equal |(INT_STAT & INT_EN)");

     //R17
    // INT_STAT implements Write-1-to-Clear semantics: writing a 1 to any bit
    // must clear that bit on the following clock cycle.
    chk_int_stat_w1c_clears : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            ((PSEL & PENABLE & PWRITE) && (PADDR == 8'h1C) && (PWDATA[4:0] != 5'h0))
            |=> ((int_stat & ($past(PWDATA[4:0]) == 5'h0)))
    ) else $error("[FAIL] chk_int_stat_w1c_clears: INT_STAT bits not cleared by W1C write");
    
    //R17
    // Writing 0 to INT_STAT must have no effect; the register must retain
    // its current value on the following clock cycle.
    chk_int_stat_w0_no_effect : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            ((PSEL & PENABLE & PWRITE) && (PADDR == 8'h1C) && (PWDATA[4:0] == 5'h0))
            |=> ((int_stat == $past(int_stat)))
    ) else $error("[FAIL] chk_int_stat_w0_no_effect: INT_STAT changed unexpectedly after writing 0");


    //R18 
    // W1C race for TX_OVF: if a hardware overflow event and a software clear
    // of that bit coincide on the same clock edge, the hardware set must win.
    chk_w1c_race_tx_ovf_wins : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            ((PSEL & PENABLE & PWRITE) && (PADDR == 8'h1C) && PWDATA[2] && $rose(tx_push_dropped))
            |=> (int_stat[2] == 1'b1)
    ) else $error("[FAIL] chk_w1c_race_tx_ovf_wins: TX_OVF cleared despite simultaneous HW set event");


     //R18 
    // W1C race for RX_OVF: if a hardware overflow event and a software clear
    // of that bit coincide on the same clock edge, the hardware set must win.
    chk_w1c_race_rx_ovf_wins : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            ((PSEL & PENABLE & PWRITE) && (PADDR == 8'h1C) && PWDATA[3] && $rose(rx_push_valid) && rx_full_w)
            |=> (int_stat[3] == 1'b1)
    ) else $error("[FAIL] chk_w1c_race_rx_ovf_wins: RX_OVF cleared despite simultaneous HW set event");


    //R23
    // Any read from a reserved address (0x24 and above) must return 0x0;
    // writes to reserved addresses are silently ignored.
    chk_reserved_addr_reads_zero : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            ((PSEL & PENABLE & ~PWRITE) && (PADDR >= 8'h24)) |-> (PRDATA == 32'h0)
    ) else $error("[FAIL] chk_reserved_addr_reads_zero: reserved offset 0x%02h returned PRDATA=0x%h", PADDR, PRDATA);

    
    // APB protocol: PSEL must remain asserted across both the SETUP and
    // ACCESS phases — it takes at least 2 PCLK cycles to complete a transfer.
    chk_apb_psel_held : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (PSEL && !PENABLE) |=> (PSEL && PENABLE)
    ) else $error("[FAIL] chk_apb_psel_held: PSEL dropped before PENABLE phase completed");

    // APB protocol: PENABLE is only valid during the ACCESS phase, which
    // requires PSEL to already be asserted.
    chk_apb_penable_needs_psel : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (PENABLE) |-> (PSEL)
    ) else $error("[FAIL] chk_apb_penable_needs_psel: PENABLE asserted without PSEL");

    // APB protocol: PADDR, PWRITE, and PWDATA must remain stable from the
    // SETUP phase through the end of the ACCESS phase of the same transfer.
    chk_apb_ctrl_stable : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (PSEL && PENABLE) |-> ($stable(PADDR) && $stable(PWRITE) && $stable(PWDATA))
    ) else $error("[FAIL] chk_apb_ctrl_stable: PADDR/PWRITE/PWDATA changed during ACCESS phase");


endmodule

`endif // SPI_SVA_SV