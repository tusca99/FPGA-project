----------------------------------------------------------------------------------
-- Testbench for modular UART TX (baud_gen + uart_tx)
-- Instantiates `baud_gen` and `uart_tx` to verify TX waveform
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_mod_tx_tb is
end uart_mod_tx_tb;

architecture tb of uart_mod_tx_tb is

    -- DUT signals
    signal Clk       : std_logic := '0';
    signal Rst       : std_logic := '1'; -- active LOW

    -- baud gen outputs
    signal baud_tick : std_logic;
    signal half_tick : std_logic;

    -- uart_tx signals
    signal tx_start  : std_logic := '0';
    signal tx_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy   : std_logic;
    signal uart_tx_o : std_logic := '1';

    constant CLK_PERIOD : time := 10 ns; -- 100 MHz

    -- component declarations (explicit)
    component baud_gen
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
    end component;

    component uart_tx
        Port (
            Clk       : in  std_logic;
            Rst       : in  std_logic; -- active low
            baud_tick : in  std_logic;
            tx_start  : in  std_logic;
            tx_data   : in  std_logic_vector(7 downto 0);
            tx_busy   : out std_logic;
            uart_tx_o : out std_logic
        );
    end component;

begin

    ---------------------------------------------------------------------
    -- Instantiate DUT: baud_gen + uart_tx
    ---------------------------------------------------------------------
    baud_i : baud_gen
        generic map (
            CLK_FREQ  => 100_000_000,
            BAUD_RATE => 115200
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick,
            half_tick => half_tick
        );

    tx_i : uart_tx
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick,
            tx_start  => tx_start,
            tx_data   => tx_data,
            tx_busy   => tx_busy,
            uart_tx_o => uart_tx_o
        );

    ---------------------------------------------------------------------
    -- Clock generation
    ---------------------------------------------------------------------
    clk_proc : process
    begin
        while now < 200 ms loop
            Clk <= '0';
            wait for CLK_PERIOD/2;
            Clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    ---------------------------------------------------------------------
    -- Stimulus
    ---------------------------------------------------------------------
    stim_proc : process
    begin
        -- reset active low
        Rst <= '0';
        wait for 200 ns;
        Rst <= '1';
        wait for 200 ns;

        -- First transfer: send 'a' (0x61)
        tx_data <= x"61";
        -- pulse tx_start for one clock cycle
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';

        -- wait enough time for 10-bit frame @115200 ~ 87 us -> use margin
        wait for 200 us;

        -- Another transfer: send 'F' (0x46)
        tx_data <= x"46";
        wait for 10 us;
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';

        wait for 200 us;

        -- finish
        wait;
    end process;

end tb;
