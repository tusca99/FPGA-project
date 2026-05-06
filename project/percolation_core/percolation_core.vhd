library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

entity percolation_core is
    generic (
        N_ROWS_G : positive := 64
    );
    port (
        Clk            : in std_logic;
        Rst            : in std_logic; -- active low

        RunEn          : in std_logic;
        StepAddValid   : in std_logic;
        StepAddCount   : in std_logic_vector(31 downto 0);

        -- configuration
        CfgP           : in std_logic_vector(31 downto 0); -- threshold fixed point [0,1) as 32-bit UQ32
        CfgStepsPerRun : in unsigned(31 downto 0); -- rows / temporal steps per run
        CfgSeed        : in std_logic_vector(31 downto 0); -- seeds the RNG bank
        CfgRuns        : in std_logic_vector(31 downto 0);
        CfgInit        : in std_logic; -- reload config + reset state

        -- status/metrics
        StepCount      : out std_logic_vector(31 downto 0); -- how many runs it has done
        PendingSteps   : out std_logic_vector(31 downto 0);
        SpanningCount  : out std_logic_vector(31 downto 0);
        TotalOccupied  : out std_logic_vector(31 downto 0);
        RngBusy        : out std_logic;
        RngAllValid    : out std_logic;
        Done           : out std_logic;
        CoreStartPulse : out std_logic;
        FrontierRowAcceptPulse : out std_logic;
        FrontierRowProcessPulse : out std_logic;
        FrontierRowsSeen : out std_logic_vector(31 downto 0);
        FrontierDonePulse : out std_logic
    );
end percolation_core;

architecture Behavioral of percolation_core is
    signal grid_steps   : integer := N_ROWS_G;
    signal runs_target  : unsigned(31 downto 0) := (others => '0');

    signal run_enable   : std_logic := '0';
    signal pending      : unsigned(31 downto 0) := (others => '0');
    signal runs_done    : unsigned(31 downto 0) := (others => '0');
    signal spanning_cnt : unsigned(31 downto 0) := (others => '0');
    signal occupied_sum : unsigned(31 downto 0) := (others => '0');

    signal state        : integer range 0 to 1 := 0;
    signal rows_sent    : integer := 0;
    signal frontier_start_s   : std_logic := '0';
    signal hk_chunk_valid_s : std_logic := '0';
    signal hk_chunk_open_s  : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal frontier_busy_s    : std_logic := '0';
    signal frontier_done_s    : std_logic := '0';
    signal frontier_spanning_s : std_logic := '0';
    signal frontier_row_accept_pulse_s : std_logic := '0';
    signal frontier_row_process_pulse_s : std_logic := '0';
    signal frontier_rows_seen_s : std_logic_vector(31 downto 0) := (others => '0');
    signal frontier_done_pulse_s : std_logic := '0';
    signal run_occupied : unsigned(31 downto 0) := (others => '0');
    signal row_open_reg : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal row_chunk_cells_reg : integer range 0 to N_ROWS_G := 0;
    signal row_valid_reg : std_logic := '0';
    signal row_occupied_reg : unsigned(31 downto 0) := (others => '0');
    signal row_occupied_valid : std_logic := '0';
    signal rng_site_open_s   : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal rng_all_valid_s   : std_logic := '0';
    signal rng_busy_s        : std_logic := '1';
    signal rng_rst_s         : std_logic := '1';
    signal rng_master_key_s  : std_logic_vector(127 downto 0) := (others => '0');
    signal rng_run_tag_s     : std_logic_vector(31 downto 0) := (others => '0');
    signal rng_ready_seen    : std_logic := '0';
    signal core_start_pulse_s : std_logic := '0';
    signal send_valid_s       : std_logic := '0';
    signal send_data_s        : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');

    constant C_GOLDEN1 : unsigned(31 downto 0) := x"9E3779B9";
    constant C_GOLDEN2 : unsigned(31 downto 0) := x"243F6A88";

    function count_ones_prefix(
        flags : flag_array_t;
        limit : integer
    ) return integer is
        variable total : integer := 0;
    begin
        for index in 0 to N_ROWS_G - 1 loop
            if index < limit then
                if flags(index) = '1' then
                    total := total + 1;
                end if;
            end if;
        end loop;

        return total;
    end function;

    function flags_to_slv(flags : flag_array_t) return std_logic_vector is
        variable bits : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    begin
        for index in flags'range loop
            bits(index) := flags(index);
        end loop;

        return bits;
    end function;

    function seed_to_master_key(seed : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable seed_u : unsigned(31 downto 0) := unsigned(seed);
        variable key_u  : unsigned(127 downto 0) := (others => '0');
    begin
        key_u(31 downto 0)   := seed_u;
        key_u(63 downto 32)  := not seed_u;
        key_u(95 downto 64)  := seed_u xor C_GOLDEN1;
        key_u(127 downto 96) := seed_u + C_GOLDEN2;
        return std_logic_vector(key_u);
    end function;

begin
    hk_chunk_valid_s <= send_valid_s;
    hk_chunk_open_s <= send_data_s;

    rng_rst_s <= (not Rst) or CfgInit;
    rng_master_key_s <= seed_to_master_key(CfgSeed);
    rng_run_tag_s <= CfgSeed;

    rng_inst : entity work.rng_hybrid_64
        generic map (
            N_ROWS_G => N_ROWS_G
        )
        port map (
            clk        => Clk,
            rst        => rng_rst_s,
            master_key => rng_master_key_s,
            run_tag    => rng_run_tag_s,
            threshold  => CfgP,
            words_out  => open,
            valid_mask => open,
            site_open  => rng_site_open_s,
            all_valid  => rng_all_valid_s,
            busy       => rng_busy_s
        );

    frontier_inst : entity work.percolation_bfs_frontier
        generic map (
            N_ROWS_G => N_ROWS_G
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            CfgInit       => CfgInit,
            GridSteps     => CfgStepsPerRun,
            Start         => frontier_start_s,
            ChunkOpen     => hk_chunk_open_s,
            ChunkValid    => hk_chunk_valid_s,
            Busy          => frontier_busy_s,
            Done          => frontier_done_s,
            Spanning      => frontier_spanning_s,
            RowAcceptPulse => frontier_row_accept_pulse_s,
            RowProcessPulse => frontier_row_process_pulse_s,
            RowsSeen      => frontier_rows_seen_s,
            DonePulse     => frontier_done_pulse_s
        );

    StepCount     <= std_logic_vector(runs_done);
    PendingSteps  <= std_logic_vector(pending);
    SpanningCount <= std_logic_vector(spanning_cnt);
    TotalOccupied <= std_logic_vector(occupied_sum);
    RngBusy       <= rng_busy_s;
    RngAllValid   <= rng_all_valid_s;
    Done          <= '1' when (runs_target /= 0) and (runs_done >= runs_target) else '0';
    CoreStartPulse <= core_start_pulse_s;
    FrontierRowAcceptPulse <= frontier_row_accept_pulse_s;
    FrontierRowProcessPulse <= frontier_row_process_pulse_s;
    FrontierRowsSeen <= frontier_rows_seen_s;
    FrontierDonePulse <= frontier_done_pulse_s;

    process(Clk)
        variable cfg_steps_i     : integer;
        variable new_runs_done   : unsigned(31 downto 0);
        variable chunk_occupied  : integer;
        variable rows_sent_v     : integer;
        variable send_valid_v    : std_logic;
        variable send_data_v     : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_steps        <= N_ROWS_G;
                runs_target       <= (others => '0');
                run_enable        <= '0';
                pending           <= (others => '0');
                runs_done         <= (others => '0');
                spanning_cnt      <= (others => '0');
                occupied_sum      <= (others => '0');
                state             <= 0;
                rows_sent         <= 0;
                run_occupied      <= (others => '0');
                frontier_start_s  <= '0';
                send_valid_s      <= '0';
                send_data_s       <= (others => '0');
                row_open_reg      <= (others => '0');
                row_chunk_cells_reg <= 0;
                row_valid_reg     <= '0';
                row_occupied_reg  <= (others => '0');
                row_occupied_valid <= '0';
                rng_ready_seen    <= '0';
                core_start_pulse_s <= '0';
            else
                core_start_pulse_s <= '0';
                if CfgInit = '1' then
                    cfg_steps_i := to_integer(CfgStepsPerRun);
                    if cfg_steps_i < 1 then
                        cfg_steps_i := 1;
                    end if;

                    grid_steps        <= cfg_steps_i;
                    runs_target       <= unsigned(CfgRuns);
                    run_enable        <= '0';
                    pending           <= (others => '0');
                    runs_done         <= (others => '0');
                    spanning_cnt      <= (others => '0');
                    occupied_sum      <= (others => '0');
                    state             <= 0;
                    rows_sent         <= 0;
                    run_occupied      <= (others => '0');
                    frontier_start_s  <= '0';
                    send_valid_s      <= '0';
                    send_data_s       <= (others => '0');
                    row_open_reg      <= (others => '0');
                    row_chunk_cells_reg <= 0;
                    row_valid_reg     <= '0';
                    row_occupied_reg  <= (others => '0');
                    row_occupied_valid <= '0';
                    rng_ready_seen    <= '0';
                    core_start_pulse_s <= '0';
                end if;

                if RunEn = '1' then
                    run_enable <= '1';
                else
                    run_enable <= '0';
                end if;

                if StepAddValid = '1' then
                    pending <= pending + unsigned(StepAddCount);
                end if;

                frontier_start_s <= '0';

                if (CfgInit = '0') and (rng_ready_seen = '0') and
                   (rng_busy_s = '0') and (rng_all_valid_s = '1') then
                    rng_ready_seen <= '1';
                    report "percolation_core RNG ready" severity note;
                end if;

                if CfgInit = '0' then
                    if row_occupied_valid = '1' then
                        run_occupied <= run_occupied + row_occupied_reg;
                        row_occupied_valid <= '0';
                    end if;

                    if row_valid_reg = '1' then
                        chunk_occupied := count_ones_prefix(row_open_reg, row_chunk_cells_reg);
                        row_occupied_reg <= to_unsigned(chunk_occupied, 32);
                        row_occupied_valid <= '1';
                        row_valid_reg <= '0';
                    end if;
                end if;

                case state is
                    when 0 =>
                        if (rng_busy_s = '0') and (rng_all_valid_s = '1') and
                           ((run_enable = '1') or (pending /= 0)) and
                           ((runs_target = 0) or (runs_done < runs_target)) then
                            rows_sent <= 0;
                            run_occupied <= (others => '0');
                            frontier_start_s <= '1';
                            send_valid_s <= '0';
                            send_data_s <= (others => '0');
                            row_open_reg      <= (others => '0');
                            row_chunk_cells_reg <= 0;
                            row_valid_reg     <= '0';
                            row_occupied_reg  <= (others => '0');
                            row_occupied_valid <= '0';
                            state        <= 1;
                            core_start_pulse_s <= '1';
                            report "percolation_core start: runs_target=" &
                                   integer'image(to_integer(runs_target)) &
                                   " pending=" & integer'image(to_integer(pending))
                                severity note;
                        end if;

                    when 1 =>
                        rows_sent_v := rows_sent;
                        send_valid_v := send_valid_s;
                        send_data_v := send_data_s;

                        if frontier_done_s = '1' then
                            new_runs_done := runs_done + 1;

                            runs_done <= new_runs_done;

                            if frontier_spanning_s = '1' then
                                spanning_cnt <= spanning_cnt + 1;
                            end if;

                            occupied_sum <= occupied_sum + run_occupied;

                                          report "percolation_core run complete: grid_width=" & integer'image(N_ROWS_G) &
                                              " grid_steps=" & integer'image(grid_steps) &
                                   " run_occupied=" & integer'image(to_integer(run_occupied)) &
                                   " runs_done=" & integer'image(to_integer(new_runs_done)) &
                                              " frontier_busy=" & std_logic'image(frontier_busy_s) &
                                              " spanning=" & std_logic'image(frontier_spanning_s)
                                severity note;

                            if (pending /= 0) then
                                pending <= pending - 1;
                            end if;

                            state <= 0;
                        end if;

                        if (frontier_done_s = '0') then
                            if (send_valid_v = '1') and (frontier_busy_s = '0') then
                                rows_sent_v := rows_sent_v + 1;
                                send_valid_v := '0';
                                row_open_reg <= send_data_v;
                                row_chunk_cells_reg <= N_ROWS_G;
                                row_valid_reg <= '1';
                            end if;

                            if (send_valid_v = '0') and (rows_sent_v < grid_steps) then
                                send_data_v := flags_to_slv(rng_site_open_s);
                                send_valid_v := '1';
                            end if;
                        end if;

                        rows_sent <= rows_sent_v;
                        send_valid_s <= send_valid_v;
                        send_data_s <= send_data_v;

                end case;
            end if;
        end if;
    end process;
end Behavioral;
