----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.10.2023 14:26:57
-- Design Name: 
-- Module Name: FSM - Behavioral
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

entity StateMachine is
    port(
      Clk   : in std_logic; --Clock port
      BRT   : in std_logic; --BAUD rate generator
      Rst   : in std_logic; --Reset port
      DVal  : in std_logic; --Data Valid port
      Data  : in std_logic_vector(7 downto 0); --Data port
      Dout  : out std_logic;  --Data out port
      Busy  : out std_logic  --Busy state port
    );  
end StateMachine;

--architecture Behavioral of StateMachine is

--type state_t is (idle, data_valid, start, BIT_0, BIT_1, BIT_2, BIT_3, BIT_4, BIT_5, BIT_6, BIT_7, stop);
--signal state : state_t;

--begin

--process(Clk) is
--begin
----   if(Clk = '1') then
--   if rising_edge(Clk) then
--       if Rst = '0' then
--           State <= idle;
--           Dout  <= '1';
--       else
--         case State is
--            when idle       => Busy <= '0';
--                               Dout <= '1';
--                                if DVal = '1' then
--                                    State <= data_valid;
--                                end if;
--            when data_valid => Busy <= '1';
--                                State <= start;
--            when start      => Dout <= '0';
--                                State <= BIT_0;
--            when BIT_0      => Dout <= Data(0);
--                                State <= BIT_1;
--            when BIT_1      => Dout <= Data(1);
--                                State <= BIT_2;
--            when BIT_2      => Dout <= Data(2);
--                                State <= BIT_3;
--            when BIT_3      => Dout <= Data(3);
--                                State <= BIT_4;
--            when BIT_4      => Dout <= Data(4);
--                                State <= BIT_5;
--            when BIT_5      => Dout <= Data(5);
--                                State <= BIT_6;
--            when BIT_6      => Dout <= Data(6);
--                                State <= BIT_7;
--            when BIT_7      => Dout <= Data(7);
--                                State <= stop;
--            when stop       => Dout <= '1';
--                                State <= idle;
--            when others     => State <= idle;
--                                Busy <= '0';
--                                Dout <= '1';
--         end case;
--      end if;
--   end if;
--end process;

--end Behavioral;

architecture Behavioral of StateMachine is

type state_t is (idle, data_valid, start, BIT_0, BIT_1, BIT_2, BIT_3, BIT_4, BIT_5, BIT_6, BIT_7, stop);
signal state : state_t;
signal data_reg : std_logic_vector(7 downto 0);

begin

process(Clk) is
begin
    if rising_edge(Clk) then
        if Rst = '0' then
            State <= idle;
            Dout  <= '1';
            Busy  <= '0';
        else
            case State is
                when idle       => Busy <= '0';
                                   Dout <= '1';
                                   if DVal = '1' then
                                       State <= data_valid;
                                   end if;
                when data_valid => if BRT = '1' then
                                       Busy <= '1';
                                       State <= start;
                                       data_reg <= Data;
                                   end if;
                when start      => Dout <= '0';
                                   Busy <= '1';
                                   if BRT = '1' then
                                       State <= BIT_0;
                                   end if;
                when BIT_0      => Dout <= data_reg(0);
                                   if BRT = '1' then
                                       State <= BIT_1;
                                   end if;
                when BIT_1      => Dout <= data_reg(1);
                                   if BRT = '1' then
                                       State <= BIT_2;
                                   end if;
                when BIT_2      => Dout <= data_reg(2);
                                   if BRT = '1' then
                                       State <= BIT_3;
                                   end if;
                when BIT_3      => Dout <= data_reg(3);
                                   if BRT = '1' then
                                       State <= BIT_4;
                                   end if;
                when BIT_4      => Dout <= data_reg(4);
                                   if BRT = '1' then
                                       State <= BIT_5;
                                   end if;
                when BIT_5      => Dout <= data_reg(5);
                                   if BRT = '1' then
                                       State <= BIT_6;
                                   end if;
                when BIT_6      => Dout <= data_reg(6);
                                   if BRT = '1' then
                                       State <= BIT_7;
                                   end if;
                when BIT_7      => Dout <= data_reg(7);
                                   if BRT = '1' then
                                       State <= stop;
                                   end if;
                when stop       => Dout <= '1';
                                   if BRT = '1' then
                                       State <= idle;
                                   end if;
                when others     => State <= idle;
                                   Busy <= '0';
                                   Dout <= '1';
            end case;
        end if;
        else null;
    end if;
end process;
end Behavioral;
