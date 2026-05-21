// =============================================================================
// coverage.sv  —  SPI Master Functional Coverage
// =============================================================================
// Ain Shams University  |  Digital Design Verification  |  Spring 2026
//
// Instantiated once in tb_top. Tests call the sample_*() tasks after each
// relevant event to record what scenarios were exercised.
// =============================================================================

`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV 

class spi_coverage_col;

  // =========================================================================
  // Coverage variables
  // =========================================================================

  // SPI transfer configuration
  bit [ 1:0] cv_mode;
  bit        cv_lsb_first;
  bit [ 1:0] cv_width;
  bit        cv_loopback;

  // APB register access
  bit [ 7:0] cv_addr;
  bit        cv_is_write;
  bit        cv_readback;
  bit [31:0] cv_last_written[bit                                            [7:0]];

  // Reset check
  bit        cv_rst_val_ok;

  // CTRL.EN behaviour
  bit        cv_ctrl_en;
  bit        cv_tx_empty_en0;
  bit        cv_rx_empty_en0;
  bit        cv_sclk_idle;
  bit        cv_ss_high;

  // CLK_DIV
  bit [15:0] cv_clk_div;

  // FIFO occupancy
  int        cv_tx_occ;
  int        cv_rx_occ;

  // FIFO error conditions
  bit        cv_tx_ovf;
  bit        cv_rx_ovf;
  bit        cv_rx_empty_read;

  // Interrupts
  bit [ 4:0] cv_int_stat;
  bit [ 4:0] cv_int_en;
  bit [ 4:0] cv_masked_stat;  // int_stat & ~int_en: bits set while masked
  bit [ 4:0] cv_w1c_mask;  // which INT_STAT bits were written-1 (W1C)

  // Slave select
  bit [ 3:0] cv_ss_en;

  // Inter-transfer delay
  bit [ 7:0] cv_delay;

  // Reserved address access
  bit [ 7:0] cv_reserved_addr;
  bit        cv_reserved_is_write;

  // BUSY flag
  bit        cv_busy;


  // =========================================================================
  // MANDATORY covergroups
  // =========================================================================


  // -------------------------------------------------------------------------
  // cg_spi_cfg  —  R4, R5, R6, R25  [MANDATORY]
  // 4 SPI modes x 3 transfer widths x 2 bit orders = 24 combinations
  // -------------------------------------------------------------------------
  covergroup cg_spi_cfg;
    option.per_instance = 1;

    cp_mode: coverpoint cv_mode {
      bins mode0 = {2'b00}; bins mode1 = {2'b01}; bins mode2 = {2'b10}; bins mode3 = {2'b11};
    }

    cp_width: coverpoint cv_width {bins w8 = {2'b00}; bins w16 = {2'b01}; bins w32 = {2'b10};}

    cp_lsb: coverpoint cv_lsb_first {bins msb_first = {1'b0}; bins lsb_first = {1'b1};}

    // All 24 mode/width/bit-order combinations
    cx_full: cross cp_mode, cp_width, cp_lsb;

  endgroup


  // -------------------------------------------------------------------------
  // cg_clk_div  —  R8, R24  [MANDATORY]
  // Clock divider corners: 0 (fastest), specific values, and max
  // -------------------------------------------------------------------------
  covergroup cg_clk_div;
    option.per_instance = 1;

    cp_div: coverpoint cv_clk_div {
      bins div0 = {16'h0000};  // PCLK/2 — fastest SCLK
      bins div1 = {16'h0001};
      bins div2 = {16'h0002};
      bins div3 = {16'h0003};
      bins div255 = {16'h00FF};
      bins div1024 = {16'h0400};
      bins div_mid = {[16'h0004 : 16'hFFFE]};  // general range
      bins div_max = {16'hFFFF};  // slowest SCLK
    }

  endgroup


  // -------------------------------------------------------------------------
  // cg_fifo_occ  —  R9, R10, R11, R12  [MANDATORY]
  // TX and RX FIFO occupancy: empty, 1 entry, mid (4), near-full (7), full
  // -------------------------------------------------------------------------
  covergroup cg_fifo_occ;
    option.per_instance = 1;

    cp_tx: coverpoint cv_tx_occ {
      bins tx_empty = {0}; bins tx_1 = {1}; bins tx_mid = {4}; bins tx_7 = {7}; bins tx_full = {8};
    }

    cp_rx: coverpoint cv_rx_occ {
      bins rx_empty = {0}; bins rx_1 = {1}; bins rx_mid = {4}; bins rx_7 = {7}; bins rx_full = {8};
    }

  endgroup


  // -------------------------------------------------------------------------
  // cg_irq  —  R16, R17, R18  [MANDATORY]
  // Each of the 5 interrupt sources: fires, captured while masked, cleared
  // -------------------------------------------------------------------------
  covergroup cg_irq;
    option.per_instance = 1;

    // --- Each source must assert at least once ---
    cp_tx_empty_irq: coverpoint cv_int_stat[0] {
      bins fired = {1'b1};
    }
    cp_rx_full_irq: coverpoint cv_int_stat[1] {bins fired = {1'b1};}
    cp_tx_ovf_irq: coverpoint cv_int_stat[2] {bins fired = {1'b1};}
    cp_rx_ovf_irq: coverpoint cv_int_stat[3] {bins fired = {1'b1};}
    cp_done_irq: coverpoint cv_int_stat[4] {bins fired = {1'b1};}

    // --- INT_EN masking: IRQ = |(INT_STAT & INT_EN) ---
    cp_int_en: coverpoint cv_int_en {
      bins all_on = {5'b11111};  // all sources route to IRQ pin
      bins all_off = {5'b00000};  // IRQ always low regardless of events
      bins partial = {[5'b00001 : 5'b11110]};  // selective routing
    }

    // --- R16: INT_EN must not suppress INT_STAT capture ---
    // Each bin fires when that source was recorded in INT_STAT
    // while its INT_EN bit was 0, proving the latch is independent.
    cp_tx_empty_masked: coverpoint cv_masked_stat[0] {
      bins captured = {1'b1};
    }
    cp_rx_full_masked: coverpoint cv_masked_stat[1] {bins captured = {1'b1};}
    cp_tx_ovf_masked: coverpoint cv_masked_stat[2] {bins captured = {1'b1};}
    cp_rx_ovf_masked: coverpoint cv_masked_stat[3] {bins captured = {1'b1};}
    cp_done_masked: coverpoint cv_masked_stat[4] {bins captured = {1'b1};}

    // --- R17: W1C — each source cleared by writing 1 to its bit ---
    cp_w1c_tx_empty: coverpoint cv_w1c_mask[0] {
      bins cleared = {1'b1};
    }
    cp_w1c_rx_full: coverpoint cv_w1c_mask[1] {bins cleared = {1'b1};}
    cp_w1c_tx_ovf: coverpoint cv_w1c_mask[2] {bins cleared = {1'b1};}
    cp_w1c_rx_ovf: coverpoint cv_w1c_mask[3] {bins cleared = {1'b1};}
    cp_w1c_done: coverpoint cv_w1c_mask[4] {bins cleared = {1'b1};}

  endgroup


  // -------------------------------------------------------------------------
  // cg_loopback  —  R19  [MANDATORY]
  // Loopback routes MOSI back to RX; MISO is ignored
  // -------------------------------------------------------------------------
  covergroup cg_loopback;
    option.per_instance = 1;

    cp_lb: coverpoint cv_loopback {
      bins off = {1'b0}; bins on = {1'b1};  // at least one loopback transfer required
    }

    cp_width: coverpoint cv_width {bins w8 = {2'b00}; bins w16 = {2'b01}; bins w32 = {2'b10};}

    // Loopback must work at all three transfer widths
    cx_lb_width: cross cp_lb, cp_width{
      ignore_bins off_any = binsof (cp_lb.off);
    }

  endgroup


  // -------------------------------------------------------------------------
  // cg_delay  —  R21  [MANDATORY]
  // Inter-transfer gap delay: 0 (none), 1 (minimum), large value
  // -------------------------------------------------------------------------
  covergroup cg_delay;
    option.per_instance = 1;

    cp_delay: coverpoint cv_delay {
      bins d0 = {8'h00};  // no delay
      bins d1 = {8'h01};  // minimum gap
      bins d2_127 = {[8'h02 : 8'h7F]};
      bins d128_255 = {[8'h80 : 8'hFF]};  // large gap
    }

  endgroup


  // -------------------------------------------------------------------------
  // cg_rst  —  R2  [MANDATORY]
  // Every register must read back its spec-defined reset value after PRESETn
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

    cp_rst_ok: coverpoint cv_rst_val_ok {bins correct = {1'b1};}

    cx_reg_rst: cross cp_addr, cp_rst_ok;

  endgroup


  // =========================================================================
  // ADDITIONAL covergroups  (bug-detection depth beyond the mandatory gate)
  // =========================================================================


  // -------------------------------------------------------------------------
  // cg_apb_reg  —  R1  [ADDITIONAL]
  // Every register is written then read back with matching data
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

    cp_readback: coverpoint cv_readback {bins match = {1'b1};}

    cx_reg_readback: cross cp_addr, cp_readback;

  endgroup


  // -------------------------------------------------------------------------
  // cg_overflow  —  R13, R14, R15  [ADDITIONAL]
  // Error conditions: write to full TX, push to full RX, read from empty RX
  // -------------------------------------------------------------------------
  covergroup cg_overflow;
    option.per_instance = 1;

    cp_tx_ovf: coverpoint cv_tx_ovf {bins no_ovf = {1'b0}; bins ovf = {1'b1};}

    cp_rx_ovf: coverpoint cv_rx_ovf {bins no_ovf = {1'b0}; bins ovf = {1'b1};}

    cp_rx_empty_read: coverpoint cv_rx_empty_read {
      bins no_empty_rd = {1'b0}; bins empty_rd = {1'b1};
    }

  endgroup


  // -------------------------------------------------------------------------
  // cg_ctrl_en  —  R3  [ADDITIONAL]
  // When EN=0: FIFOs must be empty, SCLK at idle, SS_n forced high
  // -------------------------------------------------------------------------
  covergroup cg_ctrl_en;
    option.per_instance = 1;

    cp_en: coverpoint cv_ctrl_en {bins enabled = {1'b1}; bins disabled = {1'b0};}

    // TX FIFO cleared when EN deasserts
    cp_tx_empty_en0: coverpoint cv_tx_empty_en0 {
      bins fifo_empty = {1'b1};
    }

    // RX FIFO cleared when EN deasserts
    cp_rx_empty_en0: coverpoint cv_rx_empty_en0 {
      bins fifo_empty = {1'b1};
    }

    // SCLK must idle at CPOL level when EN=0
    cp_sclk_idle: coverpoint cv_sclk_idle {
      bins at_cpol = {1'b1};
    }

    // SS_n forced high even when SS_CTRL.ss_en was non-zero
    cp_ss_high: coverpoint cv_ss_high {
      bins forced_high = {1'b1};
    }

    cx_en0_tx: cross cp_en, cp_tx_empty_en0{ignore_bins en1 = binsof (cp_en.enabled);}
    cx_en0_rx: cross cp_en, cp_rx_empty_en0{ignore_bins en1 = binsof (cp_en.enabled);}
    cx_en0_sclk: cross cp_en, cp_sclk_idle{ignore_bins en1 = binsof (cp_en.enabled);}
    cx_en0_ss: cross cp_en, cp_ss_high{ignore_bins en1 = binsof (cp_en.enabled);}

  endgroup


  // -------------------------------------------------------------------------
  // cg_ss  —  R20  [ADDITIONAL]
  // Each slave-select lane selected individually at least once
  // -------------------------------------------------------------------------
  covergroup cg_ss;
    option.per_instance = 1;

    cp_ss_en: coverpoint cv_ss_en {
      bins ss0 = {4'b0001};
      bins ss1 = {4'b0010};
      bins ss2 = {4'b0100};
      bins ss3 = {4'b1000};
      bins none = {4'b0000};
    }

  endgroup


  // -------------------------------------------------------------------------
  // cg_reserved  —  R23  [ADDITIONAL]
  // Reserved offsets must silently read 0 and ignore writes (no PSLVERR)
  // -------------------------------------------------------------------------
  covergroup cg_reserved;
    option.per_instance = 1;

    cp_addr: coverpoint cv_reserved_addr {
      bins res_24 = {8'h24}; bins res_28 = {8'h28}; bins res_other = {[8'h2C : 8'hFF]};
    }

    cp_rw: coverpoint cv_reserved_is_write {bins read = {1'b0}; bins write = {1'b1};}

    cx_reserved: cross cp_addr, cp_rw;

  endgroup


  // -------------------------------------------------------------------------
  // cg_busy  —  R7  [ADDITIONAL]
  // STATUS.BUSY observed high during an active transfer
  // -------------------------------------------------------------------------
  covergroup cg_busy;
    option.per_instance = 1;

    cp_busy: coverpoint cv_busy {bins idle = {1'b0}; bins active = {1'b1};}

  endgroup


  // =========================================================================
  // Constructor
  // =========================================================================
  function new();
    // Mandatory
    cg_spi_cfg  = new();
    cg_clk_div  = new();
    cg_fifo_occ = new();
    cg_irq      = new();
    cg_loopback = new();
    cg_delay    = new();
    cg_rst      = new();
    // Additional
    cg_apb_reg  = new();
    cg_overflow = new();
    cg_ctrl_en  = new();
    cg_ss       = new();
    cg_reserved = new();
    cg_busy     = new();
  endfunction


  // =========================================================================
  // Sample tasks
  // =========================================================================


  // Call after writing CTRL (before starting a transfer)
  // Covers cg_spi_cfg, cg_loopback
  task sample_config(input bit [1:0] mode, input bit lsb_first, input bit [1:0] width,
                     input bit loopback = 1'b0);
    cv_mode      = mode;
    cv_lsb_first = lsb_first;
    cv_width     = width;
    cv_loopback  = loopback;
    cg_spi_cfg.sample();
    cg_loopback.sample();
  endtask


  // Call after every APB read or write
  // Covers cg_apb_reg
  task sample_apb(input bit [7:0] addr, input bit is_write, input bit [31:0] wdata,
                  input bit [31:0] rdata, input bit pslverr = 1'b0, input bit pready = 1'b1);
    cv_addr     = addr;
    cv_is_write = is_write;

    if (is_write) begin
      case (addr)
        8'h04:   ;  // STATUS  — read-only
        8'h0C:   ;  // RX_DATA — read-only
        default: cv_last_written[addr] = wdata;
      endcase
    end else begin
      case (addr)
        8'h04: cv_readback = 1'b1;  // STATUS changes constantly; just confirm readable
        8'h0C: cv_readback = 1'b1;  // RX_DATA is read-only, value checked by scoreboard
        8'h08: cv_readback = (rdata == 32'h0);  // TX_DATA write-only, reads must return 0
        8'h1C: cv_readback = 1'b1;  // INT_STAT is W1C, confirm readable
        default: begin
          if (cv_last_written.exists(addr)) begin
            case (addr)
              8'h10:   cv_readback = (rdata[15:0] == cv_last_written[addr][15:0]);
              8'h14:   cv_readback = (rdata[7:0] == cv_last_written[addr][7:0]);
              8'h18:   cv_readback = (rdata[4:0] == cv_last_written[addr][4:0]);
              8'h20:   cv_readback = (rdata[7:0] == cv_last_written[addr][7:0]);
              default: cv_readback = (rdata == cv_last_written[addr]);
            endcase
          end else begin
            cv_readback = 1'b0;
          end
        end
      endcase
      cg_apb_reg.sample();
    end
  endtask


  // Call once per register immediately after PRESETn deasserts
  // Covers cg_rst
  // Pass rst_val_ok = (observed_rd == expected_reset_value)
  task sample_reset(input bit [7:0] addr, input bit rst_val_ok);
    cv_addr       = addr;
    cv_rst_val_ok = rst_val_ok;
    cg_rst.sample();
  endtask


  // Call after writing CLK_DIV and completing a transfer at that divider
  // Covers cg_clk_div
  task sample_clk_div(input bit [15:0] div);
    cv_clk_div = div;
    cg_clk_div.sample();
  endtask


  // Call after every TX push or RX pop to track FIFO depth
  // Covers cg_fifo_occ
  task sample_fifo(input int tx_occ, input int rx_occ);
    cv_tx_occ = tx_occ;
    cv_rx_occ = rx_occ;
    cg_fifo_occ.sample();
  endtask


  // Call when a FIFO limit is hit (overflow or empty read)
  // Covers cg_overflow
  task sample_overflow(input bit tx_ovf = 1'b0, input bit rx_ovf = 1'b0,
                       input bit rx_empty_rd = 1'b0);
    cv_tx_ovf        = tx_ovf;
    cv_rx_ovf        = rx_ovf;
    cv_rx_empty_read = rx_empty_rd;
    cg_overflow.sample();
  endtask


  // Call after any change to INT_STAT or INT_EN
  // Covers cg_irq
  // w1c_mask: the bitmask written to INT_STAT in a W1C operation (0 if no W1C)
  task sample_irq(input bit [4:0] int_stat, input bit [4:0] int_en, input bit [4:0] w1c_mask = 5'b0,
                  input bit [4:0] w1c_race_mask = 5'b0   // accepted but unused
);
    cv_int_stat    = int_stat;
    cv_int_en      = int_en;
    cv_masked_stat = int_stat & ~int_en;
    cv_w1c_mask    = w1c_mask;
    // w1c_race_mask intentionally ignored (cp_w1c_race_per_bit removed)
    cg_irq.sample();
  endtask

  // Call after writing SS_CTRL
  // Covers cg_ss
  task sample_ss(input bit [3:0] ss_en, input bit [3:0] ss_val = 4'b0);
    cv_ss_en = ss_en;
    cg_ss.sample();
  endtask


  // Call at transfer completion (not at register write time)
  // Covers cg_delay
  task sample_delay(input bit [7:0] delay_val, input bit queued = 1'b0);
    cv_delay = delay_val;
    cg_delay.sample();
  endtask


  // Call when accessing a reserved offset (>= 0x24)
  // Covers cg_reserved
  task sample_reserved(input bit [7:0] addr, input bit is_write = 1'b0);
    cv_reserved_addr     = addr;
    cv_reserved_is_write = is_write;
    cg_reserved.sample();
  endtask


  // Call while polling STATUS.BUSY during a transfer
  // Covers cg_busy
  // sample_busy — keep old signature, width accepted but unused
  task sample_busy(input bit busy, input bit [1:0] width = 2'b00);
    cv_busy = busy;
    cg_busy.sample();
  endtask


  // Call after writing CTRL.EN in either direction
  // Covers cg_ctrl_en
  // sclk, ss_n: read from actual pins via hierarchical reference
  // ss_en: SS_CTRL.ss_en field (to detect the non-trivial EN=0 override case)
  task sample_ctrl_en(input bit en, input bit sclk, input bit [1:0] mode, input bit [3:0] ss_n,
                      input bit [3:0] ss_en, input int tx_occ, input int rx_occ);
    bit cpol = mode[1];
    cv_ctrl_en = en;

    if (!en) begin
      cv_tx_empty_en0 = (tx_occ == 0);
      cv_rx_empty_en0 = (rx_occ == 0);
      cv_sclk_idle    = (sclk == cpol);
      // Only meaningful when ss_en != 0: proves EN=0 overrides an active SS_CTRL
      cv_ss_high      = (ss_en != 4'b0) && (&ss_n);
    end else begin
      cv_tx_empty_en0 = 1'b0;
      cv_rx_empty_en0 = 1'b0;
      cv_sclk_idle    = 1'b0;
      cv_ss_high      = 1'b0;
    end

    cg_ctrl_en.sample();
  endtask


endclass

`endif  // SPI_COVERAGE_COL_SV
