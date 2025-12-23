----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/24/2025 09:09:21 AM
-- Design Name: 
-- Module Name: Multi_Word_Transmitter - Behavioral
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

entity Multi_Word_Transmitter is
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
end Multi_Word_Transmitter;

architecture Behavioral of Multi_Word_Transmitter is


signal baud_pulse : std_logic := '0';
signal out_char   : std_logic_vector( 7 downto 0);
signal tran_busy  : std_logic := '0';
signal tran_dval  : std_logic := '0';
signal char_count : integer range 0 to N := 0;  --counter of current character;
signal data_reg   : std_logic_vector((N*8)-1 downto 0); --data register
type state_t is (idle, data_valid, waiting, transmitting, stop);
signal state : state_t;

--signal ok   : std_logic;
--signal data : std_logic_vector( 7 downto 0 ) := "00111101";
--signal Dval : std_logic := '0';
--signal button_reg   : std_logic := '0';
--signal button_reg_2 : std_logic := '0';
----signal ck_rst       : std_logic := '1';

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

component Baud_rate_generator is

    generic (Period: POSITIVE := 868
            );
    port(
      Clk   : in std_logic;
      res   : in std_logic;
      O     : out std_logic  
    );

end component;

begin

BAUD : Baud_rate_generator
    generic map( 
        Period => Period
        )
     port map(
        Clk     => Clk,
        res     => Rst,
        O       => baud_pulse
        );

Tra : Transmitter
    generic map(
            Period => Period
            )
     port map (
            Clk     => Clk,
            Rst     => Rst,
            Dval    => tran_dval,
            Data    => out_char,
            Dout    => Dout,
            Busy    => tran_busy
     );


process(Clk) is
begin
    if rising_edge(Clk) then
        if Rst = '0' then
            State <= idle;
            -- Dout  <= '1';
            Busy  <= '0';
        else
            case State is
                when idle           => if tran_busy = '1' then
                                            Busy <= '1';
                                       else
                                            Busy <= '0';
                                       end if;
--                when idle           => Busy <= '0';
                                       -- Dout <= '1';
                                       tran_dval <= '0';
                                       char_count  <= 0;
                                       if DVal = '1' then
                                           data_reg <= Data;
                                           State <= data_valid;
                                       end if;
                when data_valid     => Busy <= '1';
                                       tran_dval <= '0';
                                       if baud_pulse = '1' then
                                           State <= waiting;
                                       end if;
                when waiting        => Busy <= '1';
                                       if baud_pulse = '1' and tran_busy = '0' then
                                           if (char_count < N ) then
                                                out_char    <= data_reg( ( (char_count+1) * 8 ) - 1 downto (char_count) * 8  );
                                           end if;
                                           State <= transmitting;
                                           tran_dval <= '1';
                                           char_count  <= char_count + 1;
                                       end if;
                when transmitting   => Busy <= '1';
                                       if (char_count < N ) then
                                            State <= waiting;
                                            tran_dval <= '0';
                                        else
                                            State <= stop;
                                            tran_dval <= '0';
                                        end if;
                when stop           => -- Dout <= '1';
                                       Busy <= '1';
                                       if baud_pulse = '1' then
                                           State <= idle;
                                       end if;
                when others         => State <= idle;
                                       Busy <= '0';
                                       -- Dout <= '1';
            end case;
        end if;
        else null;
    end if;
end process;

end Behavioral;
