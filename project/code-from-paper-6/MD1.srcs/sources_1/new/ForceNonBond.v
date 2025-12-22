`timescale 1ns / 1ps
//Force calculation; starts from (dx,dy,dy) and accumulates (Fx_tot,Fy_tot_Fz_tot). 
//ResetFtot sets (Fx_tot,Fy_tot_Fz_tot)=0, and pipe is a signal that says that data are valid.
//wrForceLUT, etc. write the force LUT.
//
//Latency currently is 19, and is defined as parameter nPipeForce in MDmachine. Latency is the 
//number of clock cycles from (dx,dy,dy) until (Fx_tot,Fy_tot,Fz_tot) are valid
//
//Equivalent C-code is:
//
// r2      = dx * dx + dy * dy + dz * dz;
// r2_high = (int)(r2 * 512);
// r2_low  = (r2 * 512)%1;
// r4      = r2_low * r2_low;
// ForceLJ = ForceLUT[r2_high] + r2_low * dForceLUT[r2_high] + r4 * ddForceLUT[r2_high];
// Fx      = dx * ForceLJ;
// Fy      = dy * ForceLJ;
// Fz      = dz * ForceLJ;
// if(ResetFtot) 
// {
//   Fx_tot = 0;
//   Fy_tot = 0;
//   Fz_tot = 0;
// }
// else if (pipe)
// {  
//   Fx_tot += Fx;
//   Fy_tot += Fy;
//   Fz_tot += Fz;
// }
//
// #operations: 9 multiplications, 7 additions


module ForceNonBond
#(
parameter ForceLUTWidth  = 9      //length of Force LUT data line
)
(
input                                     IOclk,         
input                                     CalcClk,
//input that writes into Force-LUT; on IOclk
input                                     wrForceLUT,    
input              [ForceLUTWidth*8-1:0]  dataForceLUT, 
input              [8:0]                  adrForceLUT,   
input                                     selForceLUT,   
//stuff related to actual force calculation, on CalcClk
input                                     ResetFtot,
input                                     pipe,
input       signed [23:0]                 dx,
input       signed [23:0]                 dy,
input       signed [23:0]                 dz,
output reg  signed [31:0]                 Fx_tot,
output reg  signed [31:0]                 Fy_tot, 
output reg  signed [31:0]                 Fz_tot
);

localparam nPipe_dq       = 12;  //for dx,dy,dz
localparam nPipe_r2       = 5;
localparam nPipe_ForceLUT = 2;

wire signed [47:0]      Fx, Fy, Fz;
reg  signed [47:0]      Fx_tot_long = 1'b0;
reg  signed [47:0]      Fy_tot_long = 1'b0; 
reg  signed [47:0]      Fz_tot_long = 1'b0;
wire signed [47:0]      dx2, dy2, dz2;
reg  signed [47:0]      dz2_d0;
reg  signed [47:0]      r2long = 1'b0, r2tmp =1'b0;
wire signed [29:0]      r2 = r2long[47:18];
reg  signed [29:0]      r2_pipe[nPipe_r2:0];
wire        [16:0]      r4;
reg  signed [23:0]      dx_pipe[nPipe_dq:0] ,dy_pipe[nPipe_dq:0] ,dz_pipe[nPipe_dq:0];
integer                 i;
wire        [71:0]      ForceLUTout;
reg  signed [23:0]      ForceLUT[nPipe_ForceLUT :0];
wire signed [23:0]      dForceLUT;
reg  signed [23:0]      ddForceLUT;
wire signed [23:0]      dForceLJ;
wire signed [23:0]      ddForceLJ;
reg  signed [23:0]      ForceLJ;
reg  signed [23:0]      ForceLJ_d0;


//memories containing LUTs for LennardJones forces
bram_72x512 LJ_LUT (
  .clka(IOclk),           
  .ena(~selForceLUT),      
  .wea(wrForceLUT),      
  .addra(adrForceLUT),  
  .dina(dataForceLUT),    
  .clkb(CalcClk), 
  .enb(1'b1),
  .addrb(r2[25:17]),    //leading 9 bits encoding up to fixed point 1
  .doutb(ForceLUTout)    
);
 
mult24x24    mult_dx2 (.CLK(CalcClk),.A(dx),.B(dx),.P(dx2));
mult24x24    mult_dy2 (.CLK(CalcClk),.A(dy),.B(dy),.P(dy2));
mult24x24    mult_dz2 (.CLK(CalcClk),.A(dz),.B(dz),.P(dz2));

mult_u17xu17 mult_r4 (.CLK(CalcClk),.A(r2[16:0]),.B(r2[16:0]),.P(r4)); //done with 1 DSP; latency 3

assign dForceLUT   = {ForceLUTout[47:24]}; 

wire [40:0] dForceLJ_tmp;
mult_s24xu17 mult_dForce (.CLK(CalcClk),.A(dForceLUT),.B(r2_pipe[1][16:0]),.P(dForceLJ_tmp)); //done with 1 DSP; use maximum bit resolution of DSP48, latency 3
assign dForceLJ=dForceLJ_tmp[40:17]; //that is new since mult_s24xu17 has been chnaged to output all bits

wire [40:0] ddForceLJ_tmp;
mult_s24xu17 mult_ddForce (.CLK(CalcClk),.A(ddForceLUT),.B(r4),.P(ddForceLJ_tmp)); //done with 1 DSP; use maximum bit resolution of DSP48, latency 3
assign ddForceLJ=ddForceLJ_tmp[40:17]; //that is new since mult_s24xu17 has been chnaged to output all bits

mult24x24    mult_Fx (.CLK(CalcClk),.A(dx_pipe[nPipe_dq]),.B(ForceLJ),.P(Fx));
mult24x24    mult_Fy (.CLK(CalcClk),.A(dy_pipe[nPipe_dq]),.B(ForceLJ),.P(Fy));
mult24x24    mult_Fz (.CLK(CalcClk),.A(dz_pipe[nPipe_dq]),.B(ForceLJ),.P(Fz));

always @(posedge CalcClk) begin
//shift intermediate results for later usage
   for(i=1;i<=nPipe_dq;i=i+1) begin   
       dx_pipe[i]<=dx_pipe[i-1];
       dy_pipe[i]<=dy_pipe[i-1];
       dz_pipe[i]<=dz_pipe[i-1];
    end 
    for(i=1;i<=nPipe_r2;i=i+1) begin   
       r2_pipe[i]<=r2_pipe[i-1];
    end     
    for(i=1;i<=nPipe_ForceLUT;i=i+1) begin   
       ForceLUT[i]<=ForceLUT[i-1];
    end 
         
//actual pipeline 
//level 1 of pipeline
    //initiate dx2 <= dx*dx;  //done in mult_dx2, latency 4
    //initiate dy2 <= dy*dy;  //done in mult_dy2, latency 4
    //initiate dz2 <= dz*dz;  //done in mult_dz2, latency 4   
    dx_pipe[0] <= dx;
    dy_pipe[0] <= dy;
    dz_pipe[0] <= dz;
//level 2 of pipeline
//level 3 of pipeline
//level 4 of pipeline    
//level 5 of pipeline, dx2,dy2,dz2 available now
    r2tmp  <= dx2 + dy2;  //separation of that tripple sum needed at 300MHz
    dz2_d0 <= dz2;
//level 6 of pipeline 
    r2long <= r2tmp + dz2_d0;  //also evaluates r2 = r2long[47:22] and adrLUTb=r2[21:12], which enters LUT memory that has latency 2
    //initiate r4 <= r2[16:0]*r2[16:0]; done in mult_r4
//level 7 of pipeline
    r2_pipe[0]  <= r2;        
//level 8 of pipeline, output of LUT memory is available now  
    //initiate dForceLJ  <= dForceLUT*r2_pipe[1][16:0]; 24bit*17bit, done in mult_dForce, latency 3
//level 9 of pipeline
    ForceLUT[0] <= ForceLUTout[71:48]; 
    ddForceLUT  <= ForceLUTout[23:0];
    //initiate ddForceLJ  <= ddForceLUT*r4; 24bit*17bit, done in mult_ddForce, latency 3
//level 10 of pipeline
//level 11 of pipeline
//level 12 of pipeline, dForceLJ  avalable now  
    ForceLJ_d0  <= ForceLUT[nPipe_ForceLUT]+dForceLJ;
//level 13 of pipeline;ddForceLJ available now
    ForceLJ     <= (r2_pipe[nPipe_r2]<30'h4000000) ? ForceLJ_d0+ddForceLJ : 24'b0;  //quadratic interpolation and cut-off if r2<1
//level 14th of pipeline 
    //initiate Fx     <= ForceLJ*dx_pipe[nPipe_dq];  //done in mult_Fx, latency 4
    //initiate Fy     <= ForceLJ*dy_pipe[nPipe_dq];  //done in mult_Fy, latency 4
    //initiate Fz     <= ForceLJ*dz_pipe[nPipe_dq];  //done in mult_Fz, latency 4
//level 15th of pipeline
//level 16th of pipeline
//level 17th of pipeline
//level 18 of pipeline,Fx,Fy,Fz available now
    if(ResetFtot) begin
      Fx_tot_long <= 1'b0;
      Fy_tot_long <= 1'b0;
      Fz_tot_long <= 1'b0;
    end else if (pipe) begin
//comment out when NOT accumulating all forces   
      Fx_tot_long <= Fx_tot_long + Fx;
      Fy_tot_long <= Fy_tot_long + Fy;
      Fz_tot_long <= Fz_tot_long + Fz;   
//comment out when adding up forces      
//      Fx_tot_long <=  Fx;
//      Fy_tot_long <=  Fy;
//      Fz_tot_long <=  Fz;
    end        
//level 19 of pipeline, extra FF stage to faciitate routing     
    Fx_tot <= Fx_tot_long[45:14];   //32 bit in range +/-1 (in Fx_tot_long, two extra bits are generated  due to signed 24*24 mult, and the extra bit in dx
    Fy_tot <= Fy_tot_long[45:14]; 
    Fz_tot <= Fz_tot_long[45:14]; 
  end

endmodule
