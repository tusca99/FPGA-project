----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/10/2025 10:09:39 AM
-- Design Name: 
-- Module Name: Transmitter - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Transmitter is
    generic (Period: POSITIVE := 868
            );
    port ( 
        Rst     : in std_logic; --clock port
        Clk     : in std_logic; --Reset port
        DVal    : in std_logic; --Data Valid port
        Data    : in std_logic_vector(7 downto 0); --Data port
        Dout    : out std_logic;  --Data out port
        Busy    : out std_logic  --Busy state port
      );
end Transmitter;

architecture Behavioral of Transmitter is

component StateMachine is

    port(
      Clk   : in std_logic; --Clock port
      BRT   : in std_logic; --BAUD rate generator
      Rst   : in std_logic; --Reset port
      DVal  : in std_logic; --Data Valid port
      Data  : in std_logic_vector(7 downto 0); --Data port
      Dout  : out std_logic;  --Data out port
      Busy  : out std_logic  --Busy state port
    );  

end component;

component Baud_rate_generator is

    generic (Period: POSITIVE := 868
            );
    port(
      Clk   : in std_logic;
      res   : in std_logic;
      O     : out std_logic
    );

end component;

signal baud_pulse : std_logic := '0';


begin

SM : StateMachine
    port map(
        Clk     => Clk,
        BRT     => baud_pulse,
        Rst     => Rst, 
        DVal    => DVal,
        Data    => Data,  
        Dout    => Dout,
        Busy    => Busy
        );

BAUD : Baud_rate_generator
    generic map( 
        Period => Period
        )
     port map(
        Clk     => Clk,
        res     => Rst,
        O       => baud_pulse
        );
 
end Behavioral;
