-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: percolation_uart_top_tb
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--   - percolation_uart_top.vhd
--   - baud_gen.vhd
--   - uart_msg_rx.vhd
--
-- -------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_uart_top_tb is
end entity;

-- Testbench for the percolation_uart_top module. This testbench sends a configuration message over UART to the module, waits for the response, and checks that the results are as expected.
architecture Behavioral of percolation_uart_top_tb is
    constant N_ROWS_G : positive := 64;             -- MUST match hardware capabilities (not 256)
    constant CLK_FREQ  : integer := 100_000_000;    -- 100 MHz clock frequency (used for baud generation)
    constant BAUD_RATE : integer := 921600;      -- Use a high baud rate for faster testing (must be supported by the hardware and UART modules)
    constant REQ_BYTES : positive := 16;
    constant RSP_BYTES : positive := 16;
    constant ZERO_RSP  : std_logic_vector(RSP_BYTES*8-1 downto 0) := (others => '0');
    constant CLK_PERIOD : time := 10 ns;
    constant BIT_CLKS   : integer := CLK_FREQ / BAUD_RATE;
    constant BIT_TIME   : time := BIT_CLKS * CLK_PERIOD;

    signal Clk       : std_logic := '0';
    signal Rst       : std_logic := '0';
    signal uart_rx_i : std_logic := '1';
    signal uart_tx_o : std_logic;
    signal led_rgb_o  : std_logic_vector(2 downto 0);
    signal baud_tick_s : std_logic := '0';


    signal rsp_msg_s   : std_logic_vector(RSP_BYTES*8-1 downto 0);
    signal rsp_valid_s : std_logic := '0';
    signal rsp_busy_s  : std_logic := '0';

    -- Signals for percolation core configuration and results (monitored for debugging, different configuration from the test message)
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant REQ_BYTES_VEC : byte_array_t(0 to REQ_BYTES-1) := (
--        x"4C", x"CC", x"CC", x"CC", -- Word 0: CfgP = approx 0.3
--        x"33", x"33", x"33", x"33", -- Word 0: CfgP = approx 0.2
        x"99", x"99", x"99", x"9A", -- Word 0: CfgP = approx 0.6
--        x"20", x"00", x"00", x"00", -- Word 0: CfgP = approx 0.1
        x"12", x"34", x"56", x"78", -- Word 1: CfgSeed
        x"00", x"00", x"00", x"40", -- Word 2: CfgStepsPerRun=64
        x"00", x"00", x"00", x"10"  -- Word 3: CfgRuns=16
    );

    -- Procedure to send a byte over the UART receive line, simulating a UART transmission from the host. 
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
    -- Clock generator (100 MHz)
    clk_proc : process
    begin
        while true loop
            Clk <= '0';
            wait for CLK_PERIOD / 2;
            Clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    -- Instantiate the percolation_uart_top module and connect the signals. 
    -- The testbench will drive the uart_rx_i signal to send configuration messages and monitor the uart_tx_o signal for responses.
    dut : entity work.percolation_uart_top
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
            led_rgb_o  => led_rgb_o
        );

    baud_inst : entity work.baud_gen
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s
        );

    rsp_rx_inst : entity work.uart_msg_rx
        generic map (
            CLK_FREQ => CLK_FREQ,
            BAUD_RATE => BAUD_RATE,
            N_BYTES => RSP_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
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

        -- Check the response message for expected values. 
        -- The exact expected values depend on the configuration sent and the behavior of the percolation core, but we can check for some basic sanity conditions 
        -- (e.g., StepCount should be 16, SpanningCount should be <= StepCount, TotalOccupied should be > 0, etc.).
        assert rsp_valid_s = '1'
            report "Response message was not received" severity failure;

--        assert rsp_msg_s(127 downto 96) = x"00000010"
--            report "Unexpected StepCount in response: expected 16 completed runs" severity failure;
        assert rsp_msg_s(127 downto 96) = x"00000010"
            report "Unexpected StepCount in response: expected 16 completed runs" severity failure;

        -- SpanningCount can vary with threshold, but must be <= StepCount
        assert unsigned(rsp_msg_s(95 downto 64)) <= unsigned(rsp_msg_s(127 downto 96))
            report "SpanningCount exceeds StepCount: " & 
                   integer'image(to_integer(unsigned(rsp_msg_s(95 downto 64)))) & " > " &
                   integer'image(to_integer(unsigned(rsp_msg_s(127 downto 96)))) severity failure;
        
        report "SpanningCount: " & integer'image(to_integer(unsigned(rsp_msg_s(95 downto 64)))) severity note;

        assert unsigned(rsp_msg_s(63 downto 32)) > 0
            report "Expected non-zero TotalOccupied" severity failure;

        assert rsp_msg_s(31 downto 0) = x"00000000"
            report "Expected Status = 0 (success)" severity failure;

        report "Percolation UART top smoke test passed" severity note;
        wait;
    end process;

end Behavioral;