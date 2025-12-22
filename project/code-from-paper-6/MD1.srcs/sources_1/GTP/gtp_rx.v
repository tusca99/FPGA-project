//
//use gtp0-gtp3 as 4Gb links to the nodes in the xy plane. 
//protocol: 32'hbc, data (nGTP 32bit words), sequence count (1byte), crc (3bytes), framegap (1 word)
//complementary to gtp_tx
//received data are buffered at the end of sequence and are valid until the next data are received 
//
//output:  
//data_valid      data valid
//data_recv       received data
//error           crc or sequence_cnt error
//bussy           receiving data bussy



module gtp_rx
#(
parameter nGTP=4'd7
)
(
    input                    rst,
	input                    rx_clk,
	input                    IOclk,
    input[31:0]              rx_data,
    input[3:0]               rx_kchar,
    output reg [nGTP*32-1:0] data_recv,
    output reg               data_valid,
    output                   error,
    output                   bussy
);

//(* MARK_DEBUG="true" *)

reg  [31:0]        rx_data_d0        = 1'b0;
reg  [1:0]         rx_kchar_d0       = 1'b0;
reg  [31:0]        rx_data_align     = 1'b0;
reg                rx_kchar_align    = 1'b0;
reg  [3:0]         frame_cnt         = 1'b0; 
reg  [23:0]        crc_recv          = 1'b0;
reg  [23:0]        crc_calc          = 1'b0;
wire [23:0]        crc;
reg  [7:0]         sequence_cnt_old  = 1'b0;
reg  [7:0]         sequence_cnt      = 1'b0;
//reg                sequence_err      = 1'b0;
reg                state2            = 1'b0;
reg                state2_init       = 1'b0;
reg  [nGTP*32-1:0] data_recv_d0      = 1'b0;
reg  [nGTP*32-1:0] data_recv_d1      = 1'b0;
reg  [nGTP*32-1:0] data_recv_d2      = 1'b0;
reg                sel               = 1'b0;
reg                bussy_d0          = 1'b0;
reg                data_valid_d0     = 1'b0;
wire               data_valid_d1;
reg                error_d0          = 1'b0;
reg                crc_en            = 1'b0;
reg                crc_reset         = 1'b1;

//align data stream. Does in essence the same way as gtp_ex provided by Vivado. Example of Alinx had bugs that caussed that the first read 
//might be wrong, as status of rx_data and rx_kchar can be ill-defined. Allignment shifts in steps of 2byte, not by single bytes, which is inherent 
//to the settings of the IP in gtp_exdes (i.e., internally, it works with 2byte at 250MHz)

always@(posedge rx_clk) begin
    if   ((rx_data[23:16] == 8'hbc) && rx_kchar==4'b0100) sel <= 1'b1;       //used to check only the one bit, not the full 4 bits; might be different
    else if((rx_data[7:0] == 8'hbc) && rx_kchar==4'b0001) sel <= 1'b0;       
    rx_data_d0  <= rx_data;
	rx_kchar_d0 <= {rx_kchar[2],rx_kchar[0]};                                        //other bits are not needed
	if (sel) begin
	  rx_data_align  <= {rx_data[15:0],rx_data_d0[31:16]};
      rx_kchar_align <= rx_kchar_d0[1];
 	end else begin
      rx_data_align  <= rx_data_d0;
 	  rx_kchar_align <= rx_kchar_d0[0];
    end   	
end

//recv data 
always @(posedge rx_clk) begin
  if (frame_cnt==4'd0)  begin            //Idle   
    state2_init <= 1'b0;
    bussy_d0    <= 1'b0;
    if((rx_kchar_align == 1'b1 && rx_data_align[7:0] == 8'hbc))  begin
      frame_cnt         <= 1'b1;
      crc_en            <= 1'b1;
      crc_reset         <= 1'b0;
    end    
  end else if (frame_cnt<=nGTP)  begin
    bussy_d0         <= 1'b1;
    frame_cnt        <= frame_cnt +1'b1;
    data_recv_d0     <= {data_recv_d0[nGTP*32-33:0],rx_data_align}; 
    if(frame_cnt==nGTP)  crc_en <= 1'b0;
  end else if (frame_cnt<=nGTP+4'd1)  begin
    crc_recv         <= rx_data_align[23:0];
    data_recv_d1     <= data_recv_d0;
    sequence_cnt     <= rx_data_align[31:24];
    state2_init      <= 1'b1;
    crc_reset        <= 1'b1;
    frame_cnt        <= 1'b0;               //restart for next read, which may overlap with second state machine, allows for minimal gap 1
  end
end  

ClkTransfer #(.extend (2)) ClkTransfer0  
(
    .clkIn      (IOclk),
    .clkOut     (rx_clk),
    .sigIn      (rst),
    .sigOut     (rst_d0)
); 
   
always @(posedge rx_clk) begin
  if (rst_d0) sequence_cnt_old <= 1'b0;
  else begin
    case (state2)
      0: begin
         error_d0      <= 1'b0;
         data_valid_d0 <= 1'b0;
         if (state2_init) begin 
           state2   <= 2'd1;
           crc_calc <= crc;
         end  
       end 
      1: begin      
         if(crc_calc!=crc_recv) begin 
           error_d0 <= 1'b1;
           sequence_cnt_old <= sequence_cnt_old+1'b1;    
         end else if(sequence_cnt!=(sequence_cnt_old+1'b1)) begin     //send even when there has been a sequence error since these are valid data                       
           error_d0 <= 1'b1;
           sequence_cnt_old <= sequence_cnt;
           data_valid_d0    <= 1'b1;
           data_recv_d2     <= data_recv_d1;
        end else begin   
           sequence_cnt_old <= sequence_cnt;
           data_valid_d0    <= 1'b1;
           data_recv_d2     <= data_recv_d1;
         end
         state2 <= 2'd0;                                         //done
       end  
       default: ;  
    endcase
  end    
end  

crc24 crc24 
(
.Clk      (rx_clk), 
.Reset    (crc_reset),
.d        (rx_data_align),
.Enable   (crc_en), 
.c        (crc)
);  

ClkTransfer #(.extend (2)) ClkTransfer1  //transfer data_valid between clock domains
(
    .clkIn   (rx_clk),
    .clkOut  (IOclk),
    .sigIn   (data_valid_d0),
    .sigOut  (data_valid_d1)
); 

ClkTransfer #(.extend (2)) ClkTransfer2  
(
    .clkIn      (rx_clk),
    .clkOut     (IOclk),
    .sigIn      (error_d0),
    .sigOut     (error)
); 



ClkTransferStat #(.Width (1))  ClkTransferStat  
(
    .clkIn   (rx_clk),
    .clkOut  (IOclk),
    .sigIn   (bussy_d0),
    .sigOut  (bussy_d2)
); 
assign bussy = bussy_d2;

always @(posedge IOclk) begin
  if (data_valid_d1) data_recv <= data_recv_d2;
  data_valid <= data_valid_d1;
end


endmodule