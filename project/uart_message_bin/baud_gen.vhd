-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: baud_gen
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--
-- -------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- This module generates a single-cycle pulse at the specified baud rate.
-- The baud tick is used to trigger the UART transmitter.
entity baud_gen is
    generic (
        CLK_FREQ  : integer := 100_000_000;  -- machine clock frequency (Hz)
        BAUD_RATE : integer := 115200        -- default baud rate (bits per second)
    );
    port (
        Clk        : in  std_logic;
        Rst        : in  std_logic; -- active low
        baud_tick  : out std_logic  -- single cycle pulse per baud period
    );
end entity;

architecture Behavioral of baud_gen is
    constant BAUD_TICK_COUNT : integer := CLK_FREQ / BAUD_RATE; -- number of clock cycles per baud period

    signal counter : integer range 0 to BAUD_TICK_COUNT := 0;   -- counts clock cycles to determine when to generate ticks
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
                -- pulses are single-cycle, so we clear them at the start of each clock cycle
                tick_s <= '0';
                if counter = BAUD_TICK_COUNT - 1 then
                    counter <= 0;               -- reset counter for next baud period
                    tick_s <= '1';
                else
                    counter <= counter + 1;     -- update counter for next cycle
                end if;
            end if;
        end if;
    end process;

    baud_tick <= tick_s;

end Behavioral;