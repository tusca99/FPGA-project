----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 18.10.2023 12:45:27
-- Design Name: 
-- Module Name: tb_counter - Behavioral
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

entity tb_transmitter is
--    port ( 
--        CLK100MHZ       : in std_logic; --clock port
--        ck_rst          : in std_logic; --Reset port
--        btn             : in std_logic_vector(3 downto 0); --button port
----        sw              : in std_logic_vector(3 downto 0); --switch port
--        uart_rxd_out    : out std_logic --uart reciver output
----        Busy            : out std_logic  --Busy state port
--      );
end tb_transmitter;

architecture Behavioral of tb_transmitter is

signal CLK100MHZ    : std_logic := '0';
signal ck_rst       : std_logic := '1';
signal btn          : std_logic_vector(3 downto 0) := (others => '0');
signal uart_rxd_out : std_logic;
signal ok   : std_logic;
signal data : std_logic_vector( 7 downto 0 ) := "00111101";
signal Dval : std_logic := '0';
signal button_reg   : std_logic  := '0';
signal button_reg_2 : std_logic  := '0';
constant clk_period : time := 10 ns;

component Transmitter is
    generic (Period: POSITIVE := 868
            );
    port ( 
        Clk  : in std_logic; --clock port
        Rst  : in std_logic; --Reset port
        DVal : in std_logic; --Data Valid port
        Data : in std_logic_vector(7 downto 0); --Data port
        Dout : out std_logic;  --Data out port
        Busy : out std_logic  --Busy state port
      );
end component;

begin

ok <= btn(0) or btn(1) or btn(2) or btn(3) ;

Tra : Transmitter
    generic map(
            Period => 868
            )
     port map (
            Clk     => CLK100MHZ,
            Rst     => ck_rst,
            Dval    => Dval,
            Data    => data,
            Dout    => uart_rxd_out
     );

CLK100MHZ <= not CLK100MHZ after clk_period/2;

test : process
begin
    btn(0) <= '1';
    wait for 300 ns;
    btn <= (others =>'0');
    ck_rst <= '0';
    wait for 20 ns;
    ck_rst <= '1';
    btn(0) <= '1';
    wait for 200 ns;
    btn <= (others =>'0');
    wait;
end process;

edge_d :process( CLK100MHZ )
begin
    if( rising_edge(CLK100MHZ)) then
        button_reg <= ok;
        button_reg_2 <= button_reg;
        if( button_reg = '1') and (button_reg_2 = '0') then
            Dval <= '1';
        else
            Dval <= '0';
        end if;
     end if;
end process;


end Behavioral;
