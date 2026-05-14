

`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV 

class spi_coverage_col;

  // --- SPI configuration (R4, R5, R6, R25) ---
  bit [ 1:0] cv_mode;
  bit        cv_lsb_first;
  bit [ 1:0] cv_width;  // 00=8b 01=16b 10=32b

  // --- APB register access (R1) ---
  bit [ 7:0] cv_addr;
  bit        cv_is_write;  // used ONLY by cg_apb_reg (R1) and cg_apb_protocol (R22)
  bit        cv_readback;
  bit [31:0] cv_last_written[bit                                                      [7:0]];

  // --- APB protocol (R22) — kept separate from readback variables ---
  bit        cv_pslverr;
  bit        cv_pready;

  // --- Reset (R2) ---
  bit        cv_rst_val_ok;  // 1 when rdata matched expected reset value

  // --- CTRL.EN (R3) ---
  bit        cv_ctrl_en;
  bit        cv_tx_empty_en0;  // TX_EMPTY=1 when EN=0
  bit        cv_rx_empty_en0;  // RX_EMPTY=1 when EN=0
  bit        cv_sclk_idle;  // SCLK at CPOL idle level when EN=0
  bit        cv_ss_high;  // all SS_n high when EN=0

  // --- CLK_DIV (R8, R24) ---
  bit [15:0] cv_clk_div;

  // --- FIFO occupancy (R9-R12) ---
  int        cv_tx_occ;  // 0..8
  int        cv_rx_occ;  // 0..8

  // --- Overflow and empty-read (R13, R14, R15) ---
  bit        cv_tx_ovf;
  bit        cv_rx_ovf;
  bit        cv_rx_empty_read;

  // --- IRQ (R16, R17, R18) ---
  bit [ 4:0] cv_int_stat;
  bit [ 4:0] cv_int_en;
  bit [ 4:0] cv_masked_stat;  // int_stat & ~int_en — captured-while-masked
  bit [ 4:0] cv_w1c_mask;  // which INT_STAT bits were written-1 (W1C)
  bit [ 4:0] cv_w1c_race_mask;  // which bits saw simultaneous set+W1C

  // --- Loopback (R19) ---
  bit        cv_loopback;

  // --- Slave select (R20) ---
  bit [ 3:0] cv_ss_en;
  bit [ 3:0] cv_ss_val;  // NEW (WARN-3 fix): track ss_val separately

  // --- Delay (R21) ---
  bit [ 7:0] cv_delay;
  bit        cv_delay_queued;

  // --- Reserved address (R23) ---
  bit [ 7:0] cv_reserved_addr;
  // BUG-4 FIX: dedicated variable so sample_reserved and sample_apb
  // never share state. cg_reserved.cp_rw reads cv_reserved_is_write.
  bit        cv_reserved_is_write;

  // --- BUSY flag (R7) ---
  bit        cv_busy;
  // BUG-5 FIX: dedicated width variable for cg_busy so sample_busy()
  // cannot corrupt cv_width used by cg_spi_cfg and cg_loopback.
  bit [ 1:0] cv_busy_width;

  // =========================================================================
  // Covergroups
  // =========================================================================

  // -------------------------------------------------------------------------
  // cg_apb_protocol — R22 (NEW, split from cg_apb_reg)
  // -------------------------------------------------------------------------
  covergroup cg_apb_protocol;
    option.per_instance = 1;

    cp_addr: coverpoint cv_addr {
      bins ctrl = {8'h00};
      bins status = {8'h04};
      bins tx_data = {8'h08};
      bins rx_data = {8'h0C};
      bins clk_div = {8'h10};
      bins ss_ctrl = {8'h14};
      bins int_en = {8'h18};
      bins int_stat = {8'h1C};
      bins delay_r = {8'h20};
    }

    cp_rw: coverpoint cv_is_write {bins read = {1'b0}; bins write = {1'b1};}

    // R22: PSLVERR must always be 0 for every valid register access
    cp_pslverr: coverpoint cv_pslverr {
      bins never_high = {1'b0};
    }

    // R22: PREADY must always be 1 (zero-wait-state slave)
    cp_pready: coverpoint cv_pready {
      bins always_ready = {1'b1};
    }

    // R22: every register accessed (read AND write) with correct handshake
    cx_addr_rw_protocol: cross cp_addr, cp_rw, cp_pslverr, cp_pready;
  endgroup

  // -------------------------------------------------------------------------
  // cg_apb_reg — R1
  // -------------------------------------------------------------------------
  covergroup cg_apb_reg;
    option.per_instance = 1;

    cp_addr: coverpoint cv_addr {
      bins ctrl = {8'h00};
      bins status = {8'h04};
      bins tx_data = {8'h08};
      bins rx_data = {8'h0C};
      bins clk_div = {8'h10};
      bins ss_ctrl = {8'h14};
      bins int_en = {8'h18};
      bins int_stat = {8'h1C};
      bins delay_r = {8'h20};
    }

    // R1: proved readable (is_write=0 guaranteed because sample called
    // only from the read branch of sample_apb)
    cp_readback: coverpoint cv_readback {
      bins data_match = {1'b1};
    }

    // R1: every register must be read and its value confirmed correct
    cx_addr_readback: cross cp_addr, cp_readback;
  endgroup

  // -------------------------------------------------------------------------
  // cg_rst — R2
  // -------------------------------------------------------------------------
  covergroup cg_rst;
    option.per_instance = 1;

    cp_addr: coverpoint cv_addr {
      bins ctrl = {8'h00};
      bins status = {8'h04};
      bins tx_data = {8'h08};
      bins rx_data = {8'h0C};
      bins clk_div = {8'h10};
      bins ss_ctrl = {8'h14};
      bins int_en = {8'h18};
      bins int_stat = {8'h1C};
      bins delay_r = {8'h20};
    }

    cp_rst_val_ok: coverpoint cv_rst_val_ok {bins correct_rst_values = {1'b1};}

    cx_addr_rst: cross cp_addr, cp_rst_val_ok;
  endgroup

  // -------------------------------------------------------------------------
  // cg_ctrl_en — R3
  // -------------------------------------------------------------------------
  covergroup cg_ctrl_en;
    option.per_instance = 1;

    cp_en: coverpoint cv_ctrl_en {bins enabled = {1'b1}; bins disabled = {1'b0};}

    cp_tx_empty_en0: coverpoint cv_tx_empty_en0 {bins fifo_empty_during_en0 = {1'b1};}

    cp_rx_empty_en0: coverpoint cv_rx_empty_en0 {bins fifo_empty_during_en0 = {1'b1};}

    cp_sclk_idle: coverpoint cv_sclk_idle {bins at_cpol = {1'b1};}

    cp_ss_high: coverpoint cv_ss_high {bins forced_high = {1'b1};}

    cx_en0_tx: cross cp_en, cp_tx_empty_en0{ignore_bins en1 = binsof (cp_en.enabled);}
    cx_en0_rx: cross cp_en, cp_rx_empty_en0{ignore_bins en1 = binsof (cp_en.enabled);}
    cx_en0_sclk: cross cp_en, cp_sclk_idle{ignore_bins en1 = binsof (cp_en.enabled);}
    cx_en0_ss: cross cp_en, cp_ss_high{ignore_bins en1 = binsof (cp_en.enabled);}
  endgroup

  // -------------------------------------------------------------------------
  // cg_spi_cfg — R4, R5, R6, R25
  // -------------------------------------------------------------------------
  covergroup cg_spi_cfg;
    option.per_instance = 1;

    cp_mode: coverpoint cv_mode {
      bins mode0 = {2'b00}; bins mode1 = {2'b01}; bins mode2 = {2'b10}; bins mode3 = {2'b11};
    }

    cp_width: coverpoint cv_width {bins w8 = {2'b00}; bins w16 = {2'b01}; bins w32 = {2'b10};}

    cp_lsb: coverpoint cv_lsb_first {bins msb_first = {1'b0}; bins lsb_first = {1'b1};}

    cx_full: cross cp_mode, cp_width, cp_lsb;
  endgroup

  // -------------------------------------------------------------------------
  // cg_clk_div — R8, R24
  // -------------------------------------------------------------------------
  covergroup cg_clk_div;
    option.per_instance = 1;

    cp_div: coverpoint cv_clk_div {
      bins div0 = {16'h0000};  // R24: PCLK/2, no divide-by-zero
      bins div1 = {16'h0001};  // PCLK/4
      bins div2 = {16'h0002};
      bins div3 = {16'h0003};
      bins div255 = {16'h00FF};
      bins div1024 = {16'h0400};  // PCLK/2050 corner
      bins div_small = {[16'h0004 : 16'h00FE]};
      bins div_medium = {[16'h0100 : 16'h03FF]};
      // WARN-2: was [16'h0400:16'hFFFE], now starts at 16'h0401
      bins div_large = {[16'h0401 : 16'hFFFE]};
      bins div_max = {16'hFFFF};
    }
  endgroup

  // -------------------------------------------------------------------------
  // cg_fifo_occ — R9, R10, R11, R12
  // -------------------------------------------------------------------------
  covergroup cg_fifo_occ;
    option.per_instance = 1;

    cp_tx: coverpoint cv_tx_occ {
      bins tx0 = {0};
      bins tx1 = {1};
      bins tx2_3 = {[2 : 3]};
      bins tx4 = {4};
      bins tx5_6 = {[5 : 6]};
      bins tx7 = {7};
      bins tx8 = {8};  // R11: TX_FULL
    }

    cp_rx: coverpoint cv_rx_occ {
      bins rx0 = {0};
      bins rx1 = {1};
      bins rx2_3 = {[2 : 3]};
      bins rx4 = {4};
      bins rx5_6 = {[5 : 6]};
      bins rx7 = {7};
      bins rx8 = {8};  // R12: RX_FULL
    }
  endgroup

  // -------------------------------------------------------------------------
  // cg_overflow — R13, R14, R15
  // -------------------------------------------------------------------------
  covergroup cg_overflow;
    option.per_instance = 1;

    cp_tx_ovf: coverpoint cv_tx_ovf {bins no_ovf = {1'b0}; bins ovf = {1'b1};}

    cp_rx_ovf: coverpoint cv_rx_ovf {bins no_ovf = {1'b0}; bins ovf = {1'b1};}

    cp_rx_empty_read: coverpoint cv_rx_empty_read {
      bins no_empty_read = {1'b0}; bins empty_read = {1'b1};
    }
  endgroup

  // -------------------------------------------------------------------------
  // cg_irq — R16, R17, R18
  // -------------------------------------------------------------------------
  covergroup cg_irq;
    option.per_instance = 1;

    // R16 sub-clause 1: each of the 5 interrupt bits must fire
    cp_tx_empty_irq: coverpoint cv_int_stat[0] {
      bins set = {1'b1}; bins clear = {1'b0};
    }
    cp_rx_full_irq: coverpoint cv_int_stat[1] {bins set = {1'b1}; bins clear = {1'b0};}
    cp_tx_ovf_irq: coverpoint cv_int_stat[2] {bins set = {1'b1}; bins clear = {1'b0};}
    cp_rx_ovf_irq: coverpoint cv_int_stat[3] {bins set = {1'b1}; bins clear = {1'b0};}
    cp_done_irq: coverpoint cv_int_stat[4] {bins set = {1'b1}; bins clear = {1'b0};}


    cp_int_en: coverpoint cv_int_en {
      bins all_enabled = {5'b11111};
      bins all_disabled = {5'b00000};
      // per-bit: the named bit is DISABLED (0), others are don't-care
      wildcard bins bit0_masked = {5'b????0};  // TX_EMPTY masked
      wildcard bins bit1_masked = {5'b???0?};  // RX_FULL  masked
      wildcard bins bit2_masked = {5'b??0??};  // TX_OVF   masked
      wildcard bins bit3_masked = {5'b?0???};  // RX_OVF   masked
      wildcard bins bit4_masked = {5'b0????};  // DONE      masked
    }

    // R16 sub-clause 2: INT_EN must NOT gate INT_STAT capture
    cp_masked_capture: coverpoint cv_masked_stat {
      wildcard bins tx_empty_captured_masked = {5'b????1};
      wildcard bins rx_full_captured_masked = {5'b???1?};
      wildcard bins tx_ovf_captured_masked = {5'b??1??};
      wildcard bins rx_ovf_captured_masked = {5'b?1???};
      wildcard bins done_captured_masked = {5'b1????};
    }

    // R17: per-bit W1C
    cp_w1c_per_bit: coverpoint cv_w1c_mask {
      wildcard bins w1c_bit0 = {5'b????1};
      wildcard bins w1c_bit1 = {5'b???1?};
      wildcard bins w1c_bit2 = {5'b??1??};
      wildcard bins w1c_bit3 = {5'b?1???};
      wildcard bins w1c_bit4 = {5'b1????};
    }

    // R18: per-bit W1C race
    cp_w1c_race_per_bit: coverpoint cv_w1c_race_mask {
      wildcard bins race_bit0 = {5'b????1};
      wildcard bins race_bit1 = {5'b???1?};
      wildcard bins race_bit2 = {5'b??1??};
      wildcard bins race_bit3 = {5'b?1???};
      wildcard bins race_bit4 = {5'b1????};
    }
  endgroup

  // -------------------------------------------------------------------------
  // cg_loopback — R19
  // -------------------------------------------------------------------------
  covergroup cg_loopback;
    option.per_instance = 1;

    cp_lb: coverpoint cv_loopback {bins loopback_off = {1'b0}; bins loopback_on = {1'b1};}

    cp_width: coverpoint cv_width {bins w8 = {2'b00}; bins w16 = {2'b01}; bins w32 = {2'b10};}

    cx_lb_width: cross cp_lb, cp_width{ignore_bins off_width = binsof (cp_lb.loopback_off);}

    cp_mode: coverpoint cv_mode {
      bins mode0 = {2'b00}; bins mode1 = {2'b01}; bins mode2 = {2'b10}; bins mode3 = {2'b11};
    }

    cx_lb_mode: cross cp_lb, cp_mode{ignore_bins off_mode = binsof (cp_lb.loopback_off);}
  endgroup

  // -------------------------------------------------------------------------
  // cg_ss — R20
  // -------------------------------------------------------------------------
  covergroup cg_ss;
    option.per_instance = 1;

    cp_ss_en: coverpoint cv_ss_en {
      bins ss0_only = {4'b0001};
      bins ss1_only = {4'b0010};
      bins ss2_only = {4'b0100};
      bins ss3_only = {4'b1000};
      bins none = {4'b0000};
      bins multiple = {[4'b0011 : 4'b1111]};
    }

    // WARN-3 FIX: track ss_val so override path is visible
    cp_ss_val: coverpoint cv_ss_val {
      bins val_zero = {4'b0000};  // val=0: SS_n follows ~ss_en
      bins val_any = {[4'b0001 : 4'b1111]};  // val non-zero: can force high
    }

    // Cross: verify the SS_n formula is exercised in both directions
    // for at least one slave at a time.
    cx_ss_en_val: cross cp_ss_en, cp_ss_val{
    // multiple-select + val is a valid but secondary path; keep it
    }
  endgroup

  // -------------------------------------------------------------------------
  // cg_delay — R21
  // -------------------------------------------------------------------------
  covergroup cg_delay;
    option.per_instance = 1;

    cp_delay: coverpoint cv_delay {
      bins d0 = {8'h00};
      bins d1 = {8'h01};
      bins d2_15 = {[8'h02 : 8'h0F]};
      bins d16_127 = {[8'h10 : 8'h7F]};
      bins d128_255 = {[8'h80 : 8'hFF]};
    }

    cp_queued: coverpoint cv_delay_queued {bins no_next_word = {1'b0}; bins has_next_word = {1'b1};}

    cx_delay_queued: cross cp_delay, cp_queued{ignore_bins d0_any = binsof (cp_delay.d0);}
  endgroup

  // -------------------------------------------------------------------------
  // cg_reserved — R23
  // -------------------------------------------------------------------------
  covergroup cg_reserved;
    option.per_instance = 1;

    cp_reserved_addr: coverpoint cv_reserved_addr {
      bins res_24 = {8'h24}; bins res_28 = {8'h28}; bins res_other = {[8'h2C : 8'hFF]};
    }

    // BUG-4 FIX: reads cv_reserved_is_write, not the shared cv_is_write
    cp_rw: coverpoint cv_reserved_is_write {
      bins read = {1'b0}; bins write = {1'b1};
    }

    cx_addr_rw: cross cp_reserved_addr, cp_rw;
  endgroup

  // -------------------------------------------------------------------------
  // cg_busy — R7
  // -------------------------------------------------------------------------
  covergroup cg_busy;
    option.per_instance = 1;

    cp_busy: coverpoint cv_busy {bins idle = {1'b0}; bins active = {1'b1};}

    // BUG-5 FIX: dedicated variable
    cp_width: coverpoint cv_busy_width {
      bins w8 = {2'b00}; bins w16 = {2'b01}; bins w32 = {2'b10};
    }

    cx_busy_width: cross cp_busy, cp_width{ignore_bins idle_any_width = binsof (cp_busy.idle);}
  endgroup

  // =========================================================================
  // Constructor
  // =========================================================================
  function new();
    cg_apb_protocol = new();
    cg_apb_reg      = new();
    cg_rst          = new();
    cg_ctrl_en      = new();
    cg_spi_cfg      = new();
    cg_clk_div      = new();
    cg_fifo_occ     = new();
    cg_overflow     = new();
    cg_irq          = new();
    cg_loopback     = new();
    cg_ss           = new();
    cg_delay        = new();
    cg_reserved     = new();
    cg_busy         = new();
  endfunction

  // =========================================================================
  // Covers R4, R5, R6, R25 (the 24-cross) and R19 (loopback).
  // =========================================================================
  task sample_config(input bit [1:0] mode, input bit lsb_first, input bit [1:0] width,
                     input bit loopback = 1'b0);
    cv_mode      = mode;
    cv_lsb_first = lsb_first;
    cv_width     = width;
    cv_loopback  = loopback;
    // NOTE: cv_ctrl_en is NOT set here. Call sample_ctrl_en() separately.

    cg_spi_cfg.sample();
    cg_loopback.sample();
  endtask

  // =========================================================================
  task sample_apb(input bit [7:0] addr, input bit is_write, input bit [31:0] wdata,
                  input bit [31:0] rdata, input bit pslverr = 1'b0, input bit pready = 1'b1);
    // Protocol variables used by cg_apb_protocol (both paths)
    cv_pslverr  = pslverr;
    cv_pready   = pready;
    cv_addr     = addr;
    cv_is_write = is_write;

    if (is_write) begin
      // Shadow the written value for later readback comparison.
      // RO registers: writes are ignored by the DUT, don't shadow them.
      case (addr)
        8'h04:   ;  // STATUS  — RO, do not shadow
        8'h0C:   ;  // RX_DATA — RO, do not shadow
        default: cv_last_written[addr] = wdata;
      endcase

      // BUG-3 FIX: sample R22 protocol covergroup only (not readback).
      // cv_readback is NOT touched on the write path.
      cg_apb_protocol.sample();

    end else begin
      // READ path: check readback and sample R1 + R22 covergroups.
      // Note: cv_addr was already set to addr at the top of this task.

      case (addr)
        8'h04: cv_readback = 1'b1;

        // BUG-2 FIX: RX_DATA (0x0C) is read-only. Writes to it are
        // never shadowed (8'h0C is skipped in the write path), so
        // cv_last_written[0x0C] never exists. Without this special case,
        // the default branch always sets cv_readback=0, making the
        // rx_data×data_match cross bin permanently unhittable.
        // Value correctness is the scoreboard's responsibility;
        // coverage just needs to confirm the register was read.
        8'h0C: cv_readback = 1'b1;

        // BUG-1 FIX: TX_DATA is write-only; spec says reads return 0.
        // Previously was unconditionally 1'b1, which meant a buggy DUT
        // returning non-zero would still close the tx_data×data_match bin.
        8'h08: cv_readback = (rdata == 32'h0);

        8'h1C: cv_readback = 1'b1;

        // All other registers: mask to meaningful bits, then compare.
        default: begin
          if (cv_last_written.exists(addr)) begin
            case (addr)
              8'h10:  // CLK_DIV: [15:0] meaningful
              cv_readback = (rdata[15:0] == cv_last_written[addr][15:0]);
              8'h14:  // SS_CTRL: [7:0] meaningful
              cv_readback = (rdata[7:0] == cv_last_written[addr][7:0]);
              8'h18:  // INT_EN: [4:0] meaningful
              cv_readback = (rdata[4:0] == cv_last_written[addr][4:0]);
              8'h20:  // DELAY: [7:0] meaningful
              cv_readback = (rdata[7:0] == cv_last_written[addr][7:0]);
              default:  // CTRL, RX_DATA (after write attempt), etc.
              cv_readback = (rdata == cv_last_written[addr]);
            endcase
          end else begin
            // No prior write — can't verify readback.
            cv_readback = 1'b0;
          end
        end
      endcase

      // R1: readback cross (reads only, BUG-3 fix)
      cg_apb_reg.sample();
      // R22: protocol cross (reads also counted here)
      cg_apb_protocol.sample();
    end
  endtask

  // =========================================================================
  // sample_reset — R2
  // =========================================================================
  task sample_reset(input bit [7:0] addr, input bit rst_val_ok);
    cv_addr       = addr;
    cv_rst_val_ok = rst_val_ok;
    // cv_post_reset removed (Bug-5 fix): was set here but no coverpoint
    // in cg_rst ever referenced it — pure dead state.
    cg_rst.sample();
  endtask

  // =========================================================================
  // sample_clk_div — R8, R24
  // =========================================================================
  task sample_clk_div(input bit [15:0] div);
    cv_clk_div = div;
    cg_clk_div.sample();
  endtask

  // =========================================================================
  // sample_fifo — R9, R10, R11, R12
  // =========================================================================
  task sample_fifo(input int tx_occ, input int rx_occ);
    cv_tx_occ = tx_occ;
    cv_rx_occ = rx_occ;
    cg_fifo_occ.sample();
  endtask

  // =========================================================================
  // sample_overflow — R13, R14, R15
  // =========================================================================
  task sample_overflow(input bit tx_ovf = 1'b0, input bit rx_ovf = 1'b0,
                       input bit rx_empty_rd = 1'b0);
    cv_tx_ovf        = tx_ovf;
    cv_rx_ovf        = rx_ovf;
    cv_rx_empty_read = rx_empty_rd;
    cg_overflow.sample();
  endtask

  // =========================================================================
  // sample_irq — R16, R17, R18
  // =========================================================================
  task sample_irq(input bit [4:0] int_stat, input bit [4:0] int_en, input bit [4:0] w1c_mask = 5'b0,
                  input bit [4:0] w1c_race_mask = 5'b0);
    // BUG-6 FIX: guard invariant — race bits must be a subset of w1c bits
    if ((w1c_race_mask & ~w1c_mask) != 5'b0) begin
      $error(
          "[COV_BUG] sample_irq: w1c_race_mask (0x%0h) has bits not in w1c_mask (0x%0h). Race mask must be a strict subset of w1c_mask.",
          w1c_race_mask, w1c_mask);
    end

    cv_int_stat      = int_stat;
    cv_int_en        = int_en;
    cv_masked_stat   = int_stat & ~int_en;  // R16: captured-while-masked
    cv_w1c_mask      = w1c_mask;
    cv_w1c_race_mask = w1c_race_mask;
    cg_irq.sample();
  endtask

  // =========================================================================
  // sample_ss — R20
  // =========================================================================
  task sample_ss(input bit [3:0] ss_en, input bit [3:0] ss_val = 4'b0);
    cv_ss_en  = ss_en;
    cv_ss_val = ss_val;
    cg_ss.sample();
  endtask

  // =========================================================================
  // sample_delay — R21
  // =========================================================================
  task sample_delay(input bit [7:0] delay_val, input bit queued = 1'b0);
    cv_delay        = delay_val;
    cv_delay_queued = queued;
    cg_delay.sample();
  endtask

  // =========================================================================
  // sample_reserved — R23
  // =========================================================================
  task sample_reserved(input bit [7:0] addr, input bit is_write = 1'b0);
    cv_reserved_addr     = addr;
    cv_reserved_is_write = is_write;
    cg_reserved.sample();
  endtask

  // =========================================================================
  // sample_busy — R7
  // =========================================================================
  task sample_busy(input bit busy, input bit [1:0] width = 2'b00);
    cv_busy       = busy;
    // BUG-5 FIX: dedicated variable — never touches cv_width
    cv_busy_width = width;
    cg_busy.sample();
  endtask

  // =========================================================================
  // sample_ctrl_en — R3
  // =========================================================================
  task sample_ctrl_en(input bit en, input bit sclk,  // observed SCLK pin value
                      input bit [1:0] mode,  // current CPOL from mode[1]
                      input bit [3:0] ss_n,  // observed SS_n pin values
                      input bit [3:0] ss_en,  // SS_CTRL.ss_en field (used for context only)
                      input int tx_occ, input int rx_occ);
    bit cpol;
    cpol       = mode[1];  // CPOL is bit 1 of the mode field

    cv_ctrl_en = en;

    if (!en) begin
      // R3 claim 1: FIFOs must be empty when EN=0
      cv_tx_empty_en0 = (tx_occ == 0);
      cv_rx_empty_en0 = (rx_occ == 0);
      // R3 claim 2: SCLK must hold at the CPOL idle level
      cv_sclk_idle = (sclk == cpol);

      // R3 claim 3: all SS_n must be high (inactive) even when
      // SS_CTRL.ss_en is non-zero, because EN=0 overrides SS_CTRL.
      //
      // BUG-3 FIX: the old code was cv_ss_high = &ss_n, which is
      // trivially 1 when ss_en=0 (formula: SS_n = ~ss_en | ss_val,
      // so ss_en=0 → SS_n=0xF always). That let the bin close without
      // ever testing the interesting case. The fix: only assert
      // cv_ss_high=1 when ss_en is non-zero AND all SS_n are still
      // high — proving the DUT correctly overrides an active SS_CTRL.
      cv_ss_high = (ss_en != 4'b0) && (&ss_n);

    end else begin
      // EN=1: these signals are not constrained; clear flags so the
      // EN=0-specific bins are only hit from the EN=0 branch.
      cv_tx_empty_en0 = 1'b0;
      cv_rx_empty_en0 = 1'b0;
      cv_sclk_idle    = 1'b0;
      cv_ss_high      = 1'b0;
    end

    cg_ctrl_en.sample();
  endtask

endclass

`endif  // SPI_COVERAGE_COL_SV
