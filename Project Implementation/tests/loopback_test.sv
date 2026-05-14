//- TP-LB-01
`ifndef LOOPBACK_TEST_SV
`define LOOPBACK_TEST_SV 

localparam [7:0] APB_CTRL = 8'h00;
localparam [7:0] APB_STATUS = 8'h04;
localparam [7:0] APB_TX_DATA = 8'h08;
localparam [7:0] APB_RX_DATA = 8'h0C;
localparam [7:0] APB_CLK_DIV = 8'h10;
localparam [7:0] APB_SS_CTRL = 8'h14;
localparam [7:0] APB_INT_EN = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY = 8'h20;

class loopback_test;

  static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);

    bit [31:0] tx_word;
    bit [31:0] rd;
    bit [31:0] miso_word;
    bit        timed_out;
    bit [ 1:0] width_enc;
    int        width_bits;
    int        w;
    int        o;
    bit        lsb_first;

    $display("[INFO] loopback_test: starting");


    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'h0000_0002);
    tb_top.u_apb_bfm.apb_write(APB_DELAY, 32'h0);


    // Loop over widths: 8, 16, 32
    for (w = 0; w < 3; w++) begin
      case (w)
        0: begin
          width_enc = 2'b00;
          width_bits = 8;
          tx_word = 32'h0000_00A5;
        end
        1: begin
          width_enc = 2'b01;
          width_bits = 16;
          tx_word = 32'h0000_A55A;
        end
        2: begin
          width_enc = 2'b10;
          width_bits = 32;
          tx_word = 32'hDEAD_BEEF;
        end
      endcase

      $display("started at width:%d", width_bits);
      // Loop over bit order: MSB-first (0), LSB-first (1)
      for (o = 0; o < 2; o++) begin
        lsb_first = (o == 1);
        miso_word = ~tx_word;  // hostile MISO

        $display("started at LSB/MSB:%d", lsb_first);
        // Configure slave BFM to match CTRL
        tb_top.bfm_mode      = 2'b00;
        tb_top.bfm_width     = width_enc;
        tb_top.bfm_lsb_first = lsb_first;
        tb_top.bfm_miso_word = miso_word;

        // CTRL: EN=1, MSTR=1, MODE=00, LSB_FIRST=lsb_first, LOOPBACK=1, WIDTH=width_enc
        tb_top.u_apb_bfm.apb_write(APB_CTRL, {24'h0, width_enc, 1'b1, lsb_first, 2'b00, 1'b1, 1'b1
                                   });

        // Assert SS0 low
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h1);

        // Predict expected RX (loopback => RX == TX)
        ref_model.predict_word(.tx_word(tx_word), .width_bits(width_bits), .loopback(1'b1),
                               .miso_word(miso_word));

        // Push TX
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, tx_word);

        // Poll BUSY with timeout
        timed_out = 1'b1;
        repeat (500) begin
          tb_top.u_apb_bfm.apb_read(APB_STATUS, rd);
          if (rd[0] == 1'b0) begin
            timed_out = 1'b0;
            break;
          end
        end

        if (timed_out)
          ref_model.checker_error("BUSY_TIMEOUT", $sformatf(
                                  "BUSY did not clear for width=%0d lsb=%0d", width_bits, lsb_first
                                  ));

        // Read RX and check
        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
        $display(rd);
        ref_model.check_rx_word(rd);

        // Sample coverage
        coverage.sample_config(.mode(2'b00), .lsb_first(lsb_first), .width(width_enc));

        // Deassert SS
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0);
      end
    end

    $display("[INFO] loopback_test: finished, errors=%0d", ref_model.error_count);
  endtask

endclass

`endif
