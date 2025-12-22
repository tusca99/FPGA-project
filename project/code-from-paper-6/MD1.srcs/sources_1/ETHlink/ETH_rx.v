`timescale 1ns / 1ps

//- use ETH3 and ETH4 as 1Gb link to the nodes up and down. 
//- protocol: 7*8'h55, 8'hd5, data (nETH Byte), sequence_cnt (1byte), crc (3 byte),frame gap (min 1byte, but 12byte on the sending side)
//  data_sequence_cnt and crc are treated with an ECC, that corrects 1bit errors for every 4 bytes
//- complementary to ETH_tx
//- condition to start read sequence: proeprly delayed rising slope of e_rx_dv (with e_rx_dv still on to supress single spikes), or 8'hd5 
//  after rising slope of e_rx_dv (with e_rx_dv still on). This accounts for bit errors in 8'hd5 or when number of preamble<7 in case of clock synchronisation   
//- received data are buffered at the end of sequence and are valid for at least another sequence 
//
//output:  
//data_valid      data valid
//data_recv       received data
//error           ecc, crc or sequence_cnt error
//ecc_corr        indicate that single-bit correction has been perforemd (but no error)
//bussy           bussy signal

module ETH_rx
#(
parameter nETH  =  5'd28    //length of a data line
)
(
  input                   ErrorReset,
  input                   e_clk  ,   
  input                   IOclk,
  input                   e_rx_dv,
  input  [7:0]            e_rxd, 
  output reg [nETH*8-1:0] data_recv,
  output reg              data_valid,
  output [2:0]            error,
  output                  bussy
);
        
// (* MARK_DEBUG="true" *)
    
reg               e_rx_dv_d0       = 1'b0;
reg               e_rx_dv_d1       = 1'b0;
reg               e_rx_dv_d2       = 1'b0;
reg  [1:0]        e_rx_dv_slope    = 1'b0;
reg  [7:0]        e_rxd_d0         = 1'b0;  
reg  [7:0]        e_rxd_d1         = 1'b0;  
reg  [7:0]        e_rxd_d2         = 1'b0;  
//reg  [5:0]        frame_cnt        = 1'b0;   
reg               crc_reset        = 1'b0;
reg               crc_en_d0        = 1'b0;
reg               crc_en_d1        = 1'b0;
wire [23:0]       crc;
reg  [23:0]       crc_recv         = 1'b0;
reg  [2:0]        wait_cnt         = 1'b0;
reg  [nETH*8-1:0] data_recv_d0     = 1'b0;
reg  [7:0]        sequence_cnt_old = 1'b0;
reg  [7:0]        sequence_cnt     = 1'b0;
reg               bussy_d0         = 1'b0;
reg               bussy_d1         = 1'b0;
reg               data_valid_d0    = 1'b0;
wire              data_valid_d1;
reg               crc_error_d0     = 1'b0;
reg  [2:0]        state1           = 1'b0;  
reg  [2:0]        cnt1             = 1'b0;
reg  [3:0]        cnt2             = 1'b0;
reg  [31:0]       inbuff1          = 1'b0;
reg  [39:0]       inbuff2          = 1'b0;
reg  [31:0]       inbuff3          = 1'b0;
wire              ecc_sbit_err;
wire              ecc_dbit_err;
wire [31:0]       ecc_data_out;
reg               ecc_error_d0     =1'b0;
reg               ecc_corr_d0      =1'b0;
reg               seq_error_d0     =1'b0;


always @(posedge e_clk) begin
//input signals through a few FFs for better routing 
  e_rxd_d0    <= e_rxd;
  e_rx_dv_d0  <= e_rx_dv;
  e_rxd_d1    <= e_rxd_d0;        
  e_rx_dv_d1  <= e_rx_dv_d0;      
  e_rxd_d2    <= e_rxd_d1;        
  e_rx_dv_d2  <= e_rx_dv_d1;
//process some of the data depending on state machine        
  crc_en_d1   <= crc_en_d0;
  if(crc_en_d0) inbuff3 <= ecc_data_out;
  if(crc_en_d1) data_recv_d0 <= {data_recv_d0[nETH*8-33:0],inbuff3};
  if(state1==1'b0) begin
    ecc_error_d0 <= 1'b0;
    ecc_corr_d0  <= 1'b0;
  end else begin
    if(ecc_dbit_err) ecc_error_d0 <= 1'b1;
    if(ecc_sbit_err) ecc_corr_d0 <= 1'b1;
  end       
//main state machine 
  e_rx_dv_slope <= {e_rx_dv_slope[0],e_rx_dv_d2};
  if (ErrorReset) sequence_cnt_old <= 1'b0;
  else begin
    case (state1)
       0: begin
         bussy_d0        <= 1'b0;
         crc_error_d0    <= 1'b0;
         seq_error_d0    <= 1'b0;
         crc_en_d0       <= 1'b0;
         crc_reset       <= 1'b1;
         data_valid_d0   <= 1'b0;
         wait_cnt        <= 1'b0;
         inbuff2         <= 1'b0;
         if((e_rx_dv_slope==2'b01)&&e_rx_dv_d2&& (e_rxd_d2==8'h55))  state1 <= 3'd1;   
       end
       1: begin
          bussy_d0  <= 1'b1;
          crc_reset <= 1'b0;   
          wait_cnt  <= wait_cnt+1'b1;
          cnt1      <= 1'b0;
          cnt2      <= 1'b0;
          if(((e_rxd_d2==8'hd5)&&e_rx_dv_d2)||wait_cnt==3'd5) begin
            state1 <= 3'd2;
          end
       end
       2: begin
         if(cnt1==3'd4) begin
           inbuff2 <= {inbuff1,e_rxd_d2};
           if(cnt2==nETH/4) begin
             state1    <= 3'd3;
           end else begin
             cnt1      <= 1'b0;
             cnt2      <= cnt2 +1'b1;
             crc_en_d0 <= 1'b1;
           end
         end else begin
           inbuff1     <= {inbuff1[23:0],e_rxd_d2}; 
           cnt1        <= cnt1+1'b1;
           crc_en_d0   <= 1'b0;
         end  
       end
       3: begin
         sequence_cnt  <= ecc_data_out[31:24];
         crc_recv      <= ecc_data_out[23:0];
         state1        <= 3'd4;
       end
       4: begin 
          if((crc_recv!=crc)||ecc_error_d0) begin
            crc_error_d0 <= 1'b1;                              
            sequence_cnt_old <= sequence_cnt_old + 1'b1;   //received data, but they are  wrong; avoid that next error is a sequence error
          end else begin
            if(sequence_cnt != sequence_cnt_old + 1'b1) seq_error_d0 <= 1'b1;
            sequence_cnt_old <= sequence_cnt;
            data_valid_d0 <= 1'b1;
         end  
         state1 <= 3'd0;
       end
    endcase
  end     
end  
  

ECCDecode your_instance_name (
  .ecc_correct_n(1'b0),    // input wire ecc_correct_n
  .ecc_data_in(inbuff2[39:8]),        // input wire [31 : 0] ecc_data_in
  .ecc_data_out(ecc_data_out),      // output wire [31 : 0] ecc_data_out
  .ecc_chkbits_in(inbuff2[6:0]),  // input wire [6 : 0] ecc_chkbits_in
  .ecc_sbit_err(ecc_sbit_err),      // output wire ecc_sbit_err
  .ecc_dbit_err(ecc_dbit_err)      // output wire ecc_dbit_err
);


crc24 crc24 
(
.Clk      (e_clk), 
.Reset    (crc_reset),
.d        (inbuff3),
.Enable   (crc_en_d1), 
.c        (crc)
); 



ClkTransfer #(.extend (2)) ClkTransfer1  //transfer data_valid between clock domains
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (data_valid_d0),
    .sigOut  (data_valid_d1)
); 

ClkTransfer #(.extend (2)) ClkTransfer2  //transfer data_valid between clock domains
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (crc_error_d0),
    .sigOut  (crc_error_d1)
); 

ClkTransfer #(.extend (2)) ClkTransfer3  //transfer data_valid between clock domains
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (seq_error_d0),
    .sigOut  (seq_error_d1)
); 

ClkTransfer #(.extend (2)) ClkTransfer4  //transfer data_valid between clock domains
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (ecc_corr_d0),
    .sigOut  (ecc_corr)
); 

assign error={ecc_corr,seq_error_d1,crc_error_d1};
    
ClkTransferStat  #(.Width (1)) ClkTransferStat  
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (bussy_d0),
    .sigOut  (bussy_d2)
); 
assign bussy = bussy_d2;

    
always @(posedge IOclk) begin 
  if (data_valid_d1) data_recv <= data_recv_d0;
  data_valid    <= data_valid_d1;
end
    
    
endmodule
