-- Baud rate generator
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity baud_gen is
    generic (
        CLK_FREQ  : integer := 100_000_000; -- Hz
        BAUD_RATE : integer := 115200        -- default baud
    );
    port (
        Clk        : in  std_logic;
        Rst        : in  std_logic; -- active low
        baud_tick  : out std_logic -- single cycle pulse per baud period
    );
end entity;

architecture Behavioral of baud_gen is
    constant BAUD_TICK_COUNT : integer := CLK_FREQ / BAUD_RATE;

    signal counter : integer range 0 to BAUD_TICK_COUNT := 0;
    signal tick_s  : std_logic := '0';
begin

    process(Clk)
    begin
        if rising_edge(Clk) then
            -- reset is active LOW (keep consistent with other modules)
            if Rst = '0' then
                counter <= 0;
                tick_s  <= '0';
            else
                -- default: pulses are single-cycle
                tick_s <= '0';
                if counter = BAUD_TICK_COUNT - 1 then
                    counter <= 0;
                    tick_s <= '1';
                else
                    counter <= counter + 1;
                end if;
            end if;
        end if;
    end process;

    baud_tick <= tick_s;

end Behavioral;