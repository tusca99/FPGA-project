library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_led_top is
    generic (
        N_ROWS_G : positive := 64
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic; -- active low
        btn_init_i : in std_logic := '1';
        btn_run_i  : in std_logic := '1';
        led_rgb_o  : out std_logic_vector(2 downto 0)
    );
end percolation_led_top;

architecture Behavioral of percolation_led_top is
    type state_t is (IDLE, RUNNING, PASS, FAIL);

    constant CFG_P_C           : std_logic_vector(31 downto 0) := x"9999999A";
    constant CFG_STEPS_C       : std_logic_vector(15 downto 0) := x"0040";
    constant CFG_SEED_C        : std_logic_vector(31 downto 0) := x"12345678";
    constant CFG_RUNS_C        : std_logic_vector(31 downto 0) := x"00000F10";

    signal state : state_t := IDLE;
    signal boot_pending_s : std_logic := '1';

    signal btn_init_sync1 : std_logic := '1';
    signal btn_init_sync2 : std_logic := '1';
    signal btn_init_prev  : std_logic := '1';
    signal btn_run_sync1  : std_logic := '1';
    signal btn_run_sync2  : std_logic := '1';
    signal btn_run_prev   : std_logic := '1';

    signal start_pulse_s : std_logic := '0';

    signal core_cfg_init_s   : std_logic := '0';
    signal core_run_en_s     : std_logic := '0';
    signal core_step_count_s : std_logic_vector(31 downto 0) := (others => '0');
    signal core_spanning_s   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_total_s      : std_logic_vector(31 downto 0) := (others => '0');
    signal core_done_s       : std_logic := '0';
    signal core_rng_busy_s   : std_logic := '1';
    signal core_rng_all_valid_s : std_logic := '0';

begin
    start_pulse_s <= '1' when
        ((btn_init_prev = '1') and (btn_init_sync2 = '0')) or
        ((btn_run_prev = '1') and (btn_run_sync2 = '0'))
        else '0';

    led_rgb_o <= "010" when state = PASS else
                 "100" when state = FAIL else
                 "110" when state = RUNNING else
                 "001";

    core_inst : entity work.percolation_core_top
        generic map (
            N_ROWS_G => N_ROWS_G
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            RunEn         => core_run_en_s,
            StepAddValid  => '0',
            StepAddCount  => (others => '0'),
            CfgP          => CFG_P_C,
            CfgStepsPerRun => CFG_STEPS_C,
            CfgSeed       => CFG_SEED_C,
            CfgRuns       => CFG_RUNS_C,
            CfgInit       => core_cfg_init_s,
            StepCount     => core_step_count_s,
            PendingSteps  => open,
            SpanningCount => core_spanning_s,
            TotalOccupied => core_total_s,
            RngBusy       => core_rng_busy_s,
            RngAllValid   => core_rng_all_valid_s,
            Done          => core_done_s
        );

    process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                btn_init_sync1 <= '1';
                btn_init_sync2 <= '1';
                btn_init_prev  <= '1';
                btn_run_sync1  <= '1';
                btn_run_sync2  <= '1';
                btn_run_prev   <= '1';
            else
                btn_init_prev  <= btn_init_sync2;
                btn_run_prev   <= btn_run_sync2;
                btn_init_sync1 <= btn_init_i;
                btn_init_sync2 <= btn_init_sync1;
                btn_run_sync1  <= btn_run_i;
                btn_run_sync2  <= btn_run_sync1;
            end if;
        end if;
    end process;

    process(Clk)
        variable step_count_u : unsigned(31 downto 0);
        variable spanning_u   : unsigned(31 downto 0);
        variable total_u      : unsigned(31 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state <= IDLE;
                boot_pending_s <= '1';
                core_cfg_init_s <= '0';
                core_run_en_s <= '0';
            else
                core_cfg_init_s <= '0';

                case state is
                    when IDLE =>
                        core_run_en_s <= '0';
                        if (boot_pending_s = '1') or (start_pulse_s = '1') then
                            core_cfg_init_s <= '1';
                            core_run_en_s <= '1';
                            boot_pending_s <= '0';
                            state <= RUNNING;
                        end if;

                    when RUNNING =>
                        core_run_en_s <= '1';
                        if core_done_s = '1' then
                            step_count_u := unsigned(core_step_count_s);
                            spanning_u := unsigned(core_spanning_s);
                            total_u := unsigned(core_total_s);

                            if (step_count_u = unsigned(CFG_RUNS_C)) and
                               (spanning_u /= 0) and
                               (total_u /= 0) then
                                state <= PASS;
                            else
                                state <= FAIL;
                            end if;
                        end if;

                    when PASS =>
                        core_run_en_s <= '0';
                        if start_pulse_s = '1' then
                            core_cfg_init_s <= '1';
                            core_run_en_s <= '1';
                            state <= RUNNING;
                        end if;

                    when FAIL =>
                        core_run_en_s <= '0';
                        if start_pulse_s = '1' then
                            core_cfg_init_s <= '1';
                            core_run_en_s <= '1';
                            state <= RUNNING;
                        end if;
                end case;
            end if;
        end if;
    end process;

end Behavioral;