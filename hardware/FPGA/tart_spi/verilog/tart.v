`timescale 1ns/1ps

//  _____      _      ____    _____
// |_   _|    / \    |  _ \  |_   _|
//   | |     / _ \   | |_) |   | |
//   | |    / ___ \  |  _ <    | |
//   |_|   /_/   \_\ |_| \_\   |_|
//

`include "tartcfg.v"

module tart
  #(// Memory controller parameters:
    parameter SDRAM_STARTUP_CYCLES = 10100, // -- 100us, plus a little more, @100MHz
`ifdef __512Mb_SDRAM
    parameter SDRAM_COLUMN_BITS    = 10, // 8 for standard papilio pro
    parameter SDRAM_ADDRESS_WIDTH  = 25, // 22 for standard papilio pro
    parameter CYCLES_PER_REFRESH   = 780, // (64000*100)/8192-1 Cycled as (64ms @100MHz)/8192 rows
`else
    parameter SDRAM_COLUMN_BITS    = 8,     // 8 for standard papilio pro
    parameter SDRAM_ADDRESS_WIDTH  = 22,    // 22 for standard papilio pro
    parameter CYCLES_PER_REFRESH   = 1524,  // (64000*100)/4096-1 Cycled as (64ms @100MHz)/4096 rows
`endif // !`ifdef __512Mb_SDRAM
    parameter SSB                  = SDRAM_ADDRESS_WIDTH-2,

    //  Antenna/signal parameters:
    parameter ANTENNAE = `NUM_ANTENNA,
    parameter NSB      = ANTENNAE-1,
    parameter RNG      = `RANDOM_DATA,

    //  Simulation parameters:
    parameter DELAY    = `DELAY)     // Simulation gate-delay setting
   (
    // SDRAM
    output wire        SDRAM_CLK,
    output wire        SDRAM_CKE,
    output wire        SDRAM_CS,
    output wire        SDRAM_RAS,
    output wire        SDRAM_CAS,
    output wire        SDRAM_WE,
    output wire [1:0]  SDRAM_DQM,
    output wire [12:0] SDRAM_ADDR,
    output wire [1:0]  SDRAM_BA,
    inout wire [15:0]  SDRAM_DQ,
   
    // SPI
    input              SPI_SCK,
    input              SPI_SSEL,
    input              SPI_MOSI,
    output wire        SPI_MISO,
   
    // TELESCOPE
    input              rx_clk_16, // 16.368 MHz receiver master clock
    input [NSB:0]      antenna, // Radio Data Interface

    // MISCELLANEOUS
	  output wire        rx_clk_test_pin, // show delayed clock
    output wire        led              // Papilio LED
    );

   (* PERIOD = "10.18 ns" *) wire fpga_clk;
   (* PERIOD = "10.18 ns" *) wire rx_clk;
   (* PERIOD = "5.091 ns" *) wire clk_x;
   (* KEEP   = "TRUE"     *) wire reset;

   wire                reset_n;

   //  SDRAM memory-controller signals:
   wire                cmd_enable, cmd_ready, cmd_wr;
   wire [SSB:0]        cmd_address;
   wire [31:0]         cmd_data_in;
   wire [31:0]         data_out;

   wire                request_from_spi;
   wire [2:0]          tart_state;
   wire                switching;

   //  Force these signals to be kept, so that they can be referenced in the
   //  constraints file (as they have the `TIG` constraint applied).
   (* KEEP = "TRUE" *) wire aq_enabled;
   (* KEEP = "TRUE" *) wire vx_enabled;
   (* KEEP = "TRUE" *) wire [2:0] aq_delay;
   (* KEEP = "TRUE" *) wire aq_debug;
   (* KEEP = "TRUE" *) wire stuck;
   (* KEEP = "TRUE" *) wire limp;
   (* KEEP = "TRUE" *) wire [NSB:0] ax_dat;

//    assign led = tart_state >= 2; // asserted when data can be read back
   (* KEEP = "TRUE" *) reg [27:0] cnt28 = 28'b0;

   assign led = tart_state >= 2 && cnt28[27];
	 assign rx_clk_test_pin = rx_clk;

   always @(posedge clk_x)
     cnt28 <= #DELAY cnt28 + 1'b1;


   //-------------------------------------------------------------------------
   //     GENERATE TART SYSTEM CLOCKS
   //-------------------------------------------------------------------------
`ifdef __USE_OLD_CLOCKS
   tart_clk_generator clknetwork
     (
      .CLKIN(rx_clk_16),        // 16.368 MHz
      .CLKOUT0(rx_clk_16_buf),  // 16.368 MHz buffered
      .CLKOUT1(fpga_clk),       // 16.368x6 = 98.208 MHz
      .reset_n(reset_n)
      );

`else
   tart_dcm TART_DCM0
     ( .clk_pin(rx_clk_16),     // 16.368 MHZ
       .clk_rst(1'b0),
       .clk(rx_clk_16_buf),     // 16.368 MHz buffered
       .reset_n(reset_n),
       .status_n(status_n),
       .clk6x(fpga_clk),        // 16.368x6  =  98.208 MHz
       .clk12x(clk_x)           // 16.368x12 = 196.416 MHz
       );
`endif // !__USE_OLD_CLOCKS


   //-------------------------------------------------------------------------
   //  
   //  TART ANTENNA DATA CAPTURE BLOCK
   //  
   //-------------------------------------------------------------------------
   tart_capture
     #(.AXNUM(ANTENNAE),
       .ABITS(SDRAM_ADDRESS_WIDTH),
       .RNG  (RNG)
       ) CAP0
     ( .clk_i     (fpga_clk),
       .clk_x     (clk_x),
       .clk_e     (rx_clk_16_buf),
       .clk_d     (rx_clk),
       .rst_i     (reset),

       .mcb_ce_o  (cmd_enable),
       .mcb_wr_o  (cmd_wr),
       .mcb_rdy_i (cmd_ready),
       .mcb_adr_o (cmd_address),
       .mcb_dat_o (cmd_data_in),

       .aq_ce_i   (aq_enabled),
       .aq_delay_i(aq_delay),
       .aq_debug_i(aq_debug),
       .ax_data_i (antenna),
       .ax_data_o (ax_dat),
       .rd_req_i  (request_from_spi),

       .tart_state(tart_state)
       );


   //  No acquisition means that the memory-controller isn't needed.
`ifdef __USE_ACQUISITION
   //-------------------------------------------------------------------------
   //  
   //  SDRAM CONTROLLER FOR THE RAW ANTENNA DATA
   //  
   //-------------------------------------------------------------------------
   SDRAM_Controller_v
   #(
      .sdram_address_width(SDRAM_ADDRESS_WIDTH),
      .sdram_column_bits(SDRAM_COLUMN_BITS),
      .sdram_startup_cycles(SDRAM_STARTUP_CYCLES),
      .cycles_per_refresh(CYCLES_PER_REFRESH)
   )
   hamster_sdram(
      .clk(fpga_clk),
      .reset(reset),
      .cmd_ready(cmd_ready),
      .cmd_enable(cmd_enable),
      .cmd_wr(cmd_wr),
      .cmd_address(cmd_address),
      .cmd_byte_enable(4'b1111),
      .cmd_data_in(cmd_data_in),
      .data_out(data_out),
      .data_out_ready(data_out_ready),

      .SDRAM_CLK(SDRAM_CLK),
      .SDRAM_CKE(SDRAM_CKE),
      .SDRAM_CS(SDRAM_CS),
      .SDRAM_RAS(SDRAM_RAS),
      .SDRAM_CAS(SDRAM_CAS),
      .SDRAM_WE(SDRAM_WE),
      .SDRAM_DQM(SDRAM_DQM),
      .SDRAM_ADDR(SDRAM_ADDR),
      .SDRAM_BA(SDRAM_BA),
      .SDRAM_DATA(SDRAM_DQ)
   );
`else // !`ifdef __USE_ACQUISITION

   //  Drive zeros onto the unused pins:
   assign cmd_ready = 1'b0;
   assign data_out_ready = 1'b0;
   assign data_out = 32'b0;

   assign SDRAM_CS   = 1'b1;
   assign SDRAM_CKE  = 1'b0;
   (* PULLUP = "TRUE" *) assign SDRAM_CLK  = 1'bz;
   (* PULLUP = "TRUE" *) assign SDRAM_WE   = 1'bz;
   (* PULLUP = "TRUE" *) assign SDRAM_RAS  = 1'bz;
   (* PULLUP = "TRUE" *) assign SDRAM_CAS  = 1'bz;
   (* PULLUP = "TRUE" *) assign SDRAM_BA   = 2'bz;
   (* PULLUP = "TRUE" *) assign SDRAM_ADDR = 13'bz;
   (* PULLUP = "TRUE" *) assign SDRAM_DQM  = 2'bz;
   (* PULLUP = "TRUE" *) assign SDRAM_DQ   = 16'bz;

`endif // !`ifdef __USE_ACQUISITION


   //-------------------------------------------------------------------------
   //
   //  TART's system-wide, Wishbone-like interconnect and peripherals.
   //
   //-------------------------------------------------------------------------
   //  Visibilities/correlator settings.
   parameter ACCUM = `ACCUM_BITS; // Bit-width of the accumulators
   parameter BLOCK = ACCUM;       // Maximum #bits of the block-size
   parameter MSB   = BLOCK-1;     // Data transfer MSB
   parameter TRATE = `TMUX_RATE;  // Time-multiplexing rate
   parameter COUNT = `VISB_LOG2;  // (1 << 3) - 1;
   parameter NREAD = `READ_COUNT; // Number of visibilities to read back
   parameter RBITS = `READ_BITS;  // = ceiling{log2(NREAD)};
   parameter RSB   = RBITS-1;     // MSB of read-back address

   //  Wishbone settings.
   parameter BBITS = `WBBUS_BITS; // Bit-width of the SoC Wishbone bus
   parameter BSB   = BBITS-1;     // Bus data MSB
   parameter WSB   = BBITS-2;     // SPI -> WB bus address-width
   parameter ABITS = `WBADR_BITS; // Correlator bus address bit-width
   parameter ASB   = ABITS-1;     // Address MSB
   parameter XBITS = `BLOCK_BITS; // Bit-width of the block-counter
   parameter XSB   = XBITS-1;     // MSB of the block-counter

   //  SPI -> WB bus signals.
   wire [BSB:0] b_dtx;   // bus master's signals
   wire [BSB:0] b_drx;
   wire [WSB:0] b_adr;
   wire         b_cyc, b_stb, b_we, b_ack;

   wire [BSB:0] r_drx;   // reset handler's signals
   wire [BSB:0] r_dtx;
   wire         r_stb, r_ack;

   wire [BSB:0] a_drx;   // data-acquisition controller's signals
   wire [BSB:0] a_dtx;
   wire [3:0]   a_adr = b_adr[3:0];
   wire         a_stb, a_ack;

   reg          r_sel = 0;
   reg          a_sel = 0;

   //  WB signals for the streaming interface to the visibilities data.
   wire [BSB:0] s_dat;
   wire [XSB:0] v_blk;
   wire         s_cyc, s_stb, s_we, s_ack;

   //  Acquisition-unit signals.
   wire         newblock, streamed, accessed, available;
   wire [MSB:0] blocksize;
   (* KEEP = "TRUE" *) wire [MSB:0] checksum;
   (* KEEP = "TRUE" *) wire uflow, oflow;

   //  Remap system signals to WB signals.
   assign b_clk = fpga_clk;
   assign b_rst = reset;


   //-------------------------------------------------------------------------
   //     TRANSMISSION BLOCK
   //     SPI SLAVE & WB MASTER
   //-------------------------------------------------------------------------
   wire spi_busy;
   wire [7:0] spi_status = {uflow, oflow, request_from_spi, aq_enabled,
                            aq_debug, tart_state[2:0]};

   assign r_dtx = b_drx;        // redirect output-data to slaves
   assign a_dtx = b_drx;

   //  Address decoders for the Wishbone(-like) bus:
   assign a_stb = b_adr[6:4] == 3'h0 && b_stb; // decoder for acquire
   assign r_stb = b_adr[6:3] == 4'hf && b_stb; // address decoder for reset unit

   assign b_ack = r_ack || a_ack;
`ifdef __icarus
   assign b_dtx = r_stb || r_sel ? r_drx : (a_stb || a_sel ? a_drx : 'bz);
`else
   assign b_dtx = r_stb || r_sel ? r_drx : a_drx;
`endif

   //-------------------------------------------------------------------------
   //  Keep the selected device active until the transaction has been
   //  acknowledged.
   always @(posedge b_clk)
     if (b_rst || !b_cyc)
       {a_sel, r_sel} <= #DELAY 2'b00;
     else begin
        r_sel <= #DELAY r_sel ? !r_ack || r_stb : r_stb;
        a_sel <= #DELAY a_sel ? !a_ack || a_stb : a_stb;
     end


   //-------------------------------------------------------------------------
   //     SPI SLAVE CORE with a WISHBONE(-like) INTERCONNECT
   //-------------------------------------------------------------------------
   spi_slave #( .WIDTH(BBITS) ) SPI_SLAVE0
     ( .clk_i(b_clk),
       .rst_i(b_rst),
       .cyc_o(b_cyc),
       .stb_o(b_stb),
       .we_o (b_we),
       .ack_i(b_ack),
       .adr_o(b_adr),
       .dat_i(b_dtx),
       .dat_o(b_drx),

       .active_o(spi_busy),
       .status_i(spi_status),
       .overflow_o(oflow),
       .underrun_o(uflow),
       
       .SCK_pin(SPI_SCK),
       .MOSI(SPI_MOSI),
       .MISO(SPI_MISO),
       .SSEL(SPI_SSEL)
       );

   //-------------------------------------------------------------------------
   //     RESET HANDLER
   //-------------------------------------------------------------------------
   tart_control #( .WIDTH(BBITS), .RTIME(4) ) TART_CONTROL0
     ( .clk_i(b_clk),
       .rst_i(b_rst),
       .cyc_i(b_cyc),
       .stb_i(r_stb),
       .we_i (b_we),
       .ack_o(r_ack),
       .adr_i(b_adr[1:0]),
       .dat_i(r_dtx),
       .dat_o(r_drx),

       .status_i  (spi_status),
       .reset_ni  (reset_n),
       .reset_o   (reset),
       .checksum_i(checksum)
       );


   //-------------------------------------------------------------------------
   //     DATA-ACQUISITION CONTROL AND READ-BACK.
   //-------------------------------------------------------------------------
   tart_acquire #( .WIDTH(BBITS), .ACCUM(ACCUM) ) TART_ACQUIRE0
     ( // WB-like bus between SPI and TART's data:
       .clk_i(b_clk),
       .rst_i(reset),
       .cyc_i(b_cyc),
       .stb_i(a_stb),
       .we_i (b_we),
       .ack_o(a_ack),
       .adr_i(a_adr),
       .dat_i(a_dtx),
       .dat_o(a_drx),

       //  DRAM (streaming) read-back signals:
       .data_ready  (data_out_ready),
       .data_request(request_from_spi),
       .data_in     (data_out[MSB:0]),

       .spi_busy(spi_busy),

       //  Visibilities status & data access:
       .vx_cyc_o(s_cyc),     // WB-like bus for visibilities read-back
       .vx_stb_o(s_stb),
       .vx_we_o (s_we ),
       .vx_ack_i(s_ack),
       .vx_blk_o(v_blk),
       .vx_dat_i(s_dat),

       .newblock (newblock), // strobes when new block ready
       .streamed (streamed), // has an entire block finished streaming?
       .accessed (accessed), // asserts once visibilities are read back
       .available(available),
       .checksum (checksum),
       .blocksize(blocksize),

       .vx_enabled(vx_enabled),
       .vx_stuck_i(stuck),
       .vx_limp_i (limp),

       //  Antenna capture & acquisition controls:
       .aq_debug_mode(aq_debug),
       .aq_enabled(aq_enabled),
       .aq_sample_delay(aq_delay),
//        .aq_adr_i(cmd_address)
       .aq_adr_i({21'h0, v_blk})
       );


`ifdef __USE_CORRELATORS
   //-------------------------------------------------------------------------
   //     
   //     CORRELATOR / VISIBILITIES BLOCK.
   //     
   //-------------------------------------------------------------------------
 `ifdef __USE_FAKE_DSP
   tart_fake_dsp
 `else
   tart_dsp
 `endif
     #(.NREAD(NREAD)
       ) DSP
     ( .clk_x(clk_x),
       .rst_i(reset),
       .aq_clk_i(b_clk),        // Bus between DSP and acquisition unit
       .aq_cyc_i(s_cyc),
       .aq_stb_i(s_stb),
       .aq_we_i (s_we),
       .aq_bst_i(1'b0),
       .aq_ack_o(s_ack),
       .aq_blk_i(v_blk),
       .aq_dat_i(8'bx),
       .aq_dat_o(s_dat),

       .stuck_o  (stuck),
       .limp_o   (limp),

       .aq_enable(aq_enabled),
       .vx_enable(vx_enabled),
       .antenna  (ax_dat),
       .blocksize(blocksize),
       .switching(switching),
       .newblock (newblock),
       .checksum (checksum),
       .streamed (streamed)
       );
 `endif //  `ifdef __USE_CORRELATORS


endmodule // tart
