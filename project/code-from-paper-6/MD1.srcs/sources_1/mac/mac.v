`timescale 1ns / 1ps

//controls ETH1 for communication with host PC. Includes sending part (mac_tx), receiving part (mac_rx), as well 
//as hardware control (smi_config). mac_tx and mac_rx do UDP protocol and ARP protocol. An ARP request from the 
//host PC is answered directly; this is not seen above mac_top. 
//UDP has a FIFO for sending (216*512 bits) and an receiving memory (8*2048 bit). One 
//can write into sending FIFO one line/clock-cycle up to 512 lines. Its output is choped so that maximal nBlock lines 
//are witten per UDP packet (which has to be smaller than ca. 1.5 kB);  state machines before and after the 
//FIFO control all that. Each set of data, which can be more than nBlock, starts with two lines, status line and nAtom.
//The receiving memeory is large enough for one such block; it needs to be choped by the host-PC.
//
//UDP sending:
//- statusline     statusline
//- nAtom          27 bytes, number of atoms in home box and 26 neigboring boxes
//- StartMac       request to send data, comes from ReadCommand
//- SendMac        sending mac data active (used for adress mux when reading box BRAMs) 
//- nSend          number of data to be sent, not including statusline and nAtom, comes from ReadCommand
//- DataSendMac    atom data
//- SendMacAdr     output, address that reads memory containing atom data.
//

 
module mac_top
#(
parameter DataByteWidth = 27,    //length of a atom data line
parameter nBlock        = 50     //length of a block to be sent at once
)
       (
                   input                       e_clk,
                   input                       IOclk,
                   input                       CalcClk,
                   output                      e_reset,
                   input                       ResetStart,
//IP-stuff         
                   input  [47:0]               local_mac_addr ,       
                   input  [31:0]               local_ip_addr,
                   input  [15:0]               local_udp_port,        
//ETH in/output   
                   output                      e_tx_en,
                   output [7:0]                e_txd, 
                   input                       e_rx_dv,
                   input  [7:0]                e_rxd,
                   output                      e_mdc,            //mdc interface
                   inout                       e_mdio,           //mdio interface
                   output  reg [1:0]           speedCombined,    //ethernet speed 00: no link, 01: 10M 02:100M 11:1000M                 
//UDP sending data                  
                   input  [DataByteWidth*8-1:0]      statusLine,
                   input  [DataByteWidth*8-1:0]      nAtom,  
                   input                             StartMac,
                   input  [7:0]                      nSend, 
                   input  [DataByteWidth*8-1:0]      DataSendMac,
                   output  reg [7:0]                 SendMacAdr,
//UDP receiving data
                   input                             ReNegotiateETH1,    //that is new
                   input       [10:0]                CommandCnt,                  
                   output      [7:0]                 CommandData,                
                   output                            CommandValid                          
);
 
 
//*******************************************FIFO for sending data************** 
reg                        sendFIFOReadEn=1'b0;
wire [DataByteWidth*8-1:0] DataOut2; 
wire                       ReqSendData2;
wire                       sendFIFOempty;
reg  [2:0]                 ReadMemStat= 1'b0;
reg                        DataOut_en = 1'b0;
reg  [DataByteWidth*8-1:0] FIFOin     = 1'b0;
wire                       StartMac2;
reg                        StartMac3;
reg                        sentAll;

                 
ClkTransfer #(.extend (2)) ClkTransfer1
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (StartMac),
    .sigOut  (StartMac2)
);      

ClkTransfer #(.extend (2)) ClkTransfer2
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (ResetStart),
    .sigOut  (ResetStart_CalcClk)
);   
                 
                   
wire [7:0] nSend_CalcClk;
ClkTransferStat #(.Width (8)) ClkTransferStat1
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (nSend),
    .sigOut  (nSend_CalcClk)
); 

//reg [DataByteWidth*8-1:0]  statusLine_d0 = 1'b0;                 
//always @(posedge IOclk) begin    //for routing, and some of the signals are result of combinatorial logic, which cuases timing warning
//  statusLine_d0 <= statusLine;
//end      
wire [DataByteWidth*8-1:0]  statusLine_CalcClk;
ClkTransferStat #(.Width (DataByteWidth*8)) ClkTransferStat2
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (statusLine),
    .sigOut  (statusLine_CalcClk)
); 

wire [DataByteWidth*8-1:0]  nAtom_CalcClk;
ClkTransferStat #(.Width (DataByteWidth*8)) ClkTransferStat3
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (nAtom),
    .sigOut  (nAtom_CalcClk)
); 



//state machine that writes into FIF0
always @(posedge CalcClk) begin
  StartMac3 <= StartMac2;          //for better routing
  if(ResetStart_CalcClk) ReadMemStat <= 3'd0;
  else begin
    case (ReadMemStat)
    0: begin
       SendMacAdr  <=1'b0;
       DataOut_en  <=1'b0;
       if(StartMac3) begin
         ReadMemStat <= 3'd1; 
       end  
    end
    1: begin
       SendMacAdr  <= SendMacAdr+1'b1;  //latency of Bram+Multiplexer is 6
       ReadMemStat <= 3'd2; 
    end
    2: begin
       SendMacAdr  <= SendMacAdr+1'b1;
       ReadMemStat <= 3'd3; 
    end
    3: begin
       SendMacAdr  <= SendMacAdr+1'b1;
       ReadMemStat <= 3'd4; 
    end
    4: begin
       SendMacAdr  <= SendMacAdr+1'b1;
       ReadMemStat <= 3'd5; 
    end
    5: begin
       DataOut_en  <= 1'b1;   //send statusBlock and nAtom line first, and then box data
       FIFOin      <= statusLine_CalcClk;
       SendMacAdr  <= SendMacAdr+1'b1; 
       ReadMemStat <= 3'd6;
    end 
    6: begin
       SendMacAdr  <= SendMacAdr+1'b1;
       FIFOin      <= nAtom_CalcClk;
       ReadMemStat <= 3'd7;
       sentAll     <= (nSend_CalcClk==0);             //precalculate
    end
    7: begin
       SendMacAdr  <= SendMacAdr+1'b1;
       FIFOin      <= DataSendMac;
       sentAll     <= (SendMacAdr==nSend_CalcClk+8'd5);   //precalculate
       if (sentAll) begin
         DataOut_en  <= 1'b0;
         ReadMemStat <= 3'd0; 
       end
    end    
    default: ReadMemStat <= 3'd0; 
    endcase  
  end  
end


FIFO_216x512 sendFIFO (
  .wr_clk(CalcClk),       // input wire wr_clk
  .rd_clk(e_clk),         // input wire rd_clk
  .din(FIFOin),           // input wire [215 : 0] din
  .wr_en(DataOut_en),     // input wire wr_en
  .rd_en(sendFIFOReadEn), // input wire rd_en; 
  .dout(DataOut2),        // output wire [215 : 0] dout
  .full(),                // output wire full
  .empty(sendFIFOempty)   // output wire empty
);
 
//********************************transfer signal to ETH clk**************************************
ClkTransfer #(.extend (2)) ClkTransfer3
(
    .clkIn   (CalcClk),
    .clkOut  (e_clk),
    .sigIn   (StartMac2),
    .sigOut  (ReqSendData2)
); 

wire [7:0] nSend_eclk;
 ClkTransferStat #(.Width (8)) ClkTransferStat4
(
    .clkIn   (IOclk),
    .clkOut  (e_clk),
    .sigIn   (nSend),
    .sigOut  (nSend_eclk)
); 
 
//**************************state machine that reads FIF0 and sends data to ETH**************************
reg [3:0]                  SendStat=4'd0;
reg                        udp_tx_req=1'b0;
wire                       udp_ram_data_req,udp_tx_end;
reg [DataByteWidth*8-1:0]  SendBuff;
reg [15:0]                 udp_send_data_length=1'b0;
reg [4:0]                  SendCnt1=1'b0;
reg [7:0]                  SendCnt2=1'b0;
reg [7:0]                  StartLine=1'b0;
reg [7:0]                  nSend_p2;



always @(posedge e_clk) begin
    case (SendStat)
    0: begin
       if(ReqSendData2)  begin
         SendStat<=4'd1;
         StartLine<=1'b0;
         if(nBlock<nSend_eclk+8'd2) begin
           nSend_p2<=nBlock;
           udp_send_data_length <= nBlock*DataByteWidth;  
         end else begin
           nSend_p2<=nSend_eclk+8'd2;
           udp_send_data_length <= (nSend_eclk+8'd2)*DataByteWidth;
         end  
       end   
    end
    1: begin
       if(~sendFIFOempty) begin 
          SendStat<=4'd2;
          udp_tx_req<=1'b1;
          sendFIFOReadEn<=1'b1;
       end   
    end
    2: begin
        udp_tx_req<=1'b0;
        sendFIFOReadEn<=1'b0;
        if(udp_ram_data_req) begin
          SendStat<=4'd3;         
        end  
    end   
    3: begin
       SendStat<=4'd4;
       SendCnt1<=1'b0;
       SendCnt2<=1'b0; 
       SendBuff<=DataOut2;
    end   
    4: begin
       if(SendCnt1<DataByteWidth-1) begin
         if(SendCnt1==DataByteWidth-3) sendFIFOReadEn<=1'b1;   //this last read is one two much, but helps to empty FIFO
         if(SendCnt1==DataByteWidth-2) sendFIFOReadEn<=1'b0;
         SendCnt1<=SendCnt1+1'b1;
         SendBuff<={SendBuff[DataByteWidth*8-9:0],8'b0};
       end else begin
         SendCnt1<=1'b0;
         SendCnt2<=SendCnt2+1'b1;       
         sendFIFOReadEn<=1'b0;
         SendBuff<=DataOut2;
         if(SendCnt2==nSend_p2-1'b1) begin   
           SendStat<=4'd5;           
         end  
       end
    end   
    5: begin
      if(nSend_p2==(nSend_eclk+8'd2-StartLine)) SendStat<=4'd0;   //sent all data
      else if (udp_send_end) begin                         //wait until transmission is done and restart for next block                             
         SendStat<=4'd6; 
         StartLine<=StartLine+nSend_p2;  
       end  
    end
    6: begin   
       if(nBlock<(nSend_eclk+8'd2-StartLine)) begin
          nSend_p2<=nBlock;
          udp_send_data_length <= nBlock*DataByteWidth;  
        end else begin
          nSend_p2<=nSend_eclk+8'd2-StartLine;
          udp_send_data_length <= (nSend_eclk+8'd2-StartLine)*DataByteWidth;
        end 
        udp_tx_req<=1'b1;
        SendStat<=4'd2;
    end
    default: SendStat<=1'b0; 
    endcase  
end


//*************************************************UDP and ARP transmit***********************************     
wire [47:0]  remote_mac_addr;
wire [31:0]  remote_ip_addr;  
wire [15:0]  remote_udp_port;    

wire [47:0]  arp_remote_mac_addr;
wire [31:0]  arp_remote_ip_addr; 
wire         arp_req;

mac_tx mac_tx
(
 .e_clk                       (e_clk),     //input
//ETH input/output 
 .e_tx_en                     (e_tx_en),            //output           transmit enable        
 .e_txd                       (e_txd),              //output [7:0]     transmit data
//IP-stuff 
 .local_mac_addr              (local_mac_addr),      
 .local_ip_addr               (local_ip_addr),       
 .local_udp_port              (local_udp_port),   
 .remote_mac_addr             (remote_mac_addr),      
 .remote_ip_addr              (remote_ip_addr),      
 .remote_udp_port             (remote_udp_port),     
//ARP stuff 
 .arp_req                     (arp_req),
 .arp_remote_mac_addr         (arp_remote_mac_addr),   
 .arp_remote_ip_addr          (arp_remote_ip_addr), 
//UDP stuff     
 .udp_tx_req                  (udp_tx_req),
 .udp_send_end                (udp_send_end),  
 .udp_send_data               (SendBuff[DataByteWidth*8-1:DataByteWidth*8-8]),
 .udp_send_data_length        (udp_send_data_length),
 .udp_ram_data_req            (udp_ram_data_req)
);        

//************************************UDP and ARP receive**************************    
mac_rx mac_rx
(
 .e_clk                       (e_clk),     //input
 .IOclk                       (IOclk),
//ETH input/output 
 .e_rx_dv                     (e_rx_dv),                   
 .e_rxd                       (e_rxd),              
//IP-stuff      
 .local_ip_addr               (local_ip_addr),       
 .local_udp_port              (local_udp_port),   
 .remote_mac_addr             (remote_mac_addr),      
 .remote_ip_addr              (remote_ip_addr),      
 .remote_udp_port             (remote_udp_port),   
//ARP stuff   
 .arp_req                     (arp_req),
 .arp_remote_mac_addr         (arp_remote_mac_addr),   
 .arp_remote_ip_addr          (arp_remote_ip_addr),   
//UDP stuff 
 .udp_rec_ram_rdata           (CommandData),             //output [7:0]        received data
 .udp_rec_ram_read_addr       (CommandCnt),              //input  [10:0]       address of received data
 .udp_rec_data_valid          (CommandValid)             //output              received data valid 
);       

//*********************************************MDIO register configuration**************************************
wire [1:0] speed;
smi_config 
 #(
.REF_CLK                 (100                   ),        
.MDC_CLK                 (500                   )
)
smi_config_inst      
(
.clk                    (IOclk                ),
.e_reset                (e_reset              ),        
.mdc                    (e_mdc                ),
.mdio                   (e_mdio               ),
.speed                  (speed                ),
.link                   (link                 ),
.ReNegotiate            (ReNegotiateETH1),
.mode                   (1'b0)    //keep EEE-mode
); 

always @(posedge IOclk) begin 
  speedCombined <= link ? (speed+2'b01): 2'b00;        
end
       
endmodule         