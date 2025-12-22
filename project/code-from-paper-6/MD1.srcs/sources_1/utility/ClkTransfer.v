`timescale 1ns / 1ps

//transfers a rising signal sigIn, which is ClkIn, into a signal that is valid for one clock cycle of clkOut. Since frequencies 
//might be different, and since sigIn might be valid for only one clock cycle, the input signal is first elongated by 2**extend clkIn-cylcles, 
//before transfering to clkOut with a two Flip-Flop synchronizer.

module ClkTransfer
#(
parameter extend = 2         //bit number of cnt; determines how much the signal will be extended
)
(
    input clkIn,
    input clkOut,
    input sigIn,
    output reg sigOut
);

//sigIn is valid only for one cycle clkIn, which might be too short to be capture with clkOut, so extend it     
 reg [extend-1:0] cnt=1'b0;
 reg sigIn_extend0=1'b0;
 always@(posedge clkIn) begin
   if (sigIn) begin
     cnt<=1'b1;
     sigIn_extend0<=1'b1;
   end else begin
     if (cnt!=1'b0)
       cnt<=cnt+1'b1;
     else 
       sigIn_extend0<=1'b0;
   end           
 end
 
//transfer to clkOut with two-flip-flop synchronizer
(* ASYNC_REG = "TRUE" *) reg sigIn_extend1=1'b0;
(* ASYNC_REG = "TRUE" *) reg sigIn_extend2=1'b0;
 reg [1:0] sigOut2=1'b0;
 always@(posedge clkOut) begin
   sigIn_extend1<=sigIn_extend0;
   sigIn_extend2<=sigIn_extend1;
   sigOut2<={sigOut2[0],sigIn_extend2};
   sigOut<=(sigOut2==2'b01);                   //search for rising slope
 end
 
    
endmodule
