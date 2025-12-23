----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.10.2023 15:52:15
-- Design Name: 
-- Module Name: counter - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Baud_rate_generator is
    generic (Period: POSITIVE := 868
            );
    port(
      Clk : in std_logic;
      res : in std_logic;
      O      : out std_logic  
    );

end Baud_rate_generator;

--architecture Behavioral of Baud_rate_generator is
--signal count : integer := 0;
---- signal count : unsigned(32 downto 0) :=(others => '0');

--begin

--process(Clk)
--begin 
--    if(rising_edge(Clk)) then
--        if(res = '0') then
--            count <= 0;
--        else
--            count <= count + 1;
--        end if;
--        if( count >= Period - 1) then
--            O <= '1';
--            count <= 0;
--        else 
--            O <= '0';
--        end if;
--    end if;       
--end process;
   
--end Behavioral;

architecture Behavioral of Baud_rate_generator is
    signal count : integer range 0 to Period-1 := 0;  -- Better to constrain range
begin

process(Clk)
begin 
    if rising_edge(Clk) then
        if res = '0' then
            count <= 0;
            O <= '0';  -- Explicit output during reset
        else
            if count >= Period - 1 then
                O <= '1';
                count <= 0;
            else 
                O <= '0';
                count <= count + 1;
            end if;
        end if;
    end if;       
end process;

end Behavioral;