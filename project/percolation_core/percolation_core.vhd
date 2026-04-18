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
        BfsStepCount   : out std_logic_vector(31 downto 0);
        Done           : out std_logic
    );
end percolation_core;

architecture Behavioral of percolation_core is
    constant MAX_GRID   : integer := 128;
    constant MAX_CELLS  : integer := MAX_GRID * MAX_GRID;
    constant VISIT_BITS  : integer := 16;
    constant VISIT_MAX    : unsigned(VISIT_BITS-1 downto 0) := (others => '1');
    constant GRID_BITS  : integer := 7;
    constant IDX_BITS   : integer := 14;
    constant QUEUE_BITS : integer := IDX_BITS + 2 * GRID_BITS;

    type grid_t    is array (0 to MAX_CELLS-1) of std_logic;
    type visited_t is array (0 to MAX_CELLS-1) of unsigned(VISIT_BITS-1 downto 0);
    -- Queue entries pack linear index, row, and column to avoid div/mod in BFS.
    type queue_t   is array (0 to MAX_CELLS-1) of unsigned(QUEUE_BITS-1 downto 0);

    signal grid_mem     : grid_t := (others => '0');
    signal visited_mem  : visited_t := (others => (others => '0'));
    signal queue_mem    : queue_t;
    signal visit_epoch_s : unsigned(VISIT_BITS-1 downto 0) := to_unsigned(1, VISIT_BITS);

    signal grid_size    : integer range 1 to MAX_GRID := 64;
    signal grid_cells   : integer range 1 to MAX_CELLS := 64*64;
    signal runs_target  : unsigned(31 downto 0) := (others => '0');

    signal run_enable   : std_logic := '0';
    signal pending      : unsigned(31 downto 0) := (others => '0');
    signal runs_done    : unsigned(31 downto 0) := (others => '0');
    signal spanning_cnt : unsigned(31 downto 0) := (others => '0');
    signal occupied_sum : unsigned(31 downto 0) := (others => '0');
    signal bfs_steps_total : unsigned(31 downto 0) := (others => '0');

    signal state        : integer range 0 to 5 := 0;
    signal gen_index    : integer range 0 to MAX_GRID := 0;
    signal gen_row_base : integer range 0 to MAX_GRID := 0;
    signal gen_row_start : integer range 0 to MAX_CELLS := 0;
    signal bfs_head     : integer range 0 to MAX_CELLS := 0;
    signal bfs_tail     : integer range 0 to MAX_CELLS := 0;
    signal bfs_cnt      : integer range 0 to MAX_CELLS := 0;
    signal p_spanning   : std_logic := '0';
    signal run_occupied : unsigned(31 downto 0) := (others => '0');

    signal rng_words_s       : word_array_t := (others => (others => '0'));
    signal rng_valid_mask_s  : flag_array_t := (others => '0');
    signal rng_site_open_s   : flag_array_t := (others => '0');
    signal rng_chunk_open_s  : flag_array_t := (others => '0');
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

    function next_epoch(current : unsigned) return unsigned is
    begin
        if current = VISIT_MAX then
            return to_unsigned(1, VISIT_BITS);
        else
            return current + 1;
        end if;
    end function;

    function pack_queue(idx, row, col : integer) return unsigned is
    begin
        return to_unsigned(idx, IDX_BITS) &
               to_unsigned(row, GRID_BITS) &
               to_unsigned(col, GRID_BITS);
    end function;

    function queue_idx(entry : unsigned) return integer is
    begin
        return to_integer(entry(QUEUE_BITS - 1 downto 2 * GRID_BITS));
    end function;

    function queue_row(entry : unsigned) return integer is
    begin
        return to_integer(entry(2 * GRID_BITS - 1 downto GRID_BITS));
    end function;

    function queue_col(entry : unsigned) return integer is
    begin
        return to_integer(entry(GRID_BITS - 1 downto 0));
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

    StepCount     <= std_logic_vector(runs_done);
    PendingSteps  <= std_logic_vector(pending);
    SpanningCount <= std_logic_vector(spanning_cnt);
    TotalOccupied <= std_logic_vector(occupied_sum);
    BfsStepCount  <= std_logic_vector(bfs_steps_total);
    Done          <= '1' when (runs_target /= 0) and (runs_done >= runs_target) else '0';

    process(Clk)
        variable cur_entry : unsigned(QUEUE_BITS - 1 downto 0);
        variable cur_idx : integer;
        variable nidx    : integer;
        variable row     : integer;
        variable col     : integer;
        variable cfg_size_i : integer;
        variable new_runs_done : unsigned(31 downto 0);
        variable q_temp  : integer;
        variable head_i  : integer;
        variable tail_i  : integer;
        variable cnt_i   : integer;
        variable i       : integer;
        variable chunk_cols : integer;
        variable chunk_occupied : integer;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_size    <= 64;
                grid_cells   <= 64*64;
                runs_target  <= (others => '0');
                run_enable   <= '0';
                pending      <= (others => '0');
                runs_done    <= (others => '0');
                spanning_cnt <= (others => '0');
                occupied_sum <= (others => '0');
                bfs_steps_total <= (others => '0');
                gen_index    <= 0;
                bfs_head     <= 0;
                bfs_tail     <= 0;
                bfs_cnt      <= 0;
                state        <= 0;
                p_spanning   <= '0';
                run_occupied <= (others => '0');
                gen_row_base <= 0;
                gen_row_start <= 0;
                rng_arm_s    <= '0';
                rng_chunk_open_s <= (others => '0');
                visit_epoch_s <= to_unsigned(1, VISIT_BITS);
            else
                if CfgInit = '1' then
                    cfg_size_i := min_int(to_integer(unsigned(CfgGridSize)), MAX_GRID);
                    if cfg_size_i < 1 then
                        cfg_size_i := 1;
                    end if;
                    grid_size   <= cfg_size_i;
                    grid_cells  <= cfg_size_i * cfg_size_i;
                    runs_target <= unsigned(CfgRuns);

                    run_enable   <= '0';
                    pending      <= (others => '0');
                    runs_done    <= (others => '0');
                    spanning_cnt <= (others => '0');
                    occupied_sum <= (others => '0');
                    bfs_steps_total <= (others => '0');
                    gen_index    <= 0;
                    gen_row_base <= 0;
                    bfs_head     <= 0;
                    bfs_tail     <= 0;
                    bfs_cnt      <= 0;
                    state        <= 0;
                    p_spanning   <= '0';
                    run_occupied <= (others => '0');
                    rng_arm_s    <= '0';
                    rng_chunk_open_s <= (others => '0');
                    gen_row_start <= 0;
                    visit_epoch_s <= to_unsigned(1, VISIT_BITS);
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

                case state is
                    when 0 => -- IDLE
                              if (rng_arm_s = '1') and (rng_busy_s = '0') and (rng_all_valid_s = '1') and
                           ((run_enable = '1') or (pending /= 0)) and
                           ((runs_target = 0) or (runs_done < runs_target)) then
                            visit_epoch_s <= next_epoch(visit_epoch_s);
                            gen_index    <= 0;
                            gen_row_base <= 0;
                            gen_row_start <= 0;
                            run_occupied <= (others => '0');
                            p_spanning   <= '0';
                            rng_chunk_open_s <= (others => '0');
                            state        <= 1;
                        end if;

                    when 1 => -- CAPTURE RNG CHUNK
                        if (rng_busy_s = '0') and (rng_all_valid_s = '1') then
                            rng_chunk_open_s <= rng_site_open_s;
                            state <= 3;
                        end if;

                    when 3 => -- GRID GENERATION
                        if gen_index < grid_size then
                            chunk_cols := min_int(grid_size - gen_row_base, N_ROWS);
                            chunk_occupied := 0;

                            for col_offset in 0 to N_ROWS - 1 loop
                                if col_offset < chunk_cols then
                                    nidx := gen_row_start + gen_row_base + col_offset;
                                    if rng_chunk_open_s(col_offset) = '1' then
                                        grid_mem(nidx) <= '1';
                                        chunk_occupied := chunk_occupied + 1;
                                    else
                                        grid_mem(nidx) <= '0';
                                    end if;
                                end if;
                            end loop;

                            if (gen_index = 0) and (gen_row_base = 0) then
                                report "percolation_core first chunk: busy=" & std_logic'image(rng_busy_s) &
                                       " all_valid=" & std_logic'image(rng_all_valid_s) &
                                       " valid0=" & std_logic'image(rng_valid_mask_s(0)) &
                                       " open0=" & std_logic'image(rng_chunk_open_s(0)) &
                                       " open1=" & std_logic'image(rng_chunk_open_s(1)) &
                                       " open2=" & std_logic'image(rng_chunk_open_s(2)) &
                                       " open3=" & std_logic'image(rng_chunk_open_s(3)) &
                                       " open4=" & std_logic'image(rng_chunk_open_s(4)) &
                                       " open5=" & std_logic'image(rng_chunk_open_s(5)) &
                                       " open6=" & std_logic'image(rng_chunk_open_s(6)) &
                                       " open7=" & std_logic'image(rng_chunk_open_s(7)) &
                                       " chunk_occupied=" & integer'image(chunk_occupied)
                                    severity note;
                            end if;

                            run_occupied <= run_occupied + to_unsigned(chunk_occupied, 32);

                            if gen_row_base + chunk_cols >= grid_size then
                                gen_row_base <= 0;
                                gen_index <= gen_index + 1;
                                gen_row_start <= gen_row_start + grid_size;
                            else
                                gen_row_base <= gen_row_base + N_ROWS;
                            end if;

                            rng_chunk_open_s <= (others => '0');
                            state <= 1;
                        else
                            bfs_head <= 0;
                            bfs_tail <= 0;
                            bfs_cnt <= 0;

                            q_temp := 0;
                            for col in 0 to MAX_GRID - 1 loop
                                if col < grid_size then
                                    if grid_mem(col) = '1' and visited_mem(col) /= visit_epoch_s then
                                        visited_mem(col) <= visit_epoch_s;
                                        queue_mem(q_temp) <= pack_queue(col, 0, col);
                                        q_temp := q_temp + 1;
                                    end if;
                                end if;
                            end loop;

                            bfs_head <= 0;
                            bfs_tail <= q_temp;
                            bfs_cnt <= q_temp;

                            if q_temp > 0 then
                                state <= 2;
                            else
                                state <= 4;
                            end if;
                        end if;

                    when 2 => -- BFS LOOP
                        if bfs_cnt = 0 then
                            state <= 4;
                        else
                            head_i := bfs_head;
                            tail_i := bfs_tail;
                            cnt_i := bfs_cnt;

                            cur_entry := queue_mem(head_i);
                            cur_idx := queue_idx(cur_entry);
                            row := queue_row(cur_entry);
                            col := queue_col(cur_entry);
                            if head_i = (grid_cells - 1) then
                                head_i := 0;
                            else
                                head_i := head_i + 1;
                            end if;
                            cnt_i := cnt_i - 1;
                            bfs_steps_total <= bfs_steps_total + 1;
                            if row = grid_size - 1 then
                                p_spanning <= '1';
                            end if;

                            if row > 0 then
                                nidx := cur_idx - grid_size;
                                if visited_mem(nidx) /= visit_epoch_s and grid_mem(nidx) = '1' then
                                    visited_mem(nidx) <= visit_epoch_s;
                                    queue_mem(tail_i) <= pack_queue(nidx, row - 1, col);
                                    if tail_i = (grid_cells - 1) then
                                        tail_i := 0;
                                    else
                                        tail_i := tail_i + 1;
                                    end if;
                                    cnt_i := cnt_i + 1;
                                end if;
                            end if;

                            if row < grid_size - 1 then
                                nidx := cur_idx + grid_size;
                                if visited_mem(nidx) /= visit_epoch_s and grid_mem(nidx) = '1' then
                                    visited_mem(nidx) <= visit_epoch_s;
                                    queue_mem(tail_i) <= pack_queue(nidx, row + 1, col);
                                    if tail_i = (grid_cells - 1) then
                                        tail_i := 0;
                                    else
                                        tail_i := tail_i + 1;
                                    end if;
                                    cnt_i := cnt_i + 1;
                                end if;
                            end if;

                            if col > 0 then
                                nidx := cur_idx - 1;
                                if visited_mem(nidx) /= visit_epoch_s and grid_mem(nidx) = '1' then
                                    visited_mem(nidx) <= visit_epoch_s;
                                    queue_mem(tail_i) <= pack_queue(nidx, row, col - 1);
                                    if tail_i = (grid_cells - 1) then
                                        tail_i := 0;
                                    else
                                        tail_i := tail_i + 1;
                                    end if;
                                    cnt_i := cnt_i + 1;
                                end if;
                            end if;

                            if col < grid_size - 1 then
                                nidx := cur_idx + 1;
                                if visited_mem(nidx) /= visit_epoch_s and grid_mem(nidx) = '1' then
                                    visited_mem(nidx) <= visit_epoch_s;
                                    queue_mem(tail_i) <= pack_queue(nidx, row, col + 1);
                                    if tail_i = (grid_cells - 1) then
                                        tail_i := 0;
                                    else
                                        tail_i := tail_i + 1;
                                    end if;
                                    cnt_i := cnt_i + 1;
                                end if;
                            end if;

                            bfs_head <= head_i;
                            bfs_tail <= tail_i;
                            bfs_cnt <= cnt_i;

                            if cnt_i = 0 then
                                state <= 4;
                            end if;
                        end if;

                    when 4 => -- RUN COMPLETE
                        report "percolation_core run complete: grid_size=" & integer'image(grid_size) &
                               " gen_index=" & integer'image(gen_index) &
                               " gen_row_base=" & integer'image(gen_row_base) &
                               " run_occupied=" & integer'image(to_integer(run_occupied)) &
                               " bfs_total=" & integer'image(to_integer(bfs_steps_total)) &
                               " runs_done=" & integer'image(to_integer(runs_done)) &
                               " rng_busy=" & std_logic'image(rng_busy_s) &
                               " p_spanning=" & std_logic'image(p_spanning)
                            severity note;

                        new_runs_done := runs_done + 1;
                        runs_done <= new_runs_done;

                        if p_spanning = '1' then
                            spanning_cnt <= spanning_cnt + 1;
                        end if;

                        occupied_sum <= occupied_sum + run_occupied;

                        if pending /= 0 then
                            pending <= pending - 1;
                        end if;

                        if ((run_enable = '1') or (pending /= 0)) and
                           ((runs_target = 0) or (new_runs_done < runs_target)) then
                            visit_epoch_s <= next_epoch(visit_epoch_s);
                            gen_index    <= 0;
                            gen_row_base <= 0;
                            run_occupied <= (others => '0');
                            p_spanning   <= '0';
                            state        <= 1;
                        else
                            state <= 0;
                        end if;

                    when others =>
                        state <= 0;
                end case;
            end if;
        end if;
    end process;
end Behavioral;
