-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: percolation_uart_top
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--   - baud_gen.vhd
--   - uart_msg_rx.vhd
--   - uart_msg_tx.vhd
--   - percolation_core.vhd
--
-- -------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Top-level module that integrates the percolation_core with UART communication and a baud generator. 
-- This module receives configuration parameters over UART, runs the percolation simulation, and sends back the results over UART. 
-- It also includes an RGB LED output for status indication.
entity percolation_uart_top is
    generic (
        CLK_FREQ  : integer := 100_000_000;     -- 100 MHz clock frequency (used for baud generation)
        BAUD_RATE : integer := 115200;          -- UART baud rate
        N_ROWS_G  : positive := 180;            -- Number of rows/columns in the percolation grid
        REQ_BYTES : positive := 16;             -- Number of bytes in the UART request message (must match the software side)
        RSP_BYTES : positive := 16              -- Number of bytes in the UART response message (must match the software side)
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic;                      -- active low
        uart_rx_i : in  std_logic;                      -- UART receive line
        uart_tx_o : out std_logic;                      -- UART transmit line
        led_rgb_o  : out std_logic_vector(2 downto 0)   -- RGB LED output for status indication (blue=idle, yellow=running)
    );
end percolation_uart_top;

architecture Behavioral of percolation_uart_top is
    -- Calculate the number of bits in the request and response messages based on the number of bytes.
    constant REQ_BITS : natural := REQ_BYTES * 8;
    constant RSP_BITS : natural := RSP_BYTES * 8;

    -- Define a state machine for controlling the flow of the module.
    type state_t is (IDLE, WAIT_CLEAR, RUN_WAIT, TX_PULSE, TX_WAIT_BUSY, TX_WAIT_DONE);
    signal state : state_t := IDLE;

    signal baud_tick_s : std_logic := '0';                                          -- Baud tick signal from the baud generator to UART trasmitter

    -- Signals for UART receiver
    signal req_msg_s   : std_logic_vector(REQ_BITS-1 downto 0) := (others => '0');
    signal req_valid_s : std_logic := '0';

    -- Signals for UART transmitter
    signal tx_msg_s   : std_logic_vector(RSP_BITS-1 downto 0) := (others => '0');
    signal tx_start_s : std_logic := '0';
    signal tx_busy_s  : std_logic := '0';

    -- Signals for percolation core configuration and results
    signal core_cfg_p_s      : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_steps_s  : unsigned(31 downto 0) := (others => '0');
    signal core_cfg_seed_s   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_runs_s   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_init_s   : std_logic := '0';
    signal core_run_en_s     : std_logic := '0';
    signal core_step_count_s : std_logic_vector(31 downto 0) := (others => '0');
    signal core_spanning_s   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_total_s      : std_logic_vector(31 downto 0) := (others => '0');
    signal core_spanning_occ_s : std_logic_vector(31 downto 0) := (others => '0');
    signal core_done_s       : std_logic := '0';
begin
    -- Set the RGB LED color based on the state of the module: blue for idle, yellow for running, and off for other states.
    led_rgb_o <= "001" when state = IDLE else
                 "110";

    -- Instantiate the baud generator, UART receiver, UART transmitter, and percolation core modules. Connect the signals appropriately.
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

    rx_inst : entity work.uart_msg_rx
        generic map (
            CLK_FREQ => CLK_FREQ,
            BAUD_RATE => BAUD_RATE,
            N_BYTES => REQ_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            uart_rx_i => uart_rx_i,
            msg_data  => req_msg_s,
            msg_valid => req_valid_s,
            busy      => open
        );

    tx_inst : entity work.uart_msg_tx
        generic map (
            N_BYTES => RSP_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s,
            msg_start => tx_start_s,
            msg_data  => tx_msg_s,
            busy      => tx_busy_s,
            uart_tx_o => uart_tx_o
        );

    core_inst : entity work.percolation_core
        generic map (
            N_ROWS_G => N_ROWS_G
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            RunEn          => core_run_en_s,
            StepAddValid   => '0',
            StepAddCount   => (others => '0'),
            CfgP           => core_cfg_p_s,
            CfgStepsPerRun => core_cfg_steps_s,
            CfgSeed        => core_cfg_seed_s,
            CfgRuns        => core_cfg_runs_s,
            CfgInit        => core_cfg_init_s,
            StepCount      => core_step_count_s,
            SpanningCount  => core_spanning_s,
            TotalOccupied  => core_total_s,
            SpanningOccupied => core_spanning_occ_s,
            Done           => core_done_s
        );

    process(Clk)
    begin
        if rising_edge(Clk) then
            -- reset logic: active low reset will return the state machine to IDLE and clear all control signals
            if Rst = '0' then
                state <= IDLE;
                tx_msg_s <= (others => '0');
                tx_start_s <= '0';
                core_cfg_p_s <= (others => '0');
                core_cfg_steps_s <= (others => '0');
                core_cfg_seed_s <= (others => '0');
                core_cfg_runs_s <= (others => '0');
                core_cfg_init_s <= '0';
                core_run_en_s <= '0';
            else
                tx_start_s <= '0';
                core_cfg_init_s <= '0';

                case state is
                    -- state IDLE: wait for a valid request message to be received over UART. 
                    -- When a valid message is received, extract the configuration parameters, initialize the core, and transition to WAIT_CLEAR.
                    when IDLE =>
                        core_run_en_s <= '0';
                        if req_valid_s = '1' then
                            core_cfg_p_s    <= req_msg_s(127 downto 96);            -- p value in UQ32 format   (bytes 12-15)
                            core_cfg_seed_s <= req_msg_s(95 downto 64);             -- seed value               (bytes 8-11)
                            core_cfg_steps_s <= unsigned(req_msg_s(63 downto 32));  -- steps per run            (bytes 4-7)
                            core_cfg_runs_s  <= req_msg_s(31 downto 0);             -- number of runs           (bytes 0-3)
                            core_cfg_init_s  <= '1';
                            state <= WAIT_CLEAR;
                        end if;

                    -- state WAIT_CLEAR: wait for the core to clear the done signal from any previous run. 
                    -- This ensures that we start a new run cleanly. Once the core is ready, transition to RUN_WAIT to start the simulation.
                    when WAIT_CLEAR =>
                        core_run_en_s <= '0';
                        if core_done_s = '0' then
                            state <= RUN_WAIT;
                        end if;

                    -- state RUN_WAIT: enable the core to start running the simulation. 
                    -- Wait for the core to assert done, indicating that the batch of runs is complete.
                    when RUN_WAIT =>
                        core_run_en_s <= '1';
                        if core_done_s = '1' then
                            core_run_en_s <= '0';
                            -- Prepare the response message by concatenating the results from the core: StepCount, SpanningCount, TotalOccupied, and SpanningOccupied.
                            tx_msg_s <= core_step_count_s & core_spanning_s & core_total_s & core_spanning_occ_s;
                            state <= TX_PULSE;
                        end if;

                    -- state TX_PULSE: pulse the tx_start signal to initiate transmission of the response message over UART.
                    when TX_PULSE =>
                        core_run_en_s <= '0';
                        if tx_busy_s = '0' then
                            tx_start_s <= '1';
                            state <= TX_WAIT_BUSY;
                        end if;

                    -- state TX_WAIT_BUSY: wait for the UART transmitter to assert busy, indicating that it has started transmitting the message.
                    -- Trasmission divided into two states to ensure that we properly detect the start and end of transmission without skipping.
                    when TX_WAIT_BUSY =>
                        core_run_en_s <= '0';
                        if tx_busy_s = '1' then
                            state <= TX_WAIT_DONE;
                        end if;

                    -- state TX_WAIT_DONE: wait for the UART transmitter to finish sending the message (busy goes low). Once done, transition back to IDLE to wait for the next request.
                    when TX_WAIT_DONE =>
                        core_run_en_s <= '0';
                        if tx_busy_s = '0' then
                            state <= IDLE;
                        end if;

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;
end Behavioral;
