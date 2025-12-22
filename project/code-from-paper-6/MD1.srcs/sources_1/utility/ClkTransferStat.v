`timescale 1ns / 1ps

//transfers a static signal of variable width from any clockIn to clkOut with a two-stage synchronizer. 

module ClkTransferStat
#(
parameter Width = 1         //width of signal
)
(
                   input clkIn,
                   input clkOut,
                   input  [Width-1:0] sigIn,
                   output [Width-1:0] sigOut
);

reg [Width-1:0] sig_d0=1'b0;
always@(posedge clkIn) begin
   sig_d0 <= sigIn;
end
 
//transfer to clkOut with two-flip-flop synchronizer
(* ASYNC_REG = "TRUE" *) reg [Width-1:0] sig_d1=1'b0;
(* ASYNC_REG = "TRUE" *) reg [Width-1:0] sig_d2=1'b0;
 always@(posedge clkOut) begin
   sig_d1 <= sig_d0;
   sig_d2 <= sig_d1;
 end
 assign sigOut=sig_d2;
    
endmodule
