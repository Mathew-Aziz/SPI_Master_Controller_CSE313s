// =============================================================================
// ref_model.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// A plain-SV reference model + scoreboard. It does not use UVM - it is a
// simple class that students instantiate from tb_top (`spi_ref_model u_ref =
// new();`) and update from their test programs.
//
// Students should extend this class to model the full spec: for the scaffold
// we model just enough to check the sanity_test.
// =============================================================================

`ifndef SPI_REF_MODEL_SV
`define SPI_REF_MODEL_SV 


class spi_ref_model;

  // Running error count. tb_top reads this to emit the final
  // [TEST_PASSED]/[TEST_FAILED] line.
  int        error_count      = 0;

  // Minimal predictor state (8-bit)
  bit [ 7:0] pred_rx_byte;
  bit [ 7:0] pred_tx_byte;

  // Extended predictor state (word-level)
  bit [31:0] pred_rx_word;
  int        pred_width_bits;
  bit        pred_lsb_first;
  bit        pred_loopback;

  function new();
    error_count     = 0;
    pred_rx_byte    = 8'h0;
    pred_tx_byte    = 8'h0;
    pred_rx_word    = 32'h0;
    pred_width_bits = 8;
    pred_lsb_first  = 1'b0;
    pred_loopback   = 1'b0;
  endfunction

  // ------------------------- Generic error helper --------------------------
  task checker_error(input string name, input string msg);
    $display("[CHECKER_ERROR] %s %s", name, msg);
    error_count++;
  endtask

  // ------------------------- Mask helper -----------------------------------
  function automatic [31:0] mask_from_width(input int width_bits);
    case (width_bits)
      8: mask_from_width = 32'h0000_00FF;
      16: mask_from_width = 32'h0000_FFFF;
      32: mask_from_width = 32'hFFFF_FFFF;
      default: mask_from_width = 32'h0000_00FF;
    endcase
  endfunction

  // ------------------------- Prediction (8-bit) -----------------------------
  // Predict the result of a loopback OR of an externally-fed MISO byte.
  task predict_single_byte(input bit [7:0] tx_byte, input bit [7:0] miso_pattern,
                           input bit loopback);
    pred_tx_byte = tx_byte;
    pred_rx_byte = loopback ? tx_byte : miso_pattern;
  endtask

  // ------------------------- Prediction (word) ------------------------------
  task predict_word(input bit [31:0] tx_word, input int width_bits, input bit loopback,
                    input bit [31:0] miso_word);
    pred_width_bits = width_bits;
    pred_loopback = loopback;
    pred_rx_word = loopback ?
        (tx_word & mask_from_width(width_bits)) : (miso_word & mask_from_width(width_bits));
  endtask

  // ------------------------- RX checks --------------------------------------
  task check_rx(input bit [31:0] observed);
    bit [7:0] obs = observed[7:0];
    if (obs !== pred_rx_byte) begin
      $display("[SCOREBOARD_ERROR] RX byte mismatch: predicted=0x%02h observed=0x%02h",
               pred_rx_byte, obs);
      error_count++;
    end
  endtask

  task check_rx_word(input bit [31:0] observed);
    bit [31:0] mask = mask_from_width(pred_width_bits);
    if ((observed & mask) !== (pred_rx_word & mask)) begin
      $display("[SCOREBOARD_ERROR] RX word mismatch: width=%0d predicted=0x%08h observed=0x%08h",
               pred_width_bits, pred_rx_word & mask, observed & mask);
      error_count++;
    end
  endtask

  // ------------------------- Register checks --------------------------------
  task check_reg(input string name, input bit [31:0] expected, input bit [31:0] observed);
    if (observed !== expected) begin
      $display("[SCOREBOARD_ERROR] %s mismatch: expected=0x%08h observed=0x%08h", name, expected,
               observed);
      error_count++;
    end
  endtask

  task check_reg_masked(input string name, input bit [31:0] expected, input bit [31:0] observed,
                        input bit [31:0] mask);
    if ((observed & mask) !== (expected & mask)) begin
      $display("[SCOREBOARD_ERROR] %s masked mismatch: expected=0x%08h observed=0x%08h mask=0x%08h",
               name, expected, observed, mask);
      error_count++;
    end
  endtask

  // ------------------------------ FIFO checks -------------------------------
  // Verify TX FIFO contents match expected order
  task verify_tx_fifo_order(input bit [31:0] expected_queue[$]);
    bit [31:0] tx_ptr_base = tb_top.u_wrap.u_dut.u_regfile.tx_rp;

    for (int i = 0; i < expected_queue.size(); i++) begin
      int fifo_idx = (tx_ptr_base + i) & 3'h7;  // wrap at 8
      bit [31:0] actual = tb_top.u_wrap.u_dut.u_regfile.tx_mem[fifo_idx];

      if (actual !== expected_queue[i]) begin
        $display("[SCOREBOARD_ERROR] TX_FIFO[%d] (mem[%d]) = 0x%08h, expected 0x%08h", i, fifo_idx,
                 actual, expected_queue[i]);
        error_count++;
      end
    end
  endtask

  // Check TX STATUS flags with meaningful names
  task check_tx_status(input [31:0] status, input bit expect_full, expect_empty, expect_busy);
    bit tx_full = status[1];
    bit tx_empty = status[2];
    bit busy = status[0];

    if (tx_full !== expect_full) begin
      $display("[SCOREBOARD_ERROR] TX_FULL=%b, expected=%b", tx_full, expect_full);
      error_count++;
    end
    if (tx_empty !== expect_empty) begin
      $display("[SCOREBOARD_ERROR] TX_EMPTY=%b, expected=%b", tx_empty, expect_empty);
      error_count++;
    end
    if (busy !== expect_busy) begin
      $display("[SCOREBOARD_ERROR] BUSY=%b, expected=%b", busy, expect_busy);
      error_count++;
    end
  endtask

  // Check TX STATUS flags with meaningful names
  task check_rx_status(input bit [31:0] status, input bit expect_full, expect_empty);
    bit rx_full = status[3];
    bit rx_empty = status[4];

    if (rx_full !== expect_full) begin
      $display("[SCOREBOARD_ERROR] RX_FULL=%b, expected=%b", rx_full, expect_full);
      error_count++;
    end
    if (rx_empty !== expect_empty) begin
      $display("[SCOREBOARD_ERROR] RX_EMPTY=%b, expected=%b", rx_empty, expect_empty);
      error_count++;
    end
  endtask

  //Drain TX FIFO
  task drain_tx_fifo();
    bit [31:0] rd = 0;
    tb_top.u_apb_bfm.apb_write(32'h14, 32'h0000_0001);
    repeat (500) begin
      tb_top.u_apb_bfm.apb_read(32'h04, rd);
      if (rd[0] == 1'b0) break;
    end
    check_reg_masked("STATUS", 8'b0000_0100, rd, 8'b0000_0100);
    tb_top.u_apb_bfm.apb_write(32'h14, 32'h0000_0000);  // deassert ss[0] HIGH
  endtask

  // ------------------------- Spec edge-case checks --------------------------
  task check_reserved_read_zero(input [7:0] addr, input [31:0] observed);
    if (observed !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] RESERVED read nonzero addr=0x%02h observed=0x%08h", addr,
               observed);
      error_count++;
    end
  endtask

  task check_tx_data_read_zero(input [31:0] observed);
    if (observed !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] TX_DATA read nonzero observed=0x%08h", observed);
      error_count++;
    end
  endtask

  task check_rx_empty_read_zero(input [31:0] observed, input [31:0] status_after);
    if (observed !== 32'h0) begin
      $display("[SCOREBOARD_ERROR] RX_EMPTY read nonzero observed=0x%08h", observed);
      error_count++;
    end
    // STATUS.RX_OVF is bit 6 per spec
    if (status_after[6] == 1'b1) begin
      $display("[SCOREBOARD_ERROR] RX_OVF set after empty read (should remain 0)");
      error_count++;
    end
  endtask

  // ------------------------- Prediction wrapper (for test compatibility) --------------------------
  task predict_transfer(input bit [31:0] tx_word, input int width = 8,
                        input bit [31:0] miso_word = 32'h0);
    // Default: loopback mode for delay_transfer_test (MISO driven by BFM as dummy echo)
    predict_word(.tx_word(tx_word), .width_bits(width), .loopback(1'b0), .miso_word(miso_word));
  endtask

  // ------------------------- RX FIFO state management --------------------------
  // Simple queue to track expected RX entries for drain verification
  bit [31:0] rx_queue[$];

  task push_rx_expected(input bit [31:0] expected_word);
    rx_queue.push_back(expected_word);
  endtask

  task pop_rx();
    if (rx_queue.size() > 0) begin
      void'(rx_queue.pop_front());
    end else begin
      $display("[CHECKER_ERROR] ref_model: pop_rx() called on empty expected queue");
      error_count++;
    end
  endtask

  function int rx_queue_size();
    return rx_queue.size();
  endfunction

  // ------------------------------------------------------------------
  // Reset helper: applies spec-compliant reset sequence
  // Spec Section 7.1: 
  //   - PRESETn active-low asynchronous assertion
  //   - Synchronous deassertion (internal synchronizer assumed)
  //   - Minimum assertion: PRESETn held low for at least 2 PCLK cycles
  // ------------------------------------------------------------------
  task apply_reset(input int min_cycles = 2);
    // Assert reset (active-low)
    tb_top.PRESETn = 1'b0;

    // Wait for min_cycles rising edges of PCLK (frequency-independent)
    // This ensures reset is held for ≥2 PCLK cycles regardless of clock speed
    repeat (min_cycles) @(posedge tb_top.PCLK);

    // Deassert reset synchronously to PCLK (spec requirement)
    tb_top.PRESETn = 1'b1;
    @(posedge tb_top.PCLK);  // Sync deassert to clock edge
  endtask

endclass

`endif  // SPI_REF_MODEL_SV
