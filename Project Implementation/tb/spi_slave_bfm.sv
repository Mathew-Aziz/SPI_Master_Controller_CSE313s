// =============================================================================
// spi_slave_bfm.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal SPI slave responder. Drives MISO with a configurable pattern that
// is rotated on every sampled SCLK edge. Students should extend this to
// capture the MOSI stream into a queue and expose it to their scoreboard.
//
// This BFM mirrors the SPI mode from the DUT's CTRL register via a shared
// testbench "mode" input. Students MUST keep it in lock-step with CTRL.MODE
// when writing new tests.
// =============================================================================

`ifndef SPI_SLAVE_BFM_SV
`define SPI_SLAVE_BFM_SV 
`timescale 1ns / 1ps

module spi_slave_bfm (
          spi_if.slave        spi,
    input logic        [ 1:0] mode,       // {CPOL, CPHA}
    input logic        [ 7:0] miso_byte,  // legacy repeating pattern
    input logic        [31:0] miso_word,  // preferred response word (low WIDTH bits)
    input logic               lsb_first,  // 1=LSB-first
    input logic        [ 1:0] width       // 00=8, 01=16, 10=32, 11=reserved
);

  // Decode mode
  wire         cpol = mode[1];
  wire         cpha = mode[0];

  // Any SS active (at least one lane low)
  wire         ss_act = (spi.ss_n != 4'hF);

  // Previous values for edge detection
  logic        sclk_q;
  logic [ 3:0] ss_n_q;

  // Word capture state
  int          width_bits;
  int          bit_count;
  logic [31:0] mosi_accum;

  // Published observation (optional use via hierarchical reference)
  event        word_done;
  logic [31:0] last_mosi_word;
  int          last_width_bits;
  logic [ 1:0] last_mode;
  logic        last_lsb_first;
  logic [ 1:0] last_ss_lane;

  // -------------------------------- Init -----------------------------------
  initial begin
    spi.cb_slave.miso <= 1'b0;
    sclk_q = 1'b0;
    ss_n_q = 4'hF;
    bit_count = 0;
    mosi_accum = '0;
    last_mosi_word = '0;
    last_width_bits = 0;
    last_mode = 2'b00;
    last_lsb_first = 1'b0;
    last_ss_lane = 2'd0;
  end

  // ------------------------------ Main BFM ---------------------------------
  always @(posedge spi.pclk) begin
    // Width decode (safe default for reserved encoding)
    unique case (width)
      2'b00:   width_bits = 8;
      2'b01:   width_bits = 16;
      2'b10:   width_bits = 32;
      default: width_bits = 8;
    endcase

    if (!ss_act) begin
      // Idle: reset state and re-sync SCLK edge detector to CPOL
      bit_count <= 0;
      mosi_accum <= '0;
      spi.cb_slave.miso <= miso_byte[7];
      sclk_q <= cpol;
      ss_n_q <= spi.ss_n;
    end else begin
      // Edge detection
      logic sclk_rise, sclk_fall;
      sclk_rise = (sclk_q === 1'b0) && (spi.sclk === 1'b1);
      sclk_fall = (sclk_q === 1'b1) && (spi.sclk === 1'b0);

      // Decide shift vs sample edge (matches spec Table 4.1)
      logic do_shift, do_sample;

      // Mode0: shift fall, sample rise
      // Mode1: shift rise, sample fall
      // Mode2: shift rise, sample fall
      // Mode3: shift fall, sample rise
      if (cpha == 1'b0) begin
        do_sample = cpol ? sclk_fall : sclk_rise;
        do_shift  = cpol ? sclk_rise : sclk_fall;
      end else begin
        do_sample = cpol ? sclk_rise : sclk_fall;
        do_shift  = cpol ? sclk_fall : sclk_rise;
      end

      // On SS assertion edge: initialize capture and drive first MISO bit
      if (ss_n_q == 4'hF) begin
        bit_count <= 0;
        mosi_accum <= '0;
        spi.cb_slave.miso <= lsb_first ? miso_word[0] : miso_word[width_bits-1];
      end

      // Drive MISO on shift edge (launch edge)
      if (do_shift) begin
        int idx;
        idx = lsb_first ? bit_count : (width_bits - 1 - bit_count);

        // Minimal behavior: prefer miso_word bits; if you didn’t set it,
        // fall back to repeating miso_byte for bits beyond [7:0].
        if (idx < 8) spi.cb_slave.miso <= miso_word[idx];
        else spi.cb_slave.miso <= miso_byte[idx%8];
      end

      // Capture MOSI on sample edge
      if (do_sample) begin
        int dst;
        dst = lsb_first ? bit_count : (width_bits - 1 - bit_count);
        if (dst >= 0 && dst < 32) mosi_accum[dst] <= spi.mosi;

        // Word completion
        if (bit_count == width_bits - 1) begin
          last_mosi_word  <= mosi_accum;
          last_width_bits <= width_bits;
          last_mode       <= mode;
          last_lsb_first  <= lsb_first;

          // active lane (first low bit)
          if (spi.ss_n[0] == 1'b0) last_ss_lane <= 2'd0;
          else if (spi.ss_n[1] == 1'b0) last_ss_lane <= 2'd1;
          else if (spi.ss_n[2] == 1'b0) last_ss_lane <= 2'd2;
          else last_ss_lane <= 2'd3;

          ->word_done;

          // Prepare for next word without SS toggle (burst support)
          bit_count  <= 0;
          mosi_accum <= '0;
        end else begin
          bit_count <= bit_count + 1;
        end
      end

      // Update previous signals
      sclk_q <= spi.sclk;
      ss_n_q <= spi.ss_n;
    end
  end

endmodule

`endif  // SPI_SLAVE_BFM_SV
