library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_uart_top is
    generic (
        CLK_FREQ  : integer := 100_000_000;
        BAUD_RATE : integer := 115200;
        N_ROWS_G  : positive := 1024;
        REQ_BYTES : positive := 16;
        RSP_BYTES : positive := 16
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic; -- active low
        uart_rx_i : in  std_logic;
        uart_tx_o : out std_logic;
        led_rgb_o  : out std_logic_vector(2 downto 0)
    );
end percolation_uart_top;

architecture Behavioral of percolation_uart_top is
    constant REQ_BITS : natural := REQ_BYTES * 8;
    constant RSP_BITS : natural := RSP_BYTES * 8;

    type state_t is (IDLE, WAIT_CLEAR, RUN_WAIT, TX_PULSE, TX_WAIT_BUSY, TX_WAIT_DONE);
    signal state : state_t := IDLE;

    signal baud_tick_s : std_logic := '0';

    signal req_msg_s   : std_logic_vector(REQ_BITS-1 downto 0) := (others => '0');
    signal req_valid_s : std_logic := '0';

    signal tx_msg_s   : std_logic_vector(RSP_BITS-1 downto 0) := (others => '0');
    signal tx_start_s : std_logic := '0';
    signal tx_busy_s  : std_logic := '0';

    signal core_cfg_p_s      : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_steps_s  : unsigned(31 downto 0) := (others => '0');
    signal core_cfg_seed_s   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_runs_s   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_init_s   : std_logic := '0';
    signal core_run_en_s     : std_logic := '0';
    signal core_step_count_s : std_logic_vector(31 downto 0) := (others => '0');
    signal core_spanning_s   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_total_s      : std_logic_vector(31 downto 0) := (others => '0');
    signal core_done_s       : std_logic := '0';
begin
    led_rgb_o <= "001" when state = IDLE else
                 "110";

    baud_inst : entity work.baud_gen
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s,
            half_tick => open
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
            PendingSteps   => open,
            SpanningCount  => core_spanning_s,
            TotalOccupied  => core_total_s,
            RngBusy        => open,
            RngAllValid    => open,
            Done           => core_done_s
        );

    process(Clk)
    begin
        if rising_edge(Clk) then
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
                    when IDLE =>
                        core_run_en_s <= '0';
                        if req_valid_s = '1' then
                            core_cfg_p_s    <= req_msg_s(127 downto 96);
                            core_cfg_seed_s <= req_msg_s(95 downto 64);
                            core_cfg_steps_s <= unsigned(req_msg_s(63 downto 32));
                            core_cfg_runs_s  <= req_msg_s(31 downto 0);
                            core_cfg_init_s  <= '1';
                            state <= WAIT_CLEAR;
                        end if;

                    when WAIT_CLEAR =>
                        core_run_en_s <= '0';
                        if core_done_s = '0' then
                            state <= RUN_WAIT;
                        end if;

                    when RUN_WAIT =>
                        core_run_en_s <= '1';
                        if core_done_s = '1' then
                            core_run_en_s <= '0';
                            tx_msg_s <= core_step_count_s & core_spanning_s & core_total_s & x"00000000";
                            state <= TX_PULSE;
                        end if;

                    when TX_PULSE =>
                        core_run_en_s <= '0';
                        if tx_busy_s = '0' then
                            tx_start_s <= '1';
                            state <= TX_WAIT_BUSY;
                        end if;

                    when TX_WAIT_BUSY =>
                        core_run_en_s <= '0';
                        if tx_busy_s = '1' then
                            state <= TX_WAIT_DONE;
                        end if;

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
