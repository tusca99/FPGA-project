`timescale 1ns / 1ps

//Gated multiplexer with nPort input ports, each with width nByte. All inputs except of port 0 are buffered upon tx_req_port, and sent out
//with different priority (port 1; highest priority, port nPort-1: lowest priority). Port 0 is special, and has even higher priority than any
//of the other ports: It is sent through right away, and data can appear without break, whereas all other ports need a break of one clock 
//cycle minimum between requests. Hence, port0 does not need a buffer since delivery time is guaranteed. If one of the ports>0 receives a
//request before data are sent out, an error signal is generated. Never seen that error but has been tested with GatedMux_tb.      
//
//input:
//tx_req_port [nPort-1:0]            send request
//data_port   [nByte*nPort*8-1:0]    vector with all input data
//
//output                          
//tx_req                             data valid at the output
//dataout                            output data
//error                              error upun overflow of port_1...port_nPort-1

module GatedMultplx
#(
parameter nPort  =  4,    //number of Ports
parameter nByte  =  28   //byte width of each poret
)
(
  input                           IOclk,
  input       [nByte*nPort*8-1:0] data_port,
  input       [nPort-1:0]         tx_req_port,
  output reg                      tx_req,
  output reg  [nByte*8-1:0]       dataout,
  output                          error 
);
   
   
/*
//version with input FIFO. Has been briefly tested and worked. However, needs a lot of resources and seems to be an overkill, 
//but keep for the time being. Error not yet implemented (would be done based on full-signal    
localparam fifo_depth = 2;
localparam fd_log2    = 1;   

reg  [nByte*8-1:0]           fifo[fifo_depth-1:0][nPort-1:0];
reg  [(fd_log2+1)*nPort-1:0] ptr_wr=1'b0;     //add extra bit for full condition, see https://vlsiverify.com/verilog/verilog-codes/synchronous-fifo/
reg  [(fd_log2+1)*nPort-1:0] ptr_rd=1'b0;
reg  [nPort-1:0]             empty;
//reg  [nPort-1:0]             full;        //currently not implemented; could be used to generate an error signal

integer i;
always @(*) begin
  for(i=0;i<nPort;i=i+1) begin
    empty[i] <= ~(ptr_wr[i*(fd_log2+1)+:(fd_log2+1)]== ptr_rd[i*(fd_log2+1)+:(fd_log2+1)]);  //is 0 when empty
//    full[i]  <=  (ptr_wr[i*(fd_log2+1)+: fd_log2]   == ptr_rd[i*(fd_log2+1)+: fd_log2+1]) & (ptr_wr[i*(fd_log2+1)+fd_log2]^ptr_rd[i*(fd_log2+1)+fd_log2]);
  end
end  
    
always @(posedge IOclk) begin
  if(|empty==1'b0) tx_req <= 1'b0;           //no data in any of the ports
  for(i=0;i<nPort;i=i+1) begin 
    if(tx_req_port[i]) begin                                    //write into entrance fifo
      fifo[ptr_wr[i*(fd_log2+1)+:fd_log2]][i]   <= data_port[i*nByte*8+:nByte*8];
      ptr_wr[i*(fd_log2+1)+:(fd_log2+1)]        <= ptr_wr[i*(fd_log2+1)+:(fd_log2+1)] +1'b1;
    end
    if (((empty&(~({nPort{1'b1}}<<i)))==1'b0)&&empty[i]) begin   //will AND with 0000, 0001, 0011, ...  
      dataout                            <= fifo[ptr_rd[i*(fd_log2+1)+:fd_log2]][i];
      ptr_rd[i*(fd_log2+1)+:(fd_log2+1)] <= ptr_rd[i*(fd_log2+1)+:(fd_log2+1)] +1'b1;
      tx_req                             <= 1'b1;
    end
  end
end
*/


//old version, treats port0 privileged as it can send through straight without gap
reg  [nPort-2:0]              tx_req_reg   = 1'b0;  
reg  [nPort-2:0]              error_port   = 1'b0;  
reg  [nByte*8*(nPort-1)-1:0]  inbuff;
assign error = |error_port;

integer i;    
always @(posedge IOclk) begin
  if((|tx_req_reg==1'b0)&&(tx_req_port[0]==1'b0)) tx_req <= 1'b0;    //no data in any of the ports
  if(tx_req_port[0]) begin                        //treat port 0 priviledged
    tx_req        <= 1'b1;
    dataout       <= data_port[0+:nByte*8];
  end   
  for(i=1;i<nPort;i=i+1) begin                 //from remaining ports, port 1 has highest priority, all subsequent ports have succesively lower priority
    error_port[i-1] <= (tx_req_port[i]==1'b1)&&(tx_req_reg[i-1]==1'b1);  
    if(tx_req_reg[i-1]==1'b0) begin                  
      if (tx_req_port[i]==1'b1) begin
        tx_req_reg[i-1] <= 1'b1;
        inbuff[(i-1)*nByte*8+:nByte*8]  <= data_port[i*nByte*8+:nByte*8];
      end    
    end else if (~tx_req_port[0]&&((tx_req_reg&(~({nPort-1{1'b1}}<<(i-1))))==1'b0)) begin        //will AND with 0000, 0001, 0011, ...             
      dataout         <= inbuff[(i-1)*nByte*8+:nByte*8];
      tx_req          <= 1'b1;
      tx_req_reg[i-1] <= 1'b0;  
      end 
    end
end

  

    
endmodule
