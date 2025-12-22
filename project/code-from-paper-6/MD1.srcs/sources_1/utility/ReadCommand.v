`timescale 1ns / 1ps

//interpretes incoming commands, and sends resceived parameters as well as atom data upwards. 
//
//Command structure: 
//packetNr(1Byte), command (1 Byte), arguments (can be up to 1500Bytes which is the maximum UDP allows)
//
//Commands:
//0:  Reset                         send status bytes and initate resets. bit0: ErrorReset. bit1: nAtomReset, bit2: MD reset, bit3: ReNegotiate ETH3, bit4: ReNegotiate ETH4, bit5: Renegotiate ETH1
//1:  nstep(MSB)  nstep(LSB)        initiate MD run with nstep steps
//2:  block       sel        data   write ForceLUT; is written in blocks of 128 lines (block=0...3), sel selects LUT (currently 1bit only) 
//3:  on/off      T_target   T_tau  thermostat parameter: on/off bit0: center-of-mass shift, bit1 velocity rescaling, T_target 24 bit, Tau_t 4 bit 
//4:                                reserve
//5:  nReceived   data              received nReceived atom data, each DataByteWidth long.
//8:  sel         nSend             send nSend atom data. LSB of sel selects 256 block in 512 memory, the higher 5 bits (0..26) address a box (home box as well as all neighboring boxes)
//
//... to be continued
//
//
//parameters that are produced:
//- PacketNr          subsequent number, is send back via statusline, allows to determine whether all packest have been received
//- PacketNrOld       previosly received packerNr; allows to determine whether a lost packet was lost on the sending or receiveing side
//- WriteDataAtom     atom data valid 
//- DataAtom          atom data
//- SendMacBox        selects 256 block in 512 memory, as well as box (home box and neighbring boxes) 
//- SendMem           request to send data to MAC
//- nSendMem          number of data to be sent
//- nAtomReset        reset nAtom counts
//- ErrorReset        reset error_all
//- MDReset           reset MD machine
//- ReNegotiateETH341 initiate a Reset of ETH3 or 4 to enforce re-negotiation of link
//- InitCalc          start MD machine
//- nstep             number of time steps
//- wrForceLUT        write into force LUT
//- dataForceLUT      data to be written into force LUT
//- adrForceLUT       address of data to be written into force LUT 
//- selForceLUT       select force LUT   
//- vcm_shiftOn       center-of-mass velocity shift on/off
//- T_scaleOn         velocity scaling thermostat on/off 
//- T_target          invers target temperature; e.g., T_target=24'h1948B1 is the inverse of T=24'h0a2000
//- T_scaleTau        2^n*dt determines time constant of thermostat    


module ReadCommand
#(
parameter DataByteWidth = 27,    //length of atom data line
parameter ForceLUTWidth = 9      //length of Force LUT data line
)      
(
        input                             IOclk,
        input                             ResetStart,
//in/output that remain within mac_top                  
        output  reg [10:0]                CommandCnt,
        input       [7:0]                 CommandData,
        input                             CommandValid,
//data that are sent higher up                   
        output  reg [7:0]                 PacketNr,
        output  reg [7:0]                 PacketNrOld,
//for command 0: status and reset        
        output                            nAtomReset,
        output                            ErrorReset,
        output  reg                       MDReset,
        output  reg  [2:0]                ReNegotiateETH341,
//for command 1: initiate MD        
        output  reg                       InitCalc,     
        output  reg [15:0]                nstep,    
//for command 2: write Force LUTs
        output  reg                       wrForceLUT,    
        output  reg [ForceLUTWidth*8-1:0] dataForceLUT,  
        output  reg [8:0]                 adrForceLUT,   
        output  reg                       selForceLUT,    
//for command 3: thermostat parameters etc.        
        output  reg                       vcm_shiftOn = 1'b0,    //center-of-mass velocity shift on/off
        output  reg                       T_scaleOn   = 1'b0,    //velocity scaling thermostat on/off 
        output  reg [23:0]                T_target,              //invers target temperature; e.g., T_target=24'h1948B1 is the inverse of T=24'h0a2000
        output  reg [3:0]                 T_scaleTau,            //2^n*dt determines time constant of termostat         
//for command 5:  receiving atom data       
        output  reg                       WriteDataAtom,                  
        output  reg [DataByteWidth*8-1:0] DataAtom, 
//for command 8: send atom data                 
        output  reg [5:0]                 SendMacBox,
        output  reg [7:0]                 nSend=1'b0,
        output                            SendMem                          
);

reg  [7:0]                  Command=1'b0;
reg  [7:0]                  nReceived=8'd0;  
reg  [4:0]                  cntLine=1'b0;
reg [DataByteWidth*8-9:0]   DataAtom_d0=1'b0;        //highest byte  not needed
reg [ForceLUTWidth*8-9:0]   DataForceLUT_d0=1'b0;    //highest byte  not needed
reg                         nAtomReset_d0=1'b0;
reg  [2:0]                  nAtomReset_d;
assign                      nAtomReset = nAtomReset_d[2];
reg                         ErrorReset_d0=1'b0;
reg  [3:0]                  ErrorReset_d;
assign                      ErrorReset = ErrorReset_d[3];
reg                         SendMem_d0=1'b0;
reg  [4:0]                  SendMem_d;
assign                      SendMem = SendMem_d[4];
reg                         wrForceLUT_d1;    
reg [ForceLUTWidth*8-1:0]   dataForceLUT_d1;  
reg [8:0]                   adrForceLUT_d1;   
reg                         selForceLUT_d1;    

always @(posedge IOclk) begin 
 nAtomReset_d <= {nAtomReset_d[1:0],nAtomReset_d0}; //needs to be delayed with respect to MDReset
 ErrorReset_d <= {ErrorReset_d[2:0],ErrorReset_d0}; //needs to be delayed even more
 SendMem_d    <=    {SendMem_d[3:0],SendMem_d0};    //needs to be delayed even more
 wrForceLUT   <= wrForceLUT_d1;                     //add one FIFO stage for better routing   
 dataForceLUT <= dataForceLUT_d1;
 adrForceLUT  <= adrForceLUT_d1;
 selForceLUT   <=selForceLUT_d1;

//reset signals 
 if(SendMem_d0==1'b1)       SendMem_d0       <= 1'b0;
 if(WriteDataAtom==1'b1)    WriteDataAtom    <= 1'b0;
 if(wrForceLUT_d1==1'b1) begin
    wrForceLUT_d1   <= 1'b0;
    adrForceLUT_d1  <= adrForceLUT_d1 +1'b1;
 end   
 if(InitCalc==1'b1)         InitCalc           <= 1'b0;
 if(nAtomReset_d0==1'b1)    nAtomReset_d0      <= 1'b0;
 if(ErrorReset_d0==1'b1)    ErrorReset_d0      <= 1'b0;
 if(MDReset==1'b1)          MDReset            <= 1'b0;
 if(ReNegotiateETH341!=3'b0) ReNegotiateETH341 <= 3'b0;
 
//major state machine 
 if(ResetStart)          CommandCnt<=11'h7ff;  
 else begin
   if(CommandValid==1'b1) begin
     CommandCnt<=1'b0;
   end else begin
     if(CommandCnt<11'h7ff) begin
       if(CommandCnt==11'd0) CommandCnt<=CommandCnt+1'b1; //wait for memory latancy 2
       if(CommandCnt==11'd1) CommandCnt<=CommandCnt+1'b1; //wait for memory latancy 2
       if(CommandCnt==11'd2) begin
         PacketNr    <= CommandData;
         PacketNrOld <= PacketNr;
         CommandCnt  <= CommandCnt+1'b1;   
       end  
       if(CommandCnt==11'd3) begin 
         Command <=CommandData;
         CommandCnt  <= CommandCnt+1'b1;
       end  
       if(CommandCnt>11'd3) begin
         case (Command)
           0: begin                                //read status  and send reset signals          
                CommandCnt<=11'h7ff; 
                ErrorReset_d0    <= CommandData[0];
                nAtomReset_d0    <= CommandData[1];
                MDReset          <= CommandData[2];
                ReNegotiateETH341<= {CommandData[5],CommandData[4],CommandData[3]};
                if(CommandData[0]) PacketNrOld <= 1'b0;   //upon ErrorReset
                nSend      <=1'b0;       
                SendMem_d0 <=1'b1;
              end            
           1: begin                                //initiate calculation;           
                if(CommandCnt==11'd4) begin                                                    
                  CommandCnt  <= CommandCnt+1'b1;
                  nstep<={nstep[7:0],CommandData};  
                end 
                if(CommandCnt==11'd5) begin
                  CommandCnt<=11'h7ff;  
                  nstep      <= {nstep[7:0],CommandData};                    
                  InitCalc   <= 1'b1;
                  nSend      <= 1'b0;                 //return status line for handshake
                  SendMem_d0 <= 1'b1;
                end  
              end 
          2: begin                                      //write Force LUTs
                if(CommandCnt==11'd4) begin             //sent in 128line blocks; number of block
                  CommandCnt     <= CommandCnt+1'b1; 
                  adrForceLUT_d1 <= {1'b0,CommandData}<<7;
                end                    
                if(CommandCnt==11'd5) begin             
                  CommandCnt     <= CommandCnt+1'b1; 
                  selForceLUT_d1 <= CommandData[0];
                  cntLine        <= 1'b0;
                end   
                if((CommandCnt>11'd5)&&(CommandCnt<128*ForceLUTWidth+11'd6)) begin 
                  CommandCnt      <= CommandCnt + 1'b1;
                  DataForceLUT_d0<={DataForceLUT_d0[ForceLUTWidth*8-9:0],CommandData};         
                  if(cntLine<ForceLUTWidth-1) begin
                    cntLine       <= cntLine + 1'b1;
                  end else begin  
                    cntLine         <= 1'b0;
                    wrForceLUT_d1   <= 1'b1;
                    dataForceLUT_d1 <= {DataForceLUT_d0[ForceLUTWidth*8-9:0],CommandData};
                  end   
                end 
                if(CommandCnt==128*ForceLUTWidth+11'd6) begin          
                  CommandCnt    <= 11'h7ff;  
                  nSend         <= 1'b0;   //return status line for handshake;    
                  SendMem_d0    <= 1'b1;    
                end 
              end
           3: begin                                //initiate calculation;           
                if(CommandCnt==11'd4) begin                                                    
                  vcm_shiftOn <= CommandData[0];
                  T_scaleOn   <= CommandData[1];
                  CommandCnt  <= CommandCnt+1'b1;
                end 
                if(CommandCnt==11'd5) begin
                  T_target    <= {T_target[15:0],CommandData};
                  CommandCnt  <= CommandCnt+1'b1;
                end  
                if(CommandCnt==11'd6) begin
                  T_target    <= {T_target[15:0],CommandData};
                  CommandCnt  <= CommandCnt+1'b1;
                end  
                if(CommandCnt==11'd7) begin
                  T_target    <= {T_target[15:0],CommandData};
                  CommandCnt  <= CommandCnt+1'b1;
                end  
                if(CommandCnt==11'd8) begin
                  CommandCnt  <= 11'h7ff;  
                  T_scaleTau  <= CommandData[3:0];
                  nSend      <= 1'b0;                 //return status line for handshake
                  SendMem_d0 <= 1'b1;
                end  
              end                             
//4 reserve                           
           5: begin                                //write atom data (velocities, coordinates, metadata) into BRAM
                if(CommandCnt==11'd4) begin             //number of data received in that block
                  CommandCnt  <= CommandCnt+1'b1; 
                  nReceived   <= CommandData;
                  cntLine     <= 1'b0;
                end                    
                if((CommandCnt>11'd4)&&(CommandCnt<nReceived*DataByteWidth+11'd5)) begin 
                  CommandCnt  <= CommandCnt + 1'b1;
                  DataAtom_d0<={DataAtom_d0[DataByteWidth*8-9:0],CommandData};         
                  if(cntLine<DataByteWidth-1) begin
                    cntLine       <= cntLine + 1'b1; 
                  end else begin  
                    cntLine       <= 1'b0; 
                    WriteDataAtom <= 1'b1;
                    DataAtom      <= {DataAtom_d0[DataByteWidth*8-9:0],CommandData};
                  end   
                end 
                if(CommandCnt==nReceived*DataByteWidth+11'd5) begin          
                  CommandCnt    <= 11'h7ff;  
                  nSend         <= 1'b0;   //return status line for handshake;    
                  SendMem_d0    <= 1'b1;  
                end 
              end
           8: begin
                if(CommandCnt==11'd4) begin                           //read Memories                          
                  CommandCnt  <= CommandCnt+1'b1; 
                  SendMacBox  <= CommandData[5:0]; 
                end 
                if(CommandCnt==11'd5) begin 
                  CommandCnt <= 11'h7ff; 
                  nSend      <= CommandData;       
                  SendMem_d0 <= 1'b1;
                end                   
              end              
           default: CommandCnt<=11'h7ff;  
         endcase   
         end
       end   
     end
   end  
 end

endmodule
