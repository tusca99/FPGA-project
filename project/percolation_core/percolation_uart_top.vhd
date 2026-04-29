library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_uart_top is
    generic (
        CLK_FREQ  : integer := 100_000_000;
        BAUD_RATE : integer := 9600;
        N_ROWS_G  : positive := 64;
        REQ_BYTES : positive := 16;
        RSP_BYTES : positive := 16
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic; -- active low
        uart_rx_i : in  std_logic;
        uart_tx_o : out std_logic;
        btn_init_i : in  std_logic := '1'; -- button for manual init (active low)
        btn_run_i  : in  std_logic := '1'; -- button for manual run (active low)
        led_rgb_o  : out std_logic_vector(2 downto 0)
    );
end percolation_uart_top;

architecture Behavioral of percolation_uart_top is
    signal slim_led_rgb_s : std_logic_vector(2 downto 0) := (others => '0');
    signal btn_any_s : std_logic := '1';
begin
    btn_any_s <= btn_init_i and btn_run_i;

    slim_inst : entity work.percolation_uart_top_slim
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE,
            N_ROWS_G  => N_ROWS_G,
            REQ_BYTES => REQ_BYTES,
            RSP_BYTES => RSP_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            uart_rx_i => uart_rx_i,
            uart_tx_o => uart_tx_o,
            led_rgb_o => slim_led_rgb_s
        );

    led_rgb_o <= slim_led_rgb_s when btn_any_s = '1' else "100";
end Behavioral;
