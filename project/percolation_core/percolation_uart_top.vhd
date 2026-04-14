library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_uart_top is
    generic (
        CLK_FREQ  : integer := 100_000_000;
        BAUD_RATE : integer := 115200;
        REQ_BYTES : positive := 12;
        RSP_BYTES : positive := 12
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic; -- active low
        uart_rx_i : in  std_logic;
        uart_tx_o : out std_logic;
        btn_init_i : in std_logic := '1'; -- button for manual init (active low)
        btn_run_i  : in std_logic := '1'  -- button for manual run (active low)
    );
end percolation_uart_top;

architecture Behavioral of percolation_uart_top is
    type state_t is (IDLE, SEND_WAIT);
    signal state : state_t := IDLE;

    signal baud_tick_s : std_logic := '0';
    signal half_tick_s : std_logic := '0';

    signal rx_msg_s        : std_logic_vector(REQ_BYTES*8-1 downto 0) := (others => '0');
    signal rx_valid_s      : std_logic := '0';
    signal rx_busy_s       : std_logic := '0';

    signal tx_msg_s        : std_logic_vector(RSP_BYTES*8-1 downto 0) := (others => '0');
    signal tx_start_s      : std_logic := '0';
    signal tx_busy_s       : std_logic := '0';

    -- Button synchronizers (double-flip-flop)
    signal btn_init_sync1 : std_logic := '1';
    signal btn_init_sync2 : std_logic := '1';
    signal btn_run_sync1  : std_logic := '1';
    signal btn_run_sync2  : std_logic := '1';

    signal core_cfg_p_s        : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_grid_s     : std_logic_vector(15 downto 0) := (others => '0');
    signal core_cfg_seed_s     : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_runs_s     : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_init_s     : std_logic := '0';
    signal core_run_en_s       : std_logic := '0';
    signal core_step_count_s   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_spanning_s     : std_logic_vector(31 downto 0) := (others => '0');
    signal core_total_s        : std_logic_vector(31 downto 0) := (others => '0');

    function word_from_msg(msg : std_logic_vector; word_index : natural) return std_logic_vector is
        variable word_hi : integer;
        variable word_lo : integer;
        variable result  : std_logic_vector(31 downto 0);
    begin
        word_hi := msg'left - integer(word_index) * 32;
        word_lo := word_hi - 31;
        result := msg(word_hi downto word_lo);
        return result;
    end function;

begin
    baud_inst : entity work.baud_gen
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s,
            half_tick => half_tick_s
        );

    rx_inst : entity work.uart_msg_rx
        generic map (
            N_BYTES => REQ_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s,
            half_tick => half_tick_s,
            uart_rx_i => uart_rx_i,
            msg_data  => rx_msg_s,
            msg_valid => rx_valid_s,
            busy      => rx_busy_s
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
        port map (
            Clk           => Clk,
            Rst           => Rst,
            RunEn         => core_run_en_s,
            StepAddValid  => '0',  -- no step control in this interface
            StepAddCount  => (others => '0'),
            CfgP          => core_cfg_p_s,
            CfgGridSize   => core_cfg_grid_s,
            CfgSeed       => core_cfg_seed_s,
            CfgRuns       => core_cfg_runs_s,
            CfgInit       => core_cfg_init_s,
            StepCount     => core_step_count_s,
            PendingSteps  => open,  -- not used in response
            SpanningCount => core_spanning_s,
            TotalOccupied => core_total_s,
            MeanOccupied  => open   -- not used in response
        );

    -- Button synchronization (double-flip-flop for metastability)
    process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                btn_init_sync1 <= '1';
                btn_init_sync2 <= '1';
                btn_run_sync1  <= '1';
                btn_run_sync2  <= '1';
            else
                btn_init_sync1 <= btn_init_i;
                btn_init_sync2 <= btn_init_sync1;
                btn_run_sync1  <= btn_run_i;
                btn_run_sync2  <= btn_run_sync1;
            end if;
        end if;
    end process;

    process(Clk)
        variable grid_runs : std_logic_vector(31 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state <= IDLE;
                tx_msg_s <= (others => '0');
                tx_start_s <= '0';
                core_cfg_p_s <= (others => '0');
                core_cfg_grid_s <= (others => '0');
                core_cfg_seed_s <= (others => '0');
                core_cfg_runs_s <= (others => '0');
                core_cfg_init_s <= '0';
                core_run_en_s <= '0';
            else
                tx_start_s <= '0';
                core_cfg_init_s <= '0';
                core_run_en_s <= '0';

                case state is
                    when IDLE =>
                        -- UART message: Word0=CfgP, Word1=CfgSeed, Word2=GridSize[7:0] | CfgRuns[23:0]
                        if rx_valid_s = '1' then
                            core_cfg_p_s    <= word_from_msg(rx_msg_s, 0);
                            core_cfg_seed_s <= word_from_msg(rx_msg_s, 1);
                            
                            grid_runs := word_from_msg(rx_msg_s, 2);
                            core_cfg_grid_s <= std_logic_vector(resize(unsigned(grid_runs(31 downto 24)), 16));
                            core_cfg_runs_s <= resize(unsigned(grid_runs(23 downto 0)), 32);
                            
                            -- Auto-init and run on UART message
                            core_cfg_init_s <= '1';
                            core_run_en_s   <= '1';
                            
                            -- Response: Word0=StepCount, Word1=SpanningCount, Word2=TotalOccupied
                            tx_msg_s <= core_step_count_s & core_spanning_s & core_total_s;
                            state <= SEND_WAIT;
                        end if;

                        -- Button override (debug): check for button presses
                        if btn_init_sync2 = '0' then
                            core_cfg_init_s <= '1';
                        end if;
                        if btn_run_sync2 = '0' then
                            core_run_en_s <= '1';
                        end if;

                    when SEND_WAIT =>
                        if tx_busy_s = '0' then
                            tx_start_s <= '1';
                            state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

end Behavioral;