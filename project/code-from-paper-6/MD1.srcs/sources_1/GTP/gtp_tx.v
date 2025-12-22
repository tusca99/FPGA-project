//
//use gtp0-gtp3 as 4Gb links to the nodes in the xy plane. 
//protocol: 32'hbc, data (nGTP 32bit words), sequence count (1byte), crc (3byte), framegap (1 word)
//complementary to gtp_rx
//has 4 ports at the input that are all buffered and worked off according to a priority list
//subsequently has FIFO at the input sufficient for 128 lines (same as ETH_tx). 64 would be better in terms of LUT-Ram
//usage, but had overflows at some point (might have changed due to slower calculation in MDmachine)
//
//input:  
//tx_req_port*   request to send data on port*
//data_port      data to be sent on port
//
//output:
//tx_error     error upon FIFO overflow
//mux_error    error when input multiplexer overflows
//bussy        transmission bussy


module gtp_tx
#(
parameter nGTP=4'd7
)
(
	input rst,
	input tx_clk,
	input IOclk,
    output reg [31:0]          tx_data,
    output reg [3:0]           tx_kchar,
    input      [nGTP*32-1:0]   data_port0,
    input                      tx_req_port0,  
    input      [nGTP*32-1:0]   data_port1,
    input                      tx_req_port1,  
    input      [nGTP*32-1:0]   data_port2,
    input                      tx_req_port2,  
	input      [nGTP*32-1:0]   data_port3,
    input                      tx_req_port3,   
    output 	                   tx_error,       //error if input buffer full
    output                     mux_error,      //error if gated multiplexer overflows
    output                     bussy
);

//(* MARK_DEBUG="true" *)

 reg  [7:0]         data_cnt        = 1'b0;  
 reg  [nGTP*32-1:0] outbuff         = 1'b0;
 wire [nGTP*32-1:0] data_send2;
 reg  [7:0]         sequence_cnt    = 1'b1;  
 reg  [3:0]         state           = 1'b0;
 reg                FIFO_rd         = 1'b0;
 wire [nGTP*32-1:0] data;
 wire               tx_req;
 reg                bussy_d0        = 1'b0;
 reg  [10:0]        clock_corr_cnt  = 1'b0; 
 reg                crc_en          = 1'b0;
 wire  [23:0]       crc;
 reg [31:0]         tx_data_d0;
 reg [3:0]          tx_kchar_d0;
 reg                send_crc=1'b0;
 
//**************************************funnel 4 input ports into FIFO************************
GatedMultplx
#(
.nPort   (4),
.nByte   (nGTP*4)                 
) GatedMultplx1
(
 .IOclk             (IOclk),
 .data_port         ({data_port3,data_port2,data_port1,data_port0}),
 .tx_req_port       ({tx_req_port3,tx_req_port2,tx_req_port1,tx_req_port0}),
 .tx_req            (tx_req),
 .dataout           (data),
 .error             (mux_error)
);

  
//*******************************input FIF0********************************************  
FIFO_224x128 FIFO_gtp_tx (         //input FIFO, latency 1 
  .wr_clk(IOclk),             
  .rd_clk(tx_clk),  
  .din(data),        
  .wr_en(tx_req),    
  .rd_en(FIFO_rd),    
  .dout(data_send2),      
  .full(tx_error),  
  .empty(FIFO_empty)    
); 


//******************************************send*********************************
always @(posedge tx_clk) begin
  if (rst) begin
    tx_data        <= 1'b0;
    tx_kchar       <= 1'b0;
    tx_data_d0     <= 1'b0;
    tx_kchar_d0    <= 1'b0;
    data_cnt       <= 4'd0;
    state          <= 1'b0;
    FIFO_rd        <= 1'b0;
    sequence_cnt   <= 1'b1;
    bussy_d0       <= 1'b0;
    clock_corr_cnt <= 1'b0;
  end else begin       
      case (state)
        0: begin                         //Idle  
           tx_data_d0     <= 1'b0;
           tx_kchar_d0    <= 1'b0; 
           send_crc       <= 1'b0;
           bussy_d0       <= 1'b0;
           clock_corr_cnt <= clock_corr_cnt +1'b1;
           if(clock_corr_cnt>11'd1245) state <= 1; 
           else if(~FIFO_empty)  begin   
             FIFO_rd      <= 1'b1;         
             state        <= 2;
           end   
        end   
        1: begin
           send_crc       <= 1'b0;
           tx_data_d0     <= 32'hf7_f7_f7_f7;     //sequence for clock correction, needs to be scattered in once in a while to correct for slightly different 
		   tx_kchar_d0    <= 4'b1111;  
		   clock_corr_cnt <= 1'b0;               
           state          <= 0;
        end 
        2: begin                 //wait; latency 1 for FIFO
           clock_corr_cnt <= clock_corr_cnt +1'b1;
           bussy_d0       <= 1'b1;
           data_cnt       <= 1'b0; 
           FIFO_rd        <= 1'b0;
           tx_data_d0     <= 1'b0;
		   tx_kchar_d0    <= 1'b0;
		   send_crc       <= 1'b0;
           state          <= 3;
        end
        3: begin                     //Header
           clock_corr_cnt<= clock_corr_cnt +1'b1;
           tx_data_d0     <= 32'h00_00_00_bc;
		   tx_kchar_d0    <= 4'b0001;
		   outbuff        <= data_send2;
		   crc_en         <= 1'b1;
//		   check_sum     <= sequence_cnt + data_send2[nGTP*32-1:nGTP*32-16] + data_send2[nGTP*32-17:nGTP*32-32]; //start calculation already now
           state          <= 4;
        end
        4: begin                     //data
           clock_corr_cnt <= clock_corr_cnt +1'b1;
           tx_kchar_d0    <= 4'b0000;
           tx_data_d0     <= outbuff[nGTP*32-1:nGTP*32-32];
           outbuff        <= {outbuff[nGTP*32-33:0],32'b0}; 
		   data_cnt       <= data_cnt + 1'b1;
		   if(data_cnt==nGTP-1)  begin
		     crc_en   <= 1'b0;  
		     state    <= 5;
		   end  
        end 
        5: begin                              
           clock_corr_cnt <= clock_corr_cnt +1'b1;
           send_crc       <= 1'b1;           //send crc one cycle delayed
           if(~FIFO_empty)  begin 
             if(clock_corr_cnt>11'd1245) state <= 1; 
             else begin
               FIFO_rd      <= 1'b1;            //restart right away
               state        <= 2;
             end  
           end else state <= 0;               //idle                  
        end                     
      endcase
      if(send_crc) begin
        tx_kchar       <= 4'b0000;
        tx_data        <= {sequence_cnt,crc};
        sequence_cnt   <= sequence_cnt +1'b1;
      end else begin
        tx_data        <= tx_data_d0;
        tx_kchar       <= tx_kchar_d0; 
      end
    end
  end  
  
crc24 crc24 
(
.Clk      (tx_clk), 
.Reset    (FIFO_rd),
.d        (outbuff[nGTP*32-1:nGTP*32-32]),
.Enable   (crc_en), 
.c        (crc)
);   



ClkTransferStat #(.Width (1))  ClkTransferStat  
(
    .clkIn   (tx_clk),
    .clkOut  (IOclk),
    .sigIn   (bussy_d0),
    .sigOut  (bussy_d2)
); 
assign bussy = bussy_d2;

endmodule 
