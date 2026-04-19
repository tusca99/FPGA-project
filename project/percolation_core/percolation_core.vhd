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

    signal grid_mem     : std_logic_vector(MAX_CELLS-1 downto 0) := (others => '0');

    signal grid_size    : integer range 1 to MAX_GRID := 64;
    signal grid_cells   : integer range 1 to MAX_CELLS := 64*64;
    signal runs_target  : unsigned(31 downto 0) := (others => '0');

    signal run_enable   : std_logic := '0';
    signal pending      : unsigned(31 downto 0) := (others => '0');
    signal runs_done    : unsigned(31 downto 0) := (others => '0');
    signal spanning_cnt : unsigned(31 downto 0) := (others => '0');
    signal occupied_sum : unsigned(31 downto 0) := (others => '0');
    signal conn_steps_total : unsigned(31 downto 0) := (others => '0');

    signal state        : integer range 0 to 5 := 0;
    signal fill_index   : integer range 0 to MAX_CELLS := 0;
    signal row_feed_index : integer range 0 to MAX_GRID := 0;
    signal hk_start_s   : std_logic := '0';
    signal hk_row_valid_s : std_logic := '0';
    signal hk_row_open_s  : std_logic_vector(MAX_GRID - 1 downto 0) := (others => '0');
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

    function extract_row(
        grid      : std_logic_vector(MAX_CELLS - 1 downto 0);
        row_index : integer;
        row_size  : integer
    ) return std_logic_vector is
        variable row_bits : std_logic_vector(MAX_GRID - 1 downto 0) := (others => '0');
        variable base_idx  : integer;
    begin
        base_idx := row_index * row_size;

        for col in 0 to MAX_GRID - 1 loop
            if col < row_size then
                row_bits(col) := grid(base_idx + col);
            end if;
        end loop;

        return row_bits;
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

    hk_inst : entity work.percolation_hk_row_wise
        port map (
            Clk           => Clk,
            Rst           => Rst,
            CfgInit       => CfgInit,
            GridSize      => CfgGridSize,
            Start         => hk_start_s,
            RowOpen       => hk_row_open_s,
            RowValid      => hk_row_valid_s,
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
        variable cfg_size_i    : integer;
        variable new_runs_done  : unsigned(31 downto 0);
        variable new_conn_total : unsigned(31 downto 0);
        variable chunk_cols     : integer;
        variable chunk_occupied : integer;
        variable bit_index      : integer;
        variable row_bits_v     : std_logic_vector(MAX_GRID - 1 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_size         <= 64;
                grid_cells        <= 64 * 64;
                runs_target       <= (others => '0');
                run_enable        <= '0';
                pending           <= (others => '0');
                runs_done         <= (others => '0');
                spanning_cnt      <= (others => '0');
                occupied_sum      <= (others => '0');
                conn_steps_total  <= (others => '0');
                state             <= 0;
                fill_index        <= 0;
                row_feed_index    <= 0;
                run_occupied      <= (others => '0');
                rng_arm_s         <= '0';
                hk_start_s        <= '0';
                hk_row_valid_s    <= '0';
                hk_row_open_s     <= (others => '0');
                grid_mem          <= (others => '0');
            else
                if CfgInit = '1' then
                    cfg_size_i := min_int(to_integer(unsigned(CfgGridSize)), MAX_GRID);
                    if cfg_size_i < 1 then
                        cfg_size_i := 1;
                    end if;

                    grid_size         <= cfg_size_i;
                    grid_cells        <= cfg_size_i * cfg_size_i;
                    runs_target       <= unsigned(CfgRuns);
                    run_enable        <= '0';
                    pending           <= (others => '0');
                    runs_done         <= (others => '0');
                    spanning_cnt      <= (others => '0');
                    occupied_sum      <= (others => '0');
                    conn_steps_total  <= (others => '0');
                    state             <= 0;
                    fill_index        <= 0;
                    row_feed_index    <= 0;
                    run_occupied      <= (others => '0');
                    rng_arm_s         <= '0';
                    hk_start_s        <= '0';
                    hk_row_valid_s    <= '0';
                    hk_row_open_s     <= (others => '0');
                    grid_mem          <= (others => '0');
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

                hk_start_s <= '0';
                hk_row_valid_s <= '0';

                case state is
                    when 0 => -- IDLE
                        if (rng_arm_s = '1') and (rng_busy_s = '0') and (rng_all_valid_s = '1') and
                           ((run_enable = '1') or (pending /= 0)) and
                           ((runs_target = 0) or (runs_done < runs_target)) then
                            fill_index    <= 0;
                            run_occupied  <= (others => '0');
                            row_feed_index <= 0;
                            state         <= 1;
                        end if;

                    when 1 => -- GENERATE GRID IN LINEAR 64-CELL BLOCKS
                        if (rng_busy_s = '0') and (rng_all_valid_s = '1') then
                            chunk_cols := min_int(grid_cells - fill_index, N_ROWS);
                            chunk_occupied := 0;

                            for bit_index in 0 to N_ROWS - 1 loop
                                if bit_index < chunk_cols then
                                    grid_mem(fill_index + bit_index) <= rng_site_open_s(bit_index);
                                    if rng_site_open_s(bit_index) = '1' then
                                        chunk_occupied := chunk_occupied + 1;
                                    end if;
                                end if;
                            end loop;

                            if fill_index = 0 then
                                report "percolation_core first chunk: busy=" & std_logic'image(rng_busy_s) &
                                       " all_valid=" & std_logic'image(rng_all_valid_s) &
                                       " valid0=" & std_logic'image(rng_valid_mask_s(0)) &
                                       " open0=" & std_logic'image(rng_site_open_s(0)) &
                                       " open1=" & std_logic'image(rng_site_open_s(1)) &
                                       " open2=" & std_logic'image(rng_site_open_s(2)) &
                                       " open3=" & std_logic'image(rng_site_open_s(3)) &
                                       " open4=" & std_logic'image(rng_site_open_s(4)) &
                                       " open5=" & std_logic'image(rng_site_open_s(5)) &
                                       " open6=" & std_logic'image(rng_site_open_s(6)) &
                                       " open7=" & std_logic'image(rng_site_open_s(7)) &
                                       " chunk_cells=" & integer'image(chunk_cols) &
                                       " chunk_occupied=" & integer'image(chunk_occupied)
                                    severity note;
                            end if;

                            run_occupied <= run_occupied + to_unsigned(chunk_occupied, 32);

                            if fill_index + chunk_cols >= grid_cells then
                                row_feed_index <= 0;
                                hk_start_s <= '1';
                                state <= 2;
                            else
                                fill_index <= fill_index + chunk_cols;
                            end if;
                        end if;

                    when 2 => -- PULSE HK START
                        state <= 3;

                    when 3 => -- PRESENT ROW TO HK
                        if (hk_busy_s = '0') and (hk_done_s = '0') then
                            row_bits_v := extract_row(grid_mem, row_feed_index, grid_size);
                            hk_row_open_s <= row_bits_v;
                            hk_row_valid_s <= '1';
                            state <= 4;
                        end if;

                    when 4 => -- WAIT FOR HK TO LATCH THE ROW
                        if hk_busy_s = '1' then
                            state <= 5;
                        end if;

                    when 5 => -- WAIT FOR HK TO COMPLETE THE ROW OR THE BATCH
                        if hk_busy_s = '0' then
                            if hk_done_s = '1' then
                                new_runs_done := runs_done + 1;
                                new_conn_total := conn_steps_total + unsigned(hk_conn_steps_s);

                                runs_done <= new_runs_done;
                                conn_steps_total <= new_conn_total;

                                if hk_spanning_s = '1' then
                                    spanning_cnt <= spanning_cnt + 1;
                                end if;

                                occupied_sum <= occupied_sum + run_occupied;

                                report "percolation_core run complete: grid_size=" & integer'image(grid_size) &
                                       " run_occupied=" & integer'image(to_integer(run_occupied)) &
                                       " conn_steps=" & integer'image(to_integer(unsigned(hk_conn_steps_s))) &
                                       " conn_total=" & integer'image(to_integer(new_conn_total)) &
                                       " runs_done=" & integer'image(to_integer(new_runs_done)) &
                                       " hk_busy=" & std_logic'image(hk_busy_s) &
                                       " spanning=" & std_logic'image(hk_spanning_s)
                                    severity note;

                                if pending /= 0 then
                                    pending <= pending - 1;
                                end if;

                                if ((run_enable = '1') or (pending /= 0)) and
                                   ((runs_target = 0) or (new_runs_done < runs_target)) then
                                    fill_index <= 0;
                                    run_occupied <= (others => '0');
                                    row_feed_index <= 0;
                                    state <= 1;
                                else
                                    state <= 0;
                                end if;
                            else
                                row_feed_index <= row_feed_index + 1;
                                state <= 3;
                            end if;
                        end if;

                    when others =>
                        state <= 0;
                end case;
            end if;
        end if;
    end process;
end Behavioral;
