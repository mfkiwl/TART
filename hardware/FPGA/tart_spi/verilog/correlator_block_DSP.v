`timescale 1ns/100ps
/*
 * Module      : verilog/correlator_block_DSP.v
 * Copyright   : (C) Tim Molteno     2016
 *             : (C) Max Scheel      2016
 *             : (C) Patrick Suggate 2016
 * License     : LGPL3
 * 
 * Maintainer  : Patrick Suggate <patrick.suggate@gmail.com>
 * Stability   : Experimental
 * Portability : only tested with Icarus Verilog
 * 
 * Time-multiplexed block of correlator-blocks, and this version uses the
 * Xilinx DSP48A1 primitives (of Spartan 6's).
 * 
 * NOTE:
 *  + typically several of these would be attached to a common set of antenna
 *    and a system bus;
 *  + a bank-switch command causes accumulator values to be cleared upon first
 *    access after a switch, by giving the accumulator a zero input;
 *  + the bus clock can be much slower than the correlation clock, as multi-
 *    port SRAM's are used;
 *  + bus transactions read from the currently-innactive bank, to prevent
 *    possible metastability/corruption;
 *  + potentially uses quite a lot of the FPGA's distributed-RAM resources;
 * 
 * Changelog:
 *  + 14/07/2016  --  initial file (rebuilt from `correlator_block.v`);
 * 
 */

`include "tartcfg.v"

module correlator_block_DSP
  #( parameter ACCUM = `ACCUM_BITS,
     // Pairs of antennas to correlate, for each block.
     parameter PAIRS0 = 120'hb1a191817161b0a090807060,
     parameter PAIRS1 = 120'hb3a393837363b2a292827262,
     parameter PAIRS2 = 120'hb5a595857565b4a494847464,
     parameter PAIRS3 = 120'hb1a191817161b0a090807060, // TODO:
     parameter MSB   = ACCUM - 1,
`ifdef __USE_SDP_DSRAM
     parameter ABITS = 12,
`else
     parameter ABITS = 7,
`endif
     parameter ASB   = ABITS - 1,
     parameter DELAY = 3)
   (
    input          clk_x, // correlator clock
    input          rst,

    // Wishbone-like bus interface for reading visibilities.
    input          clk_i, // bus clock
    input          cyc_i,
    input          stb_i,
    input          we_i, // writes are ignored
    input          bst_i, // Bulk Sequential Transfer?
    output         ack_o,
    input [ASB:0]  adr_i,
    input [MSB:0]  dat_i,
    output [MSB:0] dat_o,

    // Real and imaginary components from the antennas.
    input          sw, // switch banks
    input          en, // data is valid
    input [23:0]   re,
    input [23:0]   im,

    output reg     overflow_cos = 0,
    output reg     overflow_sin = 0
    );

   //-------------------------------------------------------------------------
   //  Wishbone-like bus interface.
   //-------------------------------------------------------------------------
   wire [MSB:0]    dats [0:3];
   wire [3:0]      stbs, acks, oc, os;
   reg [1:0]       dev = 0;
   reg             stb = 0;

   // Address decoders.
   wire            sel0 = adr_i[ASB:ASB-1] == 2'b00;
   wire            sel1 = adr_i[ASB:ASB-1] == 2'b01;
   wire            sel2 = adr_i[ASB:ASB-1] == 2'b10;
   wire            sel3 = adr_i[ASB:ASB-1] == 2'b11;

   // 4:1 multiplexer for returning requested visibilities.
   assign ack_o = cyc_i && stb && acks[dev];
   assign dat_o = dats[dev];
   assign stbs  = {4{stb_i}} & (1 << adr_i[ASB:ASB-1]);

   // TODO: Not really needed?
   always @(posedge clk_i)
     if (rst) stb <= #DELAY 0;
     else     stb <= #DELAY stb_i;

   always @(posedge clk_i)
     dev <= #DELAY adr_i[ASB:ASB-1];


   //-------------------------------------------------------------------------
   //  Correlator instances.
   //-------------------------------------------------------------------------
   correlator_DSP
     #(  .ACCUM(ACCUM),
         .PAIRS(PAIRS0),
         .DELAY(DELAY)
         ) CORRELATOR0
       ( .clk_x(clk_x),
         .rst(rst),

         .sw(clear),
         .en(en),
         .re(re),
         .im(im),
         .rd(x_rd_adr),
         .wr(x_wr_adr),

         .vld(vld),
         .vis(vis[WSB:0]),

         .overflow_cos(oc[0]),
         .overflow_sin(os[0])
         );

   correlator_DSP
     #(  .ACCUM(ACCUM),
         .PAIRS(PAIRS1),
         .DELAY(DELAY)
         ) CORRELATOR1
       ( .clk_x(clk_x),
         .rst(rst),

         .sw(clear),
         .en(en),
         .re(re),
         .im(im),
         .rd(x_rd_adr),
         .wr(x_wr_adr),

         .vld(),
         .vis(vis[WIDTH+WSB:WIDTH]),

         .overflow_cos(oc[1]),
         .overflow_sin(os[1])
         );

   correlator_DSP
     #(  .ACCUM(ACCUM),
         .PAIRS(PAIRS2),
         .DELAY(DELAY)
         ) CORRELATOR2
       ( .clk_x(clk_x),
         .rst(rst),

         .sw(clear),
         .en(en),
         .re(re),
         .im(im),
         .rd(x_rd_adr),
         .wr(x_wr_adr),

         .vld(),
         .vis(vis[WIDTH+WIDTH+WSB:WIDTH+WIDTH]),

         .overflow_cos(oc[2]),
         .overflow_sin(os[2])
         );

   correlator_DSP
     #(  .ACCUM(ACCUM),
         .PAIRS(PAIRS3),
         .DELAY(DELAY)
         ) CORRELATOR3
       ( .clk_x(clk_x),
         .rst(rst),

         .sw(clear),
         .en(en),
         .re(re),
         .im(im),
         .rd(x_rd_adr),
         .wr(x_wr_adr),

         .vld(),
         .vis(vis[WIDTH+WIDTH+WIDTH+WSB:WIDTH+WIDTH+WIDTH]),

         .overflow_cos(oc[3]),
         .overflow_sin(os[3])
         );

   
endmodule // correlator_block_DSP