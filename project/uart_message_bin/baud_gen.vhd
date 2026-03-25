library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity baud_gen is
    generic (
        CLK_FREQ  : integer := 100_000_000;
        BAUD_RATE : integer := 115200
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic; -- active low
        baud_tick : out std_logic;
        half_tick : out std_logic
    );
end baud_gen;

architecture Behavioral of baud_gen is
    constant BAUD_TICK_COUNT : integer := CLK_FREQ / BAUD_RATE;
    constant HALF_TICK_COUNT : integer := BAUD_TICK_COUNT / 2;

    signal counter : integer range 0 to BAUD_TICK_COUNT - 1 := 0;
    signal tick_s  : std_logic := '0';
    signal half_s  : std_logic := '0';
begin

    process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                counter <= 0;
                tick_s  <= '0';
                half_s  <= '0';
            else
                tick_s <= '0';
                half_s <= '0';

                if counter = BAUD_TICK_COUNT - 1 then
                    counter <= 0;
                    tick_s <= '1';
                else
                    if counter = HALF_TICK_COUNT - 1 then
                        half_s <= '1';
                    end if;
                    counter <= counter + 1;
                end if;
            end if;
        end if;
    end process;

    baud_tick <= tick_s;
    half_tick <= half_s;

end Behavioral;