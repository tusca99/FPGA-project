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

entity top_multi_transmitter is
    port ( 
        CLK100MHZ       : in std_logic; --clock port
        ck_rst          : in std_logic; --Reset port
        btn             : in std_logic_vector(3 downto 0); --button port
--        sw              : in std_logic_vector(3 downto 0); --switch port
        uart_rxd_out    : out std_logic --uart reciver output
--        Busy            : out std_logic  --Busy state port
      );
end top_multi_transmitter;

architecture Behavioral of top_multi_transmitter is

signal ok   : std_logic;
signal data : std_logic_vector( 8*7 -1 downto 0 ) := x"20616e616e6162";
signal Dval : std_logic := '0';
signal button_reg   : std_logic := '0';
signal button_reg_2 : std_logic := '0';
--signal ck_rst       : std_logic := '1';

component Multi_Word_Transmitter is
    generic (
                Period: POSITIVE := 868;
                N :     POSITIVE := 8
            );
    port ( 
        Rst     : in std_logic; --clock port
        Clk     : in std_logic; --Reset port
        DVal    : in std_logic; --Data Valid port
        Data    : in std_logic_vector((N*8)-1 downto 0); --Data port
        Dout    : out std_logic;  --Data out port
        Busy    : out std_logic  --Busy state port
      );
end component;

begin

ok <= btn(0) or btn(1) or btn(2) or btn(3) ;

Tra : Multi_Word_Transmitter
    generic map(
            Period  => 868,
            N       => 7
            )
     port map (
            Clk     => CLK100MHZ,
            Rst     => ck_rst,
            Dval    => Dval,
            Data    => data,
            Dout    => uart_rxd_out,
            Busy    => open
     );

--edge_d :process( CLK100MHZ )
--begin
--    if( rising_edge(CLK100MHZ)) then
--        button_reg <= ok;
--        button_reg_2 <= button_reg;
--        if( button_reg = '1') and (button_reg_2 = '0') then
--            Dval <= '1';
--        else
--            Dval <= '0';
--        end if;
--     end if;
--end process;
edge_d: process(CLK100MHZ)
begin
    if rising_edge(CLK100MHZ) then
        if ck_rst = '0' then
            button_reg <= '0';
            button_reg_2 <= '0';
            Dval <= '0';
        else
            button_reg <= ok;
            button_reg_2 <= button_reg;
            
            if (button_reg = '1') and (button_reg_2 = '0') then
                Dval <= '1';
            else
                Dval <= '0';
            end if;
        end if;
    end if;
end process;

end Behavioral;
