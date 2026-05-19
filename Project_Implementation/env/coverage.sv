`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV 

class spi_coverage_col;

  // =========================================================================
  // Section 1 — Coverage variables
  // =========================================================================


  // --- SPI transfer configuration (R4, R5, R6, R25) ---
  bit [1:0] cv_mode;  // {CPOL, CPHA} — 4 SPI modes
  bit cv_lsb_first;  // bit order: 0=MSB first, 1=LSB first
  bit [1:0] cv_width;  // transfer width: 00=8b, 01=16b, 10=32b

  // --- APB register access (R1, R22) ---
  bit [7:0] cv_addr;  // register offset on the APB bus
  bit cv_is_write;  // direction: 1=write, 0=read
  bit cv_readback;  // 1 when read data matched what was written
  bit [31:0] cv_last_written[bit [7:0]];  // write-shadow for readback checks
  bit cv_pslverr;  // captured PSLVERR per access (must stay 0)
  bit cv_pready;  // captured PREADY per access (must stay 1)

  // --- Reset values (R2) ---
  bit cv_rst_val_ok;  // 1 when a register read after reset matched spec

  // --- CTRL.EN disable behaviour (R3) ---
  bit cv_ctrl_en;  // current CTRL.EN state
  bit cv_tx_empty_en0;  // TX FIFO empty while EN=0
  bit cv_rx_empty_en0;  // RX FIFO empty while EN=0
  bit cv_sclk_idle;  // SCLK observed at CPOL idle level while EN=0
  bit cv_ss_high;  // SS_n forced high while EN=0 (even if ss_en≠0)

  // --- CLK_DIV range and corners (R8, R24) ---
  bit [15:0] cv_clk_div;  // value written to the CLK_DIV register

  // --- FIFO depth snapshots (R9–R12) ---
  int cv_tx_occ;  // TX FIFO occupancy: 0..8
  int cv_rx_occ;  // RX FIFO occupancy: 0..8

  // --- FIFO error conditions (R13, R14, R15) ---
  bit cv_tx_ovf;  // TX write attempted while FIFO full
  bit cv_rx_ovf;  // RX push received while FIFO full
  bit cv_rx_empty_read;  // RX read attempted while FIFO empty

  // --- Interrupt status and masking (R16, R17, R18) ---
  bit [4:0] cv_int_stat;  // current INT_STAT[4:0] snapshot
  bit [4:0] cv_int_en;  // current INT_EN[4:0] snapshot
  bit [4:0] cv_masked_stat;  // bits set in INT_STAT while their INT_EN is 0
  bit [4:0] cv_w1c_mask;  // bitmask of bits targeted by a W1C write
  bit [4:0] cv_w1c_race_mask;  // bits where event fired on same cycle as W1C

  // --- Loopback mode (R19) ---
  bit cv_loopback;  // 1 when CTRL.LOOPBACK is set

  // --- Slave-select lane control (R20) ---
  bit [3:0] cv_ss_en;  // SS_CTRL.ss_en: which lanes are enabled
  bit [3:0] cv_ss_val;  // SS_CTRL.ss_val: optional override per lane

  // --- Inter-transfer delay (R21) ---
  bit [7:0] cv_delay;  // DELAY register value
  bit cv_delay_queued;  // 1 if another TX word was waiting when gap ran

  // --- Reserved address access (R23) ---
  bit [7:0] cv_reserved_addr;  // the reserved offset that was accessed
  bit cv_reserved_is_write;  // direction of the reserved access

  // --- Transfer busy flag (R7) ---
  bit cv_busy;  // STATUS.BUSY observed value
  bit [1:0] cv_busy_width;  // transfer width active when BUSY was sampled
                            // (kept separate from cv_width to avoid aliasing)


  // =========================================================================
  // Section 2 — MANDATORY covergroups
  // =========================================================================

  covergroup cg_spi_cfg;
    option.per_instance = 1;

    // SPI clock polarity and phase (CPOL, CPHA)
    cp_mode: coverpoint cv_mode {
      bins mode0 = {2'b00};  // CPOL=0 CPHA=0: idle low, sample on rising
      bins mode1 = {2'b01};  // CPOL=0 CPHA=1: idle low, sample on falling
      bins mode2 = {2'b10};  // CPOL=1 CPHA=0: idle high, sample on falling
      bins mode3 = {2'b11};  // CPOL=1 CPHA=1: idle high, sample on rising
    }

    // Transfer width: determines how many SCLK cycles the shift takes
    cp_width: coverpoint cv_width {
      bins w8 = {2'b00};  // 8-bit
      bins w16 = {2'b01};  // 16-bit
      bins w32 = {2'b10};  // 32-bit
    }

    // Bit order: controls which end of the shift register is sent first
    cp_lsb: coverpoint cv_lsb_first {
      bins msb_first = {1'b0}; bins lsb_first = {1'b1};
    }

    // 24-bin cross: every mode × width × bit-order combination
    cx_full: cross cp_mode, cp_width, cp_lsb;

  endgroup


  covergroup cg_clk_div;
    option.per_instance = 1;

    // Individual corner values get their own bins; ranges handle the rest
    cp_div: coverpoint cv_clk_div {
      bins div0 = {16'h0000};  // fastest: PCLK/2
      bins div1 = {16'h0001};  // PCLK/4
      bins div2 = {16'h0002};
      bins div3 = {16'h0003};
      bins div255 = {16'h00FF};  // common low-speed value
      bins div1024 = {16'h0400};  // mid-range corner
      bins div_small = {[16'h0004 : 16'h00FE]};  // low range sweep
      bins div_medium = {[16'h0100 : 16'h03FF]};  // mid range sweep
      bins div_large = {[16'h0401 : 16'hFFFE]};  // high range sweep
      bins div_max = {16'hFFFF};  // slowest: PCLK/131072
    }

  endgroup


  covergroup cg_fifo_occ;
    option.per_instance = 1;

    // TX FIFO occupancy (R9, R11)
    cp_tx: coverpoint cv_tx_occ {
      bins tx0 = {0};  // empty
      bins tx1 = {1};  // one entry
      bins tx2_3 = {[2 : 3]};
      bins tx4 = {4};  // half full
      bins tx5_6 = {[5 : 6]};
      bins tx7 = {7};  // one slot remaining
      bins tx8 = {8};  // full (R11: TX_FULL status bit)
    }

    // RX FIFO occupancy (R10, R12)
    cp_rx: coverpoint cv_rx_occ {
      bins rx0 = {0};  // empty
      bins rx1 = {1};
      bins rx2_3 = {[2 : 3]};
      bins rx4 = {4};  // half full
      bins rx5_6 = {[5 : 6]};
      bins rx7 = {7};
      bins rx8 = {8};  // full (R12: RX_FULL status bit)
    }

  endgroup


  covergroup cg_irq;
    option.per_instance = 1;

    // --- R16: each interrupt source must assert at least once ---

    // TX FIFO became empty during a transfer
    cp_tx_empty_irq: coverpoint cv_int_stat[0] {
      bins set = {1'b1}; bins clear = {1'b0};
    }

    // RX FIFO reached full occupancy
    cp_rx_full_irq: coverpoint cv_int_stat[1] {
      bins set = {1'b1}; bins clear = {1'b0};
    }

    // TX write was dropped because the FIFO was already full
    cp_tx_ovf_irq: coverpoint cv_int_stat[2] {
      bins set = {1'b1}; bins clear = {1'b0};
    }

    // RX push was lost because the FIFO was already full
    cp_rx_ovf_irq: coverpoint cv_int_stat[3] {
      bins set = {1'b1}; bins clear = {1'b0};
    }

    // A complete SPI transfer finished
    cp_done_irq: coverpoint cv_int_stat[4] {
      bins set = {1'b1}; bins clear = {1'b0};
    }

    // --- R16: INT_EN masking — IRQ pin level vs individual enables ---
    cp_int_en: coverpoint cv_int_en {
      bins all_enabled = {5'b11111};  // all sources routed to IRQ
      bins all_disabled = {5'b00000};  // IRQ always low
      wildcard bins bit0_masked = {5'b????0};  // TX_EMPTY masked
      wildcard bins bit1_masked = {5'b???0?};  // RX_FULL  masked
      wildcard bins bit2_masked = {5'b??0??};  // TX_OVF   masked
      wildcard bins bit3_masked = {5'b?0???};  // RX_OVF   masked
      wildcard bins bit4_masked = {5'b0????};  // DONE      masked
    }

    // --- R16 sub-clause 2: INT_EN must not suppress INT_STAT capture ---

    cp_masked_capture: coverpoint cv_masked_stat {
      wildcard bins tx_empty_captured_masked = {5'b????1};
      wildcard bins rx_full_captured_masked = {5'b???1?};
      wildcard bins tx_ovf_captured_masked = {5'b??1??};
      wildcard bins rx_ovf_captured_masked = {5'b?1???};
      wildcard bins done_captured_masked = {5'b1????};
    }

    // --- R17: W1C — writing 1 to a bit clears it; writing 0 has no effect ---

    cp_w1c_per_bit: coverpoint cv_w1c_mask {
      wildcard bins w1c_bit0 = {5'b????1};  // TX_EMPTY cleared
      wildcard bins w1c_bit1 = {5'b???1?};  // RX_FULL  cleared
      wildcard bins w1c_bit2 = {5'b??1??};  // TX_OVF   cleared
      wildcard bins w1c_bit3 = {5'b?1???};  // RX_OVF   cleared
      wildcard bins w1c_bit4 = {5'b1????};  // DONE      cleared
    }

    // --- R18: W1C race — set and clear arrive on the same PCLK edge ---
    // Hardware event fires (set) at the exact cycle software writes the W1C.
    // The spec requires the bit to remain set; clear must NOT win the race.
    cp_w1c_race_per_bit: coverpoint cv_w1c_race_mask {
      wildcard bins race_bit0 = {5'b????1};
      wildcard bins race_bit1 = {5'b???1?};
      wildcard bins race_bit2 = {5'b??1??};
      wildcard bins race_bit3 = {5'b?1???};
      wildcard bins race_bit4 = {5'b1????};
    }

  endgroup



  covergroup cg_loopback;
    option.per_instance = 1;

    // Basic loopback on/off observation
    cp_lb: coverpoint cv_loopback {
      bins loopback_off = {1'b0};
      bins loopback_on = {1'b1};  // mandatory: must be hit at least once
    }

    // Loopback at each transfer width — the internal MOSI→RX path must
    // work correctly regardless of how many bits are shifted.
    cp_width: coverpoint cv_width {
      bins w8 = {2'b00}; bins w16 = {2'b01}; bins w32 = {2'b10};
    }

    // Loopback must be verified at each width (loopback_off rows ignored)
    cx_lb_width: cross cp_lb, cp_width{
      ignore_bins off_width = binsof (cp_lb.loopback_off);
    }

    // Loopback across all four SPI modes.  The sample edge differs between
    // modes, so a bug in the CPOL=1 capture path is only exposed here.
    cp_mode: coverpoint cv_mode {
      bins mode0 = {2'b00}; bins mode1 = {2'b01}; bins mode2 = {2'b10}; bins mode3 = {2'b11};
    }

    cx_lb_mode: cross cp_lb, cp_mode{ignore_bins off_mode = binsof (cp_lb.loopback_off);}

  endgroup



  covergroup cg_delay;
    option.per_instance = 1;

    // DELAY register value at the time the transfer completed
    cp_delay: coverpoint cv_delay {
      bins d0 = {8'h00};  // no gap — back-to-back transfers
      bins d1 = {8'h01};  // minimum gap (1 SCLK half-cycle)
      bins d2_15 = {[8'h02 : 8'h0F]};
      bins d16_127 = {[8'h10 : 8'h7F]};
      bins d128_255 = {[8'h80 : 8'hFF]};  // large gap
    }

    // Was another TX word waiting when the transfer finished?
    // 1 = gap actually fires; 0 = DELAY>0 but FIFO drained, no gap
    cp_queued: coverpoint cv_delay_queued {
      bins no_next_word = {1'b0}; bins has_next_word = {1'b1};
    }

    // Delay value × queued state.  DELAY=0 rows are excluded because
    // a zero delay never produces a gap regardless of FIFO state.
    cx_delay_queued: cross cp_delay, cp_queued{
      ignore_bins d0_any = binsof (cp_delay.d0);
    }

  endgroup



  covergroup cg_rst;
    option.per_instance = 1;

    // Which register was read
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

    // Did the value match the spec-defined reset value?
    cp_rst_val_ok: coverpoint cv_rst_val_ok {
      bins correct_rst_values = {1'b1};
    }

    // Both conditions must hold for every register
    cx_addr_rst: cross cp_addr, cp_rst_val_ok;

  endgroup


  // =========================================================================
  // Section 3 — ADDITIONAL covergroups
  // =========================================================================

  covergroup cg_apb_reg;
    option.per_instance = 1;

    // Target register address
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

    // Read returned the expected value (write-read or known-RO value)
    cp_readback: coverpoint cv_readback {
      bins data_match = {1'b1};
    }

    // Every register must be read and its value confirmed correct
    cx_addr_readback: cross cp_addr, cp_readback;

  endgroup


  covergroup cg_apb_protocol;
    option.per_instance = 1;

    // Register being accessed
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

    // Access direction
    cp_rw: coverpoint cv_is_write {
      bins read = {1'b0}; bins write = {1'b1};
    }

    // PSLVERR must always be 0 — any 1 here is a DUT bug
    cp_pslverr: coverpoint cv_pslverr {
      bins never_high = {1'b0};
    }

    // PREADY must always be 1 (zero wait states)
    cp_pready: coverpoint cv_pready {
      bins always_ready = {1'b1};
    }

    // Full cross: reg × direction × handshake correctness
    cx_addr_rw_protocol: cross cp_addr, cp_rw, cp_pslverr, cp_pready;

  endgroup



  covergroup cg_overflow;
    option.per_instance = 1;

    // TX write attempted while TX FIFO was already full
    cp_tx_ovf: coverpoint cv_tx_ovf {
      bins no_ovf = {1'b0}; bins ovf = {1'b1};  // must be triggered at least once
    }

    // RX push received while RX FIFO was already full (data lost)
    cp_rx_ovf: coverpoint cv_rx_ovf {
      bins no_ovf = {1'b0}; bins ovf = {1'b1};
    }

    // APB read of RX_DATA when the FIFO was empty (returns 0, no pop)
    cp_rx_empty_read: coverpoint cv_rx_empty_read {
      bins no_empty_read = {1'b0}; bins empty_read = {1'b1};
    }

  endgroup


  covergroup cg_ctrl_en;
    option.per_instance = 1;

    // Current EN state
    cp_en: coverpoint cv_ctrl_en {
      bins enabled = {1'b1}; bins disabled = {1'b0};
    }

    // TX FIFO empty while EN=0 (FIFO must drain on disable)
    cp_tx_empty_en0: coverpoint cv_tx_empty_en0 {
      bins fifo_empty_during_en0 = {1'b1};
    }

    // RX FIFO empty while EN=0
    cp_rx_empty_en0: coverpoint cv_rx_empty_en0 {
      bins fifo_empty_during_en0 = {1'b1};
    }

    // SCLK held at CPOL idle level while EN=0
    cp_sclk_idle: coverpoint cv_sclk_idle {
      bins at_cpol = {1'b1};
    }

    // SS_n forced high even though SS_CTRL.ss_en was non-zero.
    // This is the non-trivial case: EN=0 must override an active SS_CTRL.
    cp_ss_high: coverpoint cv_ss_high {
      bins forced_high = {1'b1};
    }

    // Crosses are restricted to the EN=0 branch only
    cx_en0_tx: cross cp_en, cp_tx_empty_en0{
      ignore_bins en1 = binsof (cp_en.enabled);
    }
    cx_en0_rx: cross cp_en, cp_rx_empty_en0{ignore_bins en1 = binsof (cp_en.enabled);}
    cx_en0_sclk: cross cp_en, cp_sclk_idle{ignore_bins en1 = binsof (cp_en.enabled);}
    cx_en0_ss: cross cp_en, cp_ss_high{ignore_bins en1 = binsof (cp_en.enabled);}

  endgroup


  covergroup cg_ss;
    option.per_instance = 1;

    // Which slave lane(s) are enabled via ss_en
    cp_ss_en: coverpoint cv_ss_en {
      bins ss0_only = {4'b0001};  // lane 0 selected
      bins ss1_only = {4'b0010};  // lane 1 selected
      bins ss2_only = {4'b0100};  // lane 2 selected
      bins ss3_only = {4'b1000};  // lane 3 selected
      bins none = {4'b0000};  // no lane active
      bins multiple = {[4'b0011 : 4'b1111]};  // multi-lane select
    }

    // ss_val override: non-zero forces the corresponding SS_n high
    // regardless of ss_en, exercising the full SS_n formula.
    cp_ss_val: coverpoint cv_ss_val {
      bins val_zero = {4'b0000};  // normal: SS_n = ~ss_en
      bins val_any = {[4'b0001 : 4'b1111]};  // override path active
    }

    // Cross ensures the formula is tested in both override directions
    cx_ss_en_val: cross cp_ss_en, cp_ss_val;

  endgroup


  covergroup cg_reserved;
    option.per_instance = 1;

    // Reserved address accessed
    cp_reserved_addr: coverpoint cv_reserved_addr {
      bins res_24 = {8'h24}; bins res_28 = {8'h28}; bins res_other = {[8'h2C : 8'hFF]};
    }

    // Both a read (must return 0) and a write (must be ignored) are required
    cp_rw: coverpoint cv_reserved_is_write {
      bins read = {1'b0}; bins write = {1'b1};
    }

    cx_addr_rw: cross cp_reserved_addr, cp_rw;

  endgroup


  covergroup cg_busy;
    option.per_instance = 1;

    // Observed BUSY state
    cp_busy: coverpoint cv_busy {
      bins idle = {1'b0}; bins active = {1'b1};  // must be seen for every width below
    }

    // Width active when BUSY was sampled (dedicated variable, not cv_width)
    cp_width: coverpoint cv_busy_width {
      bins w8 = {2'b00}; bins w16 = {2'b01}; bins w32 = {2'b10};
    }

    // BUSY=1 must be confirmed at each transfer width; idle rows skipped
    cx_busy_width: cross cp_busy, cp_width{
      ignore_bins idle_any_width = binsof (cp_busy.idle);
    }

  endgroup


  // =========================================================================
  // Section 4 — Constructor
  // =========================================================================

  function new();
    // Mandatory groups
    cg_spi_cfg      = new();
    cg_clk_div      = new();
    cg_fifo_occ     = new();
    cg_irq          = new();
    cg_loopback     = new();
    cg_delay        = new();
    cg_rst          = new();
    // Additional groups
    cg_apb_reg      = new();
    cg_apb_protocol = new();
    cg_overflow     = new();
    cg_ctrl_en      = new();
    cg_ss           = new();
    cg_reserved     = new();
    cg_busy         = new();
  endfunction


  // =========================================================================
  // Section 5 — Sample tasks
  // =========================================================================

  task sample_config(input bit [1:0] mode, input bit lsb_first, input bit [1:0] width,
                     input bit loopback = 1'b0);
    cv_mode      = mode;
    cv_lsb_first = lsb_first;
    cv_width     = width;
    cv_loopback  = loopback;
    // cv_ctrl_en is NOT updated here — call sample_ctrl_en() separately
    cg_spi_cfg.sample();
    cg_loopback.sample();
  endtask


  task sample_apb(input bit [7:0] addr, input bit is_write, input bit [31:0] wdata,
                  input bit [31:0] rdata, input bit pslverr = 1'b0, input bit pready = 1'b1);
    cv_pslverr  = pslverr;
    cv_pready   = pready;
    cv_addr     = addr;
    cv_is_write = is_write;

    if (is_write) begin
      // Shadow writable registers; skip RO ones to avoid false readback matches
      case (addr)
        8'h04:   ;  // STATUS  — read-only, do not shadow
        8'h0C:   ;  // RX_DATA — read-only, do not shadow
        default: cv_last_written[addr] = wdata;
      endcase
      cg_apb_protocol.sample();

    end else begin
      // Read path: determine whether the returned value is correct
      // Note: cv_addr already holds addr from the assignment above

      case (addr)
        8'h04: cv_readback = 1'b1;  // STATUS value changes; reads always count

        // RX_DATA is RO — never shadowed on writes, so we just confirm
        // the register was read (value correctness is the scoreboard's job)
        8'h0C: cv_readback = 1'b1;

        // TX_DATA is WO — spec says reads return 0
        8'h08: cv_readback = (rdata == 32'h0);

        // INT_STAT is W1C and changes frequently; confirm it was read
        8'h1C: cv_readback = 1'b1;

        // All other registers: compare meaningful bits against last write
        default: begin
          if (cv_last_written.exists(addr)) begin
            case (addr)
              8'h10: cv_readback = (rdata[15:0] == cv_last_written[addr][15:0]);  // CLK_DIV [15:0]
              8'h14: cv_readback = (rdata[7:0] == cv_last_written[addr][7:0]);  // SS_CTRL [7:0]
              8'h18: cv_readback = (rdata[4:0] == cv_last_written[addr][4:0]);  // INT_EN  [4:0]
              8'h20: cv_readback = (rdata[7:0] == cv_last_written[addr][7:0]);  // DELAY   [7:0]
              default: cv_readback = (rdata == cv_last_written[addr]);
            endcase
          end else begin
            cv_readback = 1'b0;  // no prior write recorded
          end
        end
      endcase

      cg_apb_reg.sample();
      cg_apb_protocol.sample();
    end
  endtask

  task sample_reset(input bit [7:0] addr, input bit rst_val_ok);
    cv_addr       = addr;
    cv_rst_val_ok = rst_val_ok;
    cg_rst.sample();
  endtask

  task sample_clk_div(input bit [15:0] div);
    cv_clk_div = div;
    cg_clk_div.sample();
  endtask

  task sample_fifo(input int tx_occ, input int rx_occ);
    cv_tx_occ = tx_occ;
    cv_rx_occ = rx_occ;
    cg_fifo_occ.sample();
  endtask

  task sample_overflow(input bit tx_ovf = 1'b0, input bit rx_ovf = 1'b0,
                       input bit rx_empty_rd = 1'b0);
    cv_tx_ovf        = tx_ovf;
    cv_rx_ovf        = rx_ovf;
    cv_rx_empty_read = rx_empty_rd;
    cg_overflow.sample();
  endtask


  task sample_irq(input bit [4:0] int_stat, input bit [4:0] int_en, input bit [4:0] w1c_mask = 5'b0,
                  input bit [4:0] w1c_race_mask = 5'b0);
    // Sanity check: race bits cannot exist without a matching W1C write
    if ((w1c_race_mask & ~w1c_mask) != 5'b0)
      $error(
          "[COV] sample_irq: race_mask 0x%0h has bits outside w1c_mask 0x%0h",
          w1c_race_mask,
          w1c_mask
      );

    cv_int_stat      = int_stat;
    cv_int_en        = int_en;
    cv_masked_stat   = int_stat & ~int_en;  // bits captured while their enable is off
    cv_w1c_mask      = w1c_mask;
    cv_w1c_race_mask = w1c_race_mask;
    cg_irq.sample();
  endtask


  task sample_ss(input bit [3:0] ss_en, input bit [3:0] ss_val = 4'b0);
    cv_ss_en  = ss_en;
    cv_ss_val = ss_val;
    cg_ss.sample();
  endtask


  task sample_delay(input bit [7:0] delay_val, input bit queued = 1'b0);
    cv_delay        = delay_val;
    cv_delay_queued = queued;
    cg_delay.sample();
  endtask



  task sample_reserved(input bit [7:0] addr, input bit is_write = 1'b0);
    cv_reserved_addr     = addr;
    cv_reserved_is_write = is_write;
    cg_reserved.sample();
  endtask



  task sample_busy(input bit busy, input bit [1:0] width = 2'b00);
    cv_busy       = busy;
    cv_busy_width = width;
    cg_busy.sample();
  endtask



  task sample_ctrl_en(input bit en, input bit sclk, input bit [1:0] mode, input bit [3:0] ss_n,
                      input bit [3:0] ss_en, input int tx_occ, input int rx_occ);
    bit cpol = mode[1];
    cv_ctrl_en = en;

    if (!en) begin
      cv_tx_empty_en0 = (tx_occ == 0);
      cv_rx_empty_en0 = (rx_occ == 0);
      cv_sclk_idle    = (sclk == cpol);
      // Only meaningful when ss_en≠0: proves EN=0 overrides an active SS_CTRL
      cv_ss_high      = (ss_en != 4'b0) && (&ss_n);
    end else begin
      // Clear EN=0 flags so those bins are only hit from the EN=0 branch
      cv_tx_empty_en0 = 1'b0;
      cv_rx_empty_en0 = 1'b0;
      cv_sclk_idle    = 1'b0;
      cv_ss_high      = 1'b0;
    end

    cg_ctrl_en.sample();
  endtask


endclass

`endif  // SPI_COVERAGE_COL_SV
