`timescale 1ns / 1ps

//fifo with only two entries and no empty or full signals

module miniFIFO
#(
parameter width  =  6   //width of FIFO
)
(
  input             clk,      
  input [width-1:0] din,      
  input             wr_en,  
  input             rd_en,  
  output[width-1:0] dout    
);

reg  [width-1:0]   data[1:0];
reg                ptr_wr=1'b0,ptr_rd=1'b0;

assign dout = ptr_rd ? data[1] : data[0];
always @(posedge clk) begin
  if(wr_en) begin
    data[ptr_wr] <= din;
    ptr_wr=~ptr_wr;
  end
  if(rd_en) ptr_rd <= ~ptr_rd;
end
   
endmodule
