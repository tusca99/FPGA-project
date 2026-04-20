library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

entity percolation_core is
    port (
        Clk            : in std_logic;
        Rst            : in std_logic; -- active low

        RunEn          : in std_logic;
        StepAddValid   : in std_logic;
        StepAddCount   : in std_logic_vector(31 downto 0);

        -- configuration
        CfgP           : in std_logic_vector(31 downto 0); -- threshold fixed point [0,1) as 32-bit UQ32
        CfgGridSize    : in std_logic_vector(15 downto 0); -- side length (max 128)
        CfgSeed        : in std_logic_vector(31 downto 0); -- seeds the RNG bank
        CfgRuns        : in std_logic_vector(31 downto 0);
        CfgInit        : in std_logic; -- reload config + reset state

        -- status/metrics
        StepCount      : out std_logic_vector(31 downto 0); -- how many runs it has done
        PendingSteps   : out std_logic_vector(31 downto 0);
        SpanningCount  : out std_logic_vector(31 downto 0);
        TotalOccupied  : out std_logic_vector(31 downto 0);
        ConnStepCount  : out std_logic_vector(31 downto 0);
        Done           : out std_logic
    );
end percolation_core;

architecture Behavioral of percolation_core is
    constant MAX_GRID   : integer := 128;
    constant MAX_CELLS  : integer := MAX_GRID * MAX_GRID;

    signal grid_cells   : integer range 1 to MAX_CELLS := 64*64;
    signal runs_target  : unsigned(31 downto 0) := (others => '0');

    signal run_enable   : std_logic := '0';
    signal pending      : unsigned(31 downto 0) := (others => '0');
    signal runs_done    : unsigned(31 downto 0) := (others => '0');
    signal spanning_cnt : unsigned(31 downto 0) := (others => '0');
    signal occupied_sum : unsigned(31 downto 0) := (others => '0');
    signal conn_steps_total : unsigned(31 downto 0) := (others => '0');

    signal state        : integer range 0 to 1 := 0;
    signal stream_index : integer range 0 to MAX_CELLS := 0;
    signal hk_start_s   : std_logic := '0';
    signal hk_chunk_valid_s : std_logic := '0';
    signal hk_chunk_open_s  : std_logic_vector(N_ROWS - 1 downto 0) := (others => '0');
    signal hk_busy_s    : std_logic := '0';
    signal hk_done_s    : std_logic := '0';
    signal hk_spanning_s : std_logic := '0';
    signal hk_conn_steps_s : std_logic_vector(31 downto 0) := (others => '0');
    signal p_spanning   : std_logic := '0';
    signal run_occupied : unsigned(31 downto 0) := (others => '0');

    signal rng_words_s       : word_array_t := (others => (others => '0'));
    signal rng_valid_mask_s  : flag_array_t := (others => '0');
    signal rng_site_open_s   : flag_array_t := (others => '0');
    signal rng_all_valid_s   : std_logic := '0';
    signal rng_busy_s        : std_logic := '1';
    signal rng_arm_s         : std_logic := '0';
    signal rng_rst_s         : std_logic := '1';
    signal rng_master_key_s  : std_logic_vector(127 downto 0) := (others => '0');
    signal rng_run_tag_s     : std_logic_vector(31 downto 0) := (others => '0');

    constant C_GOLDEN1 : unsigned(31 downto 0) := x"9E3779B9";
    constant C_GOLDEN2 : unsigned(31 downto 0) := x"243F6A88";

    function min_int(a, b : integer) return integer is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function;

    function count_ones_prefix(
        flags : flag_array_t;
        limit : integer
    ) return integer is
        variable total : integer := 0;
    begin
        for index in 0 to N_ROWS - 1 loop
            if index < limit then
                if flags(index) = '1' then
                    total := total + 1;
                end if;
            end if;
        end loop;

        return total;
    end function;

    function flags_to_slv(flags : flag_array_t) return std_logic_vector is
        variable bits : std_logic_vector(N_ROWS - 1 downto 0) := (others => '0');
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
    rng_rst_s <= (not Rst) or CfgInit;
    rng_master_key_s <= seed_to_master_key(CfgSeed);
    rng_run_tag_s <= CfgSeed;

    rng_inst : entity work.rng_hybrid_64
        port map (
            clk        => Clk,
            rst        => rng_rst_s,
            master_key => rng_master_key_s,
            run_tag    => rng_run_tag_s,
            threshold  => CfgP,
            words_out  => rng_words_s,
            valid_mask => rng_valid_mask_s,
            site_open  => rng_site_open_s,
            all_valid  => rng_all_valid_s,
            busy       => rng_busy_s
        );

    bfs_inst : entity work.percolation_bfs_frontier
        port map (
            Clk           => Clk,
            Rst           => Rst,
            CfgInit       => CfgInit,
            GridSize      => CfgGridSize,
            Start         => hk_start_s,
            ChunkOpen     => hk_chunk_open_s,
            ChunkValid    => hk_chunk_valid_s,
            Busy          => hk_busy_s,
            Done          => hk_done_s,
            Spanning      => hk_spanning_s,
            ConnStepCount => hk_conn_steps_s
        );

    StepCount     <= std_logic_vector(runs_done);
    PendingSteps  <= std_logic_vector(pending);
    SpanningCount <= std_logic_vector(spanning_cnt);
    TotalOccupied <= std_logic_vector(occupied_sum);
    ConnStepCount <= std_logic_vector(conn_steps_total);
    Done          <= '1' when (runs_target /= 0) and (runs_done >= runs_target) else '0';

    process(Clk)
        variable cfg_size_i      : integer;
        variable new_runs_done   : unsigned(31 downto 0);
        variable new_conn_total  : unsigned(31 downto 0);
        variable chunk_cells     : integer;
        variable chunk_occupied  : integer;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_cells        <= 64 * 64;
                runs_target       <= (others => '0');
                run_enable        <= '0';
                pending           <= (others => '0');
                runs_done         <= (others => '0');
                spanning_cnt      <= (others => '0');
                occupied_sum      <= (others => '0');
                conn_steps_total   <= (others => '0');
                state             <= 0;
                stream_index      <= 0;
                run_occupied      <= (others => '0');
                rng_arm_s         <= '0';
                hk_start_s        <= '0';
                hk_chunk_valid_s  <= '0';
                hk_chunk_open_s   <= (others => '0');
            else
                if CfgInit = '1' then
                    cfg_size_i := min_int(to_integer(unsigned(CfgGridSize)), MAX_GRID);
                    if cfg_size_i < 1 then
                        cfg_size_i := 1;
                    end if;

                    grid_cells        <= cfg_size_i * cfg_size_i;
                    runs_target       <= unsigned(CfgRuns);
                    run_enable        <= '0';
                    pending           <= (others => '0');
                    runs_done         <= (others => '0');
                    spanning_cnt      <= (others => '0');
                    occupied_sum      <= (others => '0');
                    conn_steps_total   <= (others => '0');
                    state             <= 0;
                    stream_index      <= 0;
                    run_occupied      <= (others => '0');
                    rng_arm_s         <= '0';
                    hk_start_s        <= '0';
                    hk_chunk_valid_s  <= '0';
                    hk_chunk_open_s   <= (others => '0');
                end if;

                if (CfgInit = '0') and (rng_busy_s = '1') then
                    rng_arm_s <= '1';
                end if;

                if RunEn = '1' then
                    run_enable <= '1';
                else
                    run_enable <= '0';
                end if;

                if StepAddValid = '1' then
                    pending <= pending + unsigned(StepAddCount);
                end if;

                hk_start_s       <= '0';
                hk_chunk_valid_s <= '0';

                case state is
                    when 0 =>
                        if (rng_arm_s = '1') and (rng_busy_s = '0') and (rng_all_valid_s = '1') and
                           ((run_enable = '1') or (pending /= 0)) and
                           ((runs_target = 0) or (runs_done < runs_target)) then
                            stream_index <= 0;
                            run_occupied <= (others => '0');
                            hk_start_s   <= '1';
                            state        <= 1;
                        end if;

                    when 1 =>
                        if hk_done_s = '1' then
                            new_runs_done := runs_done + 1;
                            new_conn_total := conn_steps_total + unsigned(hk_conn_steps_s);

                            runs_done <= new_runs_done;
                            conn_steps_total <= new_conn_total;

                            if hk_spanning_s = '1' then
                                spanning_cnt <= spanning_cnt + 1;
                            end if;

                            occupied_sum <= occupied_sum + run_occupied;

                                report "percolation_core run complete: grid_size=" & integer'image(min_int(to_integer(unsigned(CfgGridSize)), MAX_GRID)) &
                                   " run_occupied=" & integer'image(to_integer(run_occupied)) &
                                   " conn_steps=" & integer'image(to_integer(unsigned(hk_conn_steps_s))) &
                                   " conn_total=" & integer'image(to_integer(new_conn_total)) &
                                   " runs_done=" & integer'image(to_integer(new_runs_done)) &
                                   " hk_busy=" & std_logic'image(hk_busy_s) &
                                   " spanning=" & std_logic'image(hk_spanning_s)
                                severity note;

                            if (pending /= 0) then
                                pending <= pending - 1;
                            end if;

                            if (((run_enable = '1') or (pending /= 0)) and
                                ((runs_target = 0) or (new_runs_done < runs_target))) then
                                stream_index <= 0;
                                run_occupied <= (others => '0');
                                hk_start_s <= '1';
                                state <= 1;
                            else
                                state <= 0;
                            end if;
                        elsif stream_index < grid_cells then
                            chunk_cells := min_int(grid_cells - stream_index, N_ROWS);
                            hk_chunk_open_s  <= flags_to_slv(rng_site_open_s);
                            hk_chunk_valid_s <= '1';
                            chunk_occupied := count_ones_prefix(rng_site_open_s, chunk_cells);
                            run_occupied <= run_occupied + to_unsigned(chunk_occupied, 32);
                            stream_index <= stream_index + chunk_cells;
                        end if;

                    when others =>
                        state <= 0;
                end case;
            end if;
        end if;
    end process;
end Behavioral;
