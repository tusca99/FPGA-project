----------------------------------------------------------------------------------
-- Testbench for uart_tx_top
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx_tb is
end uart_tx_tb;

architecture tb of uart_tx_tb is

    -- DUT signals
    signal Clk          : std_logic := '0';
    signal Rst          : std_logic := '1';   -- active LOW
    signal btn          : std_logic := '0';
    signal uart_rxd_out : std_logic;
    signal uart_txd_in  : std_logic := '1';

    -- Clock period for 100 MHz
    constant CLK_PERIOD : time := 10 ns;

component  uart_tx_top is
    Port (
        Clk          : in  STD_LOGIC;          -- 100 MHz clock
        Rst          : in  STD_LOGIC;          -- Reset active LOW
        btn          : in  STD_LOGIC;  -- Button
        uart_rxd_out : out STD_LOGIC;          -- TX toward PC
        uart_txd_in  : in  STD_LOGIC           -- RX from PC (unused)
    );
end component;

begin

    ---------------------------------------------------------------------
    -- Instantiate the DUT
    ---------------------------------------------------------------------
    DUT : uart_tx_top
    port map (
        Clk          => Clk,
        Rst          => Rst,
        btn          => btn,
        uart_rxd_out => uart_rxd_out,
        uart_txd_in  => uart_txd_in
    );

    ---------------------------------------------------------------------
    -- Clock generation
    ---------------------------------------------------------------------
    Clk_process : process
    begin
        Clk <= '0';
        wait for CLK_PERIOD/2;
        Clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    ---------------------------------------------------------------------
    -- Stimulus Process
    ---------------------------------------------------------------------
    stim_proc : process
    begin

        ------------------------------------------------------------------
        -- Reset sequence
        ------------------------------------------------------------------
        Rst <= '0';
        wait for 200 ns;
        Rst <= '1';
        wait for 200 ns;

        ------------------------------------------------------------------
        -- Simulate a button press (clean edge)
        ------------------------------------------------------------------
        btn <= '1';
        wait for 200 ns;
        btn <= '0';

        ------------------------------------------------------------------
        -- Wait enough time for complete UART frame (10 bits @ 115200 ≈ 87 µs)
        ------------------------------------------------------------------
        wait for 2000 us;

        ------------------------------------------------------------------
        -- Press again
        ------------------------------------------------------------------
        btn <= '1';
        wait for 200 ns;
        btn <= '0';

        wait for 2000 us;

        ------------------------------------------------------------------
        -- End simulation
        ------------------------------------------------------------------
        wait;
    end process;

end tb;
