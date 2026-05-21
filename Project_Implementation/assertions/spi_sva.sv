// =============================================================================
// abp_sva.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// SVA target module. `tb_top` binds it into `dut_wrapper.u_dut.u_regfile`:
//
//   bind u_wrap.u_dut.u_regfile abp_sva u_sva (.*);
//   (use the instance path of your dut_wrapper instance, here `u_wrap`)
//
// Add assertions for every spec requirement that you can prove without
// modifying the DUT. The scaffold ships two starter assertions so that the
// file compiles and the grader sees at least one SVA active.
// =============================================================================

`ifndef ABP_SVA_SV
`define ABP_SVA_SV 
`timescale 1ns / 1ps

module apb_sva (

    // --- APB bus signals ---
    input wire [31:0] PRDATA,
    input wire [31:0] PWDATA,
    input wire [ 7:0] PADDR,
    input wire        PWRITE,
    input wire        PENABLE,
    input wire        PSEL,
    input wire        PSLVERR,
    input wire        PREADY,

    // --- Clock and reset ---
    input wire PCLK,
    input wire PRESETn,

    // --- FIFO status ---
    input wire [3:0] rx_count,
    input wire [3:0] tx_count,
    input wire       rx_push_valid,
    input wire       tx_push_dropped,
    input wire       rx_full_w,
    input wire       rx_empty_w,
    input wire       tx_full_w,
    input wire       tx_empty_w,
    input wire       tx_empty,
    input wire       busy_in,

    // --- Interrupt signals ---
    input wire       IRQ,
    input wire [4:0] int_stat,
    input wire [4:0] int_en,

    // --- Slave select ---
    input wire [3:0] SS_n,
    input wire [3:0] ss_val,
    input wire [3:0] ss_en,

    // --- Control register fields ---
    input wire [ 1:0] ctrl_width,
    input wire [ 1:0] ctrl_mode,
    input wire [15:0] clk_div,
    input wire [ 7:0] delay_cfg,
    input wire        ctrl_loopback,
    input wire        ctrl_lsb_first,
    input wire        ctrl_mstr,
    input wire        ctrl_en,
    //----extra-----
    input wire        transfer_done_pulse,
    input wire        tx_pop

);

  localparam integer FIFO_DEPTH = 8;
  localparam integer IRQ_RX_OVF = 3;
  localparam integer IRQ_TX_OVF = 2;

  // =========================================================================
  // Combinational (always_comb) assertions — no clock needed
  // =========================================================================
  always_comb begin


    // Spec R2        : All registers return their specified reset values
    //                  after PRESETn asserts.
    if (!PRESETn) begin
      chk_r2_reset_vals :
      assert final (
                ss_en          == 4'h0  &&
                ss_val         == 4'h0  &&
                ctrl_en        == 1'b0  &&
                ctrl_mstr      == 1'b0  &&
                ctrl_lsb_first == 1'b0  &&
                ctrl_loopback  == 1'b0  &&
                ctrl_mode      == 2'b00 &&
                ctrl_width     == 2'b00 &&
                delay_cfg      == 8'h0  &&
                clk_div        == 16'h0 &&
                int_en         == '0    &&
                int_stat       == '0    &&
                busy_in        == 1'h0  &&
                rx_empty_w     == 1'h1  &&
                rx_full_w      == 1'h0  &&
                tx_empty_w     == 1'h1  &&
                tx_empty       == 1'h1  &&
                tx_full_w      == 1'h0);

      cov_r2_reset_vals :
      cover final (
                ss_en          == 4'h0  &&
                ss_val         == 4'h0  &&
                ctrl_en        == 1'b0  &&
                ctrl_mstr      == 1'b0  &&
                ctrl_lsb_first == 1'b0  &&
                ctrl_loopback  == 1'b0  &&
                ctrl_mode      == 2'b00 &&
                ctrl_width     == 2'b00 &&
                delay_cfg      == 8'h0  &&
                clk_div        == 16'h0 &&
                int_en         == '0    &&
                int_stat       == '0    &&
                busy_in        == 1'h0  &&
                rx_empty_w     == 1'h1  &&
                rx_full_w      == 1'h0  &&
                tx_empty_w     == 1'h1  &&
                tx_empty       == 1'h1  &&
                tx_full_w      == 1'h0);
    end




  end

  // =========================================================================
  // Clocked (assert property) assertions
  // =========================================================================


  // Spec R3        : CTRL.EN=0 holds the shifter and FIFOs in reset;
  //                  SCLK stays at CPOL idle; 
  chk_r3_fifo_and_ovf_reset_when_disabled :
  assert property (
        @(posedge PCLK) (!ctrl_en) |-> (
                tx_full_w            == 1'h0 &&
                tx_empty_w           == 1'h1 &&
                tx_empty             == 1'h1 &&
                rx_full_w            == 1'h0 &&
                rx_empty_w           == 1'h1
)
    )
  else
    $error(
        "[FAIL] chk_r3_fifo_and_ovf_reset_when_disabled: FIFO/overflow flags not in reset state while ctrl_en=0"
    );


  // Spec R11       : TX FIFO depth is exactly 8 entries;
  //                  TX_FULL asserts on the 8th pending entry.
  chk_r11_tx_full_at_8_entries :
  assert property (@(posedge PCLK) (tx_count == 8) |-> (tx_full_w == 1'h1))
  else $error("[FAIL] chk_r11_tx_full_at_8_entries: TX_FULL not asserted when tx_count=8");


  // Spec R12       : RX FIFO depth is exactly 8 entries;
  //                  RX_FULL asserts on the 8th received entry.
  chk_r12_rx_full_at_8_entries :
  assert property (@(posedge PCLK) (rx_count == 8) |-> (rx_full_w == 1'h1))
  else $error("[FAIL] chk_r12_rx_full_at_8_entries: RX_FULL not asserted when rx_count=8");


  // Spec R13       : A TX_DATA write while TX_FULL=1 discards the write
  //                  and sets STATUS.TX_OVF and INT_STAT[TX_OVF].
  chk_r13_tx_ovf_set_after_push_dropped :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (tx_push_dropped) |=> (int_stat[IRQ_TX_OVF] == 1'b1)
    )
  else
    $error(
        "[FAIL] chk_r13_tx_ovf_set_after_push_dropped: INT_STAT[TX_OVF] not set one cycle after write dropped into full TX FIFO"
    );


  // Spec R14       : A transfer completing while RX_FULL=1 discards the
  //                  received word and sets STATUS.RX_OVF and INT_STAT[RX_OVF].
  chk_r14_rx_ovf_set_when_push_to_full_fifo :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (rx_push_valid && rx_full_w) |=> (int_stat[IRQ_RX_OVF] == 1'b1)
    )
  else
    $error(
        "[FAIL] chk_r14_rx_ovf_set_when_push_to_full_fifo: INT_STAT[RX_OVF] not set one cycle after push to full RX FIFO"
    );

  // Spec R15       : RX_DATA read while RX_EMPTY returns 0 and does NOT
  //                  raise RX_OVF / INT_STAT[RX_OVF].
  chk_r15_rx_empty_read_returns_zero_no_ovf :
  assert property (
      @(posedge PCLK) disable iff (!PRESETn)
          (rx_empty_w && (PSEL & PENABLE & ~PWRITE) && PADDR == 8'h0C)
          |-> (!$rose(
      int_stat[IRQ_RX_OVF]
  ) && PRDATA == 32'h0))
  else
    $error(
        "[FAIL] chk_r15_rx_empty_read_returns_zero_no_ovf: RX read while empty returned PRDATA=0x%h or raised RX_OVF",
        PRDATA
    );


  // Spec R16       : IRQ = |(INT_STAT & INT_EN) at all times;
  //                  INT_EN does not gate status capture.
  chk_r16_irq_combinational_every_cycle :
  assert property (@(posedge PCLK) disable iff (!PRESETn) IRQ == |(int_stat & int_en))
  else
    $error(
        "[FAIL] chk_r16_irq_combinational_every_cycle: IRQ != |(INT_STAT & INT_EN), IRQ=%b int_stat=%05b int_en=%05b",
        IRQ,
        int_stat,
        int_en
    );



  // INT_STAT_W1C_NORMAL
  // Spec R17 : W1C baseline — on an APB write to 0x1C with no simultaneous
  INT_STAT_W1C_NORMAL :
  assert property (
    @(posedge PCLK) disable iff (!PRESETn)
    (  (PSEL & PENABLE & PWRITE)
     && (PADDR == 8'h1C)
     && !($rose(
      transfer_done_pulse
  )) && !($rose(
      rx_push_valid
  )) && !($rose(
      tx_pop
  ))) |=> (int_stat == ($past(
      int_stat
  ) & ~$past(
      PWDATA[4:0]
  ))))
  else $error("[ASSERTION_ERROR] INT_STAT_W1C_NORMAL: W1C baseline behaviour failed");



  // INT_STAT_W1C_RACE_RX_OVF  (bit 3 — RX overflow)
  // Spec 18: HW event wins — if rx_push_valid rises (RX FIFO write)

  INT_STAT_W1C_RACE_RX_OVF :
  assert property (
    @(posedge PCLK) disable iff (!PRESETn)
    (   (PSEL & PENABLE & PWRITE)
     && (PADDR == 8'h1C)
     && $rose(
      rx_push_valid
  ) && rx_full_w && PWDATA[3]) |=> (int_stat[3] == 1'b1))
  else
    $error(
        "[ASSERTION_ERROR] INT_STAT_W1C_RACE_RX_OVF: bit 3 cleared despite simultaneous RX-overflow HW event"
    );



  // INT_STAT_W1C_RACE_RX_FULL  (bit 1 — RX FIFO full)
  // Spec 18 2 : HW event wins — if rx_push_valid rises and the FIFO is one
  INT_STAT_W1C_RACE_RX_FULL :
  assert property (
    @(posedge PCLK) disable iff (!PRESETn)
    (   (PSEL & PENABLE & PWRITE)
     && (PADDR == 8'h1C)
     && $rose(
      rx_push_valid
  ) && !rx_full_w && (rx_count == FIFO_DEPTH - 1) && PWDATA[1]) |=> (int_stat[1] == 1'b1))
  else
    $error(
        "[ASSERTION_ERROR] INT_STAT_W1C_RACE_RX_FULL: bit 1 cleared despite simultaneous RX-full HW event"
    );

  // INT_STAT_W1C_RACE_TX_EMPTY  (bit 0 — TX FIFO empty)
  // Spec 18 3: HW event wins — if tx_pop rises while only one entry remains

  INT_STAT_W1C_RACE_TX_EMPTY :
  assert property (
    @(posedge PCLK) disable iff (!PRESETn)
    (   (PSEL & PENABLE & PWRITE)
     && (PADDR == 8'h1C)
     && $rose(
      tx_pop
  ) && (tx_count == 1) && PWDATA[0]) |=> (int_stat[0] == 1'b1))
  else
    $error(
        "[ASSERTION_ERROR] INT_STAT_W1C_RACE_TX_EMPTY: bit 0 cleared despite simultaneous TX-empty HW event"
    );



  // INT_STAT_W1C_RACE_XFER_DONE  (bit 4 — transfer done)
  // Spec 18 4: HW event wins — if transfer_done_pulse rises in the same

  INT_STAT_W1C_RACE_XFER_DONE :
  assert property (
    @(posedge PCLK) disable iff (!PRESETn)
    (   (PSEL & PENABLE & PWRITE)
     && (PADDR == 8'h1C)
     && $rose(
      transfer_done_pulse
  ) && PWDATA[4]) |=> (int_stat[4] == 1'b1))
  else
    $error(
        "[ASSERTION_ERROR] INT_STAT_W1C_RACE_XFER_DONE: bit 4 cleared despite simultaneous transfer-done HW event"
    );



  // Spec R20       : SS_n[i] = !SS_EN[i] | SS_VAL[i] combinationally;
  //                  IP never drives SS_n autonomously.
  chk_SS_n :
  assert property (@(posedge PCLK) (SS_n == ~ss_en | ss_val))
  else $error("[FAIL] chk_SS_n: SS_n error");


  // Spec R22       : PREADY is 1 for every addressed access , PSILVER IS 0
  //                  (zero wait states enforced).

  chk_PREADY_PSLVERR :
  assert property (@(posedge PCLK) (PSEL & PENABLE) |-> (PREADY && !PSLVERR))
  else $error("[FAIL] chk_SS_n: SS_n error");



  // Spec R23       : Reserved offsets (0x24 and above) read as 0x0;
  //                  writes to reserved addresses are silently ignored.
  chk_r23_reserved_addr_read_returns_zero :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            ((PADDR >= 8'h24) && (PSEL & PENABLE & ~PWRITE)) |-> (PRDATA == 32'h0)
    )
  else
    $error(
        "[FAIL] chk_r23_reserved_addr_read_returns_zero: reserved offset 0x%02h returned PRDATA=0x%h instead of 0",
        PADDR,
        PRDATA
    );


  // Spec APB       : PSEL=1 for at least 2 PCLK cycles to complete a
  //                  transaction (SETUP phase then ACCESS phase).
  chk_apb_psel_held_across_setup_and_access :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (PSEL && !PENABLE) |=> (PSEL && PENABLE))
  else
    $error(
        "[FAIL] chk_apb_psel_held_across_setup_and_access: PSEL dropped before PENABLE ACCESS phase completed"
    );


  // Spec APB       : PENABLE must only assert while PSEL=1.
  chk_apb_penable_requires_psel :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (PENABLE) |-> (PSEL))
  else
    $error(
        "[FAIL] chk_apb_penable_requires_psel: PENABLE asserted without PSEL, illegal APB state"
    );


  // Spec APB       : PADDR, PWRITE, and PWDATA must remain stable from the
  //                  SETUP phase through the end of the ACCESS phase of the
  //                  same transaction.
  chk_apb_control_signals_stable_during_access :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (PENABLE && PSEL) |-> ($stable(
      PWDATA
  ) && $stable(
      PWRITE
  ) && $stable(
      PADDR
  )))
  else
    $error(
        "[FAIL] chk_apb_control_signals_stable_during_access: PWRITE/PADDR/PWDATA changed during ACCESS phase"
    );


endmodule

`endif  // ABP_SVA_SV
// =============================================================================
// core_sva.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// SVA target module. `tb_top` binds it into `dut_wrapper.u_dut.u_regfile`:
//
//   bind u_wrap.u_dut.u_regfile core_sva u_sva (.*);
//   (use the instance path of your dut_wrapper instance, here `u_wrap`)
//
// Add assertions for every spec requirement that you can prove without
// modifying the DUT. The scaffold ships two starter assertions so that the
// file compiles and the grader sees at least one SVA active.
// =============================================================================

`ifndef CORE_SVA_SV
`define CORE_SVA_SV 
`timescale 1ns / 1ps

module core_sva (

    // --- Clock and reset ---
    input wire PCLK,
    input wire PRESETn,
    input wire sclk_phase,
    // --- SPI physical signals ---
    input wire MISO,
    input wire MOSI,
    input wire SCLK,

    // --- Transfer control ---
    input wire       busy,
    input wire       cfg_en,
    input wire       transfer_done_pulse,
    input wire       tx_empty,
    input wire [1:0] state,

    // --- SPI mode configuration ---
    input wire       cpha,
    input wire       cpol,
    input wire [1:0] cfg_mode,

    // --- SCLK timing ---
    input wire [16:0] sclk_cnt,
    input wire [16:0] half_period,
    input wire [15:0] xfer_div,

    // --- Gap / delay ---
    input wire [8:0] gap_cnt,
    input wire [7:0] cfg_delay,

    // --- Latched transfer parameters ---
    input wire [1:0] xfer_width,
    input wire [1:0] xfer_mode,
    input wire       xfer_lsb_first,

    // --- Static configuration ---
    input wire [ 1:0] cfg_width,
    input wire [15:0] cfg_clk_div,
    input wire        cfg_lsb_first,
    inout wire        cfg_mstr,

    // --- Slave select ---
    input wire [3:0] ss_n_drive,

    // --- Loopback ---
    input wire miso_eff,
    input wire cfg_loopback
);

  // --- FSM state encoding ---
  localparam S_IDLE = 2'd0;
  localparam S_SHIFT = 2'd1;
  localparam S_FINISH = 2'd2;
  localparam S_GAP = 2'd3;

  // =========================================================================
  // Internal helper signals
  // =========================================================================
  logic leading;
  logic sample_edge;
  logic launch_edge;

  assign leading     = ~sclk_phase;
  assign sample_edge = (cpha == 1'b0) ? leading : ~leading;
  assign launch_edge = sample_edge;

  // =========================================================================
  // Clocked (assert property) assertions
  // =========================================================================

  // Spec R3        : CTRL.EN=0 holds the shifter and FIFOs in reset;
  //                  BUSY must be 0 while the block is disabled.
  chk_r3_busy_deasserted_when_disabled :
  assert property (@(posedge PCLK) (!cfg_en) |-> (busy == 0))
  else $error("[FAIL] chk_r3_busy_deasserted_when_disabled: busy=%b asserted while cfg_en=0", busy);

  // Assertion name : chk_r3_sclk_idle_at_cpol_when_disabled
  // Spec R3        : CTRL.EN=0 — SCLK stays at the CPOL idle level;
  //                  it must not toggle while the block is disabled.
  chk_r3_sclk_idle_at_cpol_when_disabled :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (!cfg_en) |=> (SCLK == $past(
      cfg_mode[1]
  )))
  else
    $error(
        "[FAIL] chk_r3_sclk_idle_at_cpol_when_disabled: SCLK=%b not at CPOL idle=%b while cfg_en=0",
        SCLK,
        cfg_mode[1]
    );


  // Spec R4        : For each SPI mode, SCLK idle polarity matches CPOL
  //                  before transfers (S_IDLE state).
  chk_r4_sclk_matches_cpol_in_idle :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (state == S_IDLE && cfg_en ) |=> (SCLK == $past(
      cfg_mode[1]
  )))
  else
    $error(
        "[FAIL] chk_r4_sclk_matches_cpol_in_idle: SCLK=%b does not match CPOL=%b in IDLE state",
        SCLK,
        cfg_mode[1]
    );


  // Spec R4        : For each SPI mode, SCLK idle polarity matches CPOL
  //                  after transfers (on transfer_done_pulse).
  chk_r4_sclk_returns_to_cpol_after_finish :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (transfer_done_pulse) |-> (SCLK == $past(
      cpol
  )))
  else
    $error(
        "[FAIL] chk_r4_sclk_returns_to_cpol_after_finish: SCLK=%b does not match CPOL=%b after transfer done",
        SCLK,
        cpol
    );

  // Assertion name : chk_r4_sclk_matches_cpol_in_gap
  // Spec R4        : For each SPI mode, SCLK idle polarity matches CPOL
  //                  between consecutive transfers (S_GAP state).
  chk_r4_sclk_matches_cpol_in_gap :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (state == S_GAP) |=> (SCLK == $past(
      cpol
  )))
  else
    $error(
        "[FAIL] chk_r4_sclk_matches_cpol_in_gap: SCLK=%b does not match CPOL=%b between transfers (GAP)",
        SCLK,
        cpol
    );


  // Spec R5        : For each SPI mode, MOSI is stable across the sample
  //                  edge defined by CPOL/CPHA (WIRE-STABILITY before edge).
  chk_r5_mosi_stable_at_before_sample_edge :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (state == S_SHIFT && (($rose(
      SCLK
  ) && cpha == cpol) || ($fell(
      SCLK
  ) && cpha != cpol))) |-> ($stable(
      MOSI
  )))
  else
    $error(
        "[FAIL] chk_r5_mosi_stable_at_sample_edge: MOSI=%b changed on sample-edge cycle, SCLK=%b",
        MOSI,
        SCLK
    );


  // Spec R5        : MOSI changes on the launch edge and must be stable
  //                  for at least 1 PCLK after the launch edge.
  chk_r5_mosi_stable_no_launch_edge :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        ((!(sclk_cnt == half_period - 1) && launch_edge) && state == S_SHIFT) |=> ($stable(
      MOSI
  )))
  else
    $error(
        "[FAIL] chk_r5_mosi_stable_after_launch_edge: MOSI=%b changed within 1 PCLK after launch edge, SCLK=%b",
        MOSI,
        SCLK
    );


  // Spec R5        : MOSI must remain stable for at least 1 PCLK after
  //                  the sample edge (WIRE-STABILITY after edge).
  chk_r5_mosi_stable_after_sample_edge :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (state == S_SHIFT && (sclk_cnt == half_period - 1) && sample_edge) |=> ($stable(
      MOSI
  )))
  else
    $error(
        "[FAIL] chk_r5_mosi_stable_after_sample_edge: MOSI=%b changed within 1 PCLK after sample edge, SCLK=%b",
        MOSI,
        SCLK
    );


  // Spec R7        : A transfer lasts exactly WIDTH SCLK cycles; BUSY=1
  //                  throughout all active states (SHIFT, FINISH, GAP).
  chk_r7_busy_asserted_during_transfer_states :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (state == S_GAP || state == S_FINISH || state == S_SHIFT) |-> (busy == 1'b1)
    )
  else
    $error(
        "[FAIL] chk_r7_busy_asserted_during_transfer_states: busy=0 during active transfer state=%0d",
        state
    );


  // Spec R7        : BUSY deasserts one PCLK after the last sample edge
  //                  when no delay is pending and TX FIFO is empty.
  chk_r7_busy_deasserts_after_transfer_done :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (transfer_done_pulse && ($past(
      cfg_delay
  ) == 8'h0 || $past(
      tx_empty
  ))) |-> (busy == 1'b0))
  else
    $error(
        "[FAIL] chk_r7_busy_deasserts_after_transfer_done: busy did not deassert one PCLK after transfer_done_pulse"
    );


  // Spec R8 + R24  : SCLK frequency = PCLK / (2 x (DIV+1)) for all DIV in
  //                  [0, 65535]; CLK_DIV=0 yields PCLK/2 (no divide-by-zero).
  chk_r8_r24_half_period_equals_div_plus_one :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (half_period == {1'b0, xfer_div} + 17'd1))
  else
    $error(
        "[FAIL] chk_r8_r24_half_period_equals_div_plus_one: half_period=%0d != xfer_div+1=%0d",
        half_period,
        xfer_div + 1
    );


  // Spec R8        : SCLK toggles exactly when sclk_cnt reaches
  //                  half_period-1 in the SHIFT state.
  chk_r8_sclk_toggles_at_half_period :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (sclk_cnt == (half_period - 1) && state == S_SHIFT) |=> $changed(
      SCLK
  ))
  else
    $error(
        "[FAIL] chk_r8_sclk_toggles_at_half_period: SCLK did not toggle at half_period=%0d, sclk_cnt=%0d, xfer_div=%0d",
        half_period,
        sclk_cnt,
        xfer_div
    );


  // Spec R8        : SCLK must remain stable while sclk_cnt has not yet
  //                  reached half_period-1 in the SHIFT state.
  chk_r8_sclk_stable_before_half_period :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (sclk_cnt < (half_period - 1) && state == S_SHIFT) |=> $stable(
      SCLK
  ))
  else
    $error(
        "[FAIL] chk_r8_sclk_stable_before_half_period: SCLK toggled early before half_period=%0d, sclk_cnt=%0d, xfer_div=%0d",
        half_period,
        sclk_cnt,
        xfer_div
    );


  // Spec R19       : Loopback mode (CTRL.LOOPBACK=1) routes MOSI internally
  //                  to the RX shift register; external MISO is ignored.
  chk_r19_loopback_miso_equals_mosi :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (cfg_loopback) |-> (miso_eff == MOSI))
  else
    $error(
        "[FAIL] chk_r19_loopback_miso_equals_mosi: miso_eff=%b != MOSI=%b while cfg_loopback=1",
        miso_eff,
        MOSI
    );

  // Spec R21       : DELAY SCLK half-cycles of idle are inserted between
  //                  consecutive transfers when DELAY > 0 and another word
  //                  is queued (S_GAP must follow S_FINISH).
  chk_r21_gap_state_inserted_when_delay_nonzero :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (!tx_empty && sclk_cnt == (half_period - 1) && (cfg_delay > 0) && state == S_FINISH)
        |=> (state == S_GAP)[*1:$]
    )
  else
    $error(
        "[FAIL] chk_r21_gap_state_inserted_when_delay_nonzero: GAP state not entered after FINISH, cfg_delay=%0d gap_cnt=%0d",
        cfg_delay,
        gap_cnt
    );


  // Spec R25       : DIV, MODE, WIDTH, LSB_FIRST are sampled at transfer
  //                  start (S_IDLE -> active) and held for that transfer.
  chk_r25_xfer_params_latched_at_transfer_start :
  assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (!tx_empty && cfg_en && cfg_mstr && (ss_n_drive != 4'hF) && state == S_IDLE)
        |=> (xfer_width == $past(
      cfg_width
  ) && xfer_div == $past(
      cfg_clk_div
  ) && xfer_lsb_first == $past(
      cfg_lsb_first
  ) && xfer_mode == $past(
      cfg_mode
  )))
  else
    $error(
        "[FAIL] chk_r25_xfer_params_latched_at_transfer_start: xfer params not latched from cfg at start of transfer"
    );


  // Spec R25       : DIV, MODE, WIDTH, LSB_FIRST are held stable for the
  //                  entire duration of the transfer (while BUSY=1).
  chk_r25_xfer_params_stable_during_transfer :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (busy) |=> $stable(
      xfer_width
  ) && $stable(
      xfer_div
  ) && $stable(
      xfer_lsb_first
  ) && $stable(
      xfer_mode
  ))
  else
    $error(
        "[FAIL] chk_r25_xfer_params_stable_during_transfer: xfer params changed during active transfer while busy=1"
    );


  // Spec SPI       : SS_n held asserted for the entire WIDTH-bit transfer
  //                  (ss_n_drive != 4'hF means at least one slave selected).
  chk_spi_ss_n_held_during_transfer :
  assert property (@(posedge PCLK) disable iff (!PRESETn) (busy) |-> (ss_n_drive != 4'hF))
  else
    $error(
        "[FAIL] chk_spi_ss_n_held_during_transfer: SS_n deasserted (ss_n_drive=0x%h) while busy=1 during transfer",
        ss_n_drive
    );

endmodule

`endif  // CORE_SVA_SV
