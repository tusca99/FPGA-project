library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_uart_top_tb is
end entity;

architecture Behavioral of percolation_uart_top_tb is
    constant CLK_FREQ  : integer := 100_000_000;
    constant BAUD_RATE : integer := 115200;
    constant REQ_BYTES : positive := 24;
    constant RSP_BYTES : positive := 20;
    constant CLK_PERIOD : time := 10 ns;
    constant BIT_CLKS   : integer := CLK_FREQ / BAUD_RATE;
    constant BIT_TIME   : time := BIT_CLKS * CLK_PERIOD;

    signal Clk       : std_logic := '0';
    signal Rst       : std_logic := '0';
    signal uart_rx_i : std_logic := '1';
    signal uart_tx_o : std_logic;

    signal dec_baud_tick_s : std_logic := '0';
    signal dec_half_tick_s : std_logic := '0';

    signal rsp_msg_s   : std_logic_vector(RSP_BYTES*8-1 downto 0);
    signal rsp_valid_s : std_logic := '0';
    signal rsp_busy_s  : std_logic := '0';

    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant REQ_BYTES_VEC : byte_array_t(0 to REQ_BYTES-1) := (
        x"99", x"99", x"99", x"9A", -- CfgP = approx 0.6
        x"00", x"00", x"00", x"08", -- CfgGridSize = 8
        x"12", x"34", x"56", x"78", -- CfgSeed
        x"00", x"00", x"00", x"10", -- CfgRuns = 16
        x"00", x"00", x"00", x"07", -- ctrl: init/run/step bits set
        x"00", x"00", x"00", x"01"  -- StepAddCount = 1
    );

    procedure send_uart_byte(signal line : out std_logic; constant data_byte : in std_logic_vector(7 downto 0)) is
    begin
        line <= '0';
        wait for BIT_TIME;

        for bit_index in 0 to 7 loop
            line <= data_byte(bit_index);
            wait for BIT_TIME;
        end loop;

        line <= '1';
        wait for BIT_TIME;
    end procedure;

begin
    clk_proc : process
    begin
        while true loop
            Clk <= '0';
            wait for CLK_PERIOD / 2;
            Clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    baud_dec_inst : entity work.baud_gen
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => dec_baud_tick_s,
            half_tick => dec_half_tick_s
        );

    dut : entity work.percolation_uart_top
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE,
            REQ_BYTES => REQ_BYTES,
            RSP_BYTES => RSP_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            uart_rx_i => uart_rx_i,
            uart_tx_o => uart_tx_o
        );

    rsp_rx_inst : entity work.uart_msg_rx
        generic map (
            N_BYTES => RSP_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => dec_baud_tick_s,
            half_tick => dec_half_tick_s,
            uart_rx_i => uart_tx_o,
            msg_data  => rsp_msg_s,
            msg_valid => rsp_valid_s,
            busy      => rsp_busy_s
        );

    stim_proc : process
    begin
        Rst <= '0';
        wait for 200 ns;
        Rst <= '1';
        wait for 200 ns;

        for byte_index in REQ_BYTES_VEC'range loop
            send_uart_byte(uart_rx_i, REQ_BYTES_VEC(byte_index));
        end loop;

        for cycle_index in 0 to 1_000_000 loop
            wait until rising_edge(Clk);
            if rsp_valid_s = '1' then
                exit;
            end if;
        end loop;

        assert rsp_valid_s = '1'
            report "Response message was not received" severity failure;

        assert rsp_msg_s = (others => '0')
            report "Unexpected response payload in smoke test" severity failure;

        report "Percolation UART top smoke test passed" severity note;
        wait;
    end process;

end Behavioral;