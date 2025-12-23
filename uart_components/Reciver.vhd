----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 12/01/2025 09:43:23 AM
-- Design Name: 
-- Module Name: Reciver - Behavioral
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

entity Reciver is
generic (Period: POSITIVE := 868
            );
    port ( 
        Rst     : in std_logic; --Reset port
        Clk     : in std_logic; --clock port
        Data    : in std_logic; --Data port
        Dout    : out std_logic_vector(7 downto 0);  --Data out port
        DVal    : out std_logic --Data Valid port
        -- Busy    : out std_logic  --Busy state port
      );
end Reciver;

architecture Behavioral of Reciver is

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
signal baud_half  : std_logic := '0';
signal stop_pulse : std_logic := '0';
constant half_bp  : POSITIVE := Period / 2;
type state_t is (idle, data_valid, start, BIT_0, BIT_1, BIT_2, BIT_3, BIT_4, BIT_5, BIT_6, BIT_7, stop);
signal state : state_t;
signal data_reg : std_logic_vector(7 downto 0) := (others => '0');

begin

BAUDRG : Baud_rate_generator
    generic map( 
        Period => Period
        )
     port map(
        Clk     => Clk,
        res     => stop_pulse,
        O       => baud_pulse
        );

HALFBRG : Baud_rate_generator
    generic map( 
        Period => half_bp
        )
     port map(
        Clk     => Clk,
        res     => stop_pulse,
        O       => baud_half
        );

reciver : process( Clk)
begin
    if rising_edge(Clk) then
        if Rst = '0' then
            State <= idle;
            data_reg <= (others => '0');
            stop_pulse <= '0';
        else
            case State is
                when idle =>    DVal <= '0';
                                if Data = '0' then
                                    State <= start;
                                    stop_pulse <= '1';
                                end if;
                when start =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    data_reg <= (others => '0');
                                    DVal <= '0';
                                    State <= BIT_0;
                                end if;
                when BIT_0 =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    State <= BIT_1;
                                    data_reg(0) <= Data;
                                end if;
                when BIT_1 =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    State <= BIT_2;
                                    data_reg(1) <= Data;
                                end if;
                when BIT_2 =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    State <= BIT_3;
                                    data_reg(2) <= Data;
                                end if;
                when BIT_3 =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    State <= BIT_4;
                                    data_reg(3) <= Data;
                                end if;
                when BIT_4 =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    State <= BIT_5;
                                    data_reg(4) <= Data;
                                end if;
                when BIT_5 =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    State <= BIT_6;
                                    data_reg(5) <= Data;
                                end if;
                when BIT_6 =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    State <= BIT_7;
                                    data_reg(6) <= Data;
                                end if;
               when BIT_7 =>   if ( baud_half = '1') and ( baud_pulse = '0' ) then
                                    State <= stop;
                                    data_reg(7) <= Data;
                                end if;
               when stop  =>    if ( baud_half = '1') then
                                    stop_pulse <= '0';
                                    State <= idle;
                                    Dout <= data_reg;
                                    DVal <= '1';
                                end if;
                when others     => State <= idle;
                                   stop_pulse <= '0';
            end case;
        end if;
        else null;
    end if;

end process;


end Behavioral;
