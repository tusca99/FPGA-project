library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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
        CfgSeed        : in std_logic_vector(31 downto 0);
        CfgRuns        : in std_logic_vector(31 downto 0);
        CfgInit        : in std_logic; -- reload config + reset state

        -- status/metrics
        StepCount      : out std_logic_vector(31 downto 0);
        PendingSteps   : out std_logic_vector(31 downto 0);
        SpanningCount  : out std_logic_vector(31 downto 0);
        TotalOccupied  : out std_logic_vector(31 downto 0);
        MeanOccupied   : out std_logic_vector(31 downto 0)
    );
end percolation_core;

architecture Behavioral of percolation_core is
    constant MAX_GRID   : integer := 128;
    constant MAX_CELLS  : integer := MAX_GRID * MAX_GRID;

    type grid_t    is array (0 to MAX_CELLS-1) of std_logic;
    type visited_t is array (0 to MAX_CELLS-1) of std_logic;
    type queue_t   is array (0 to MAX_CELLS-1) of unsigned(13 downto 0);

    signal grid_mem     : grid_t := (others => '0');
    signal visited_mem  : visited_t := (others => '0');
    signal queue_mem    : queue_t;

    signal grid_size    : integer range 1 to MAX_GRID := 64;
    signal grid_cells   : integer range 1 to MAX_CELLS := 64*64;
    signal p_thresh     : unsigned(31 downto 0) := (others => '0');
    signal runs_target  : unsigned(31 downto 0) := (others => '0');

    signal run_enable   : std_logic := '0';
    signal pending      : unsigned(31 downto 0) := (others => '0');
    signal runs_done    : unsigned(31 downto 0) := (others => '0');
    signal spanning_cnt : unsigned(31 downto 0) := (others => '0');
    signal occupied_sum : unsigned(31 downto 0) := (others => '0');
    signal mean_occ     : unsigned(31 downto 0) := (others => '0');

    signal state        : integer range 0 to 5 := 0;
    signal gen_index    : integer range 0 to MAX_CELLS := 0;
    signal bfs_head     : integer range 0 to MAX_CELLS := 0;
    signal bfs_tail     : integer range 0 to MAX_CELLS := 0;
    signal bfs_cnt      : integer range 0 to MAX_CELLS := 0;
    signal p_spanning   : std_logic := '0';
    signal run_occupied : unsigned(31 downto 0) := (others => '0');

    signal lfsr_value : std_logic_vector(31 downto 0) := (others => '1');
    signal lfsr_load  : std_logic := '0';
    signal lfsr_step  : std_logic := '0';

    function min_int(a, b : integer) return integer is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function;

begin
    lfsr_inst : entity work.percolation_lfsr32
        port map (
            Clk      => Clk,
            Rst      => Rst,
            Load     => lfsr_load,
            StepEn   => lfsr_step,
            SeedIn   => CfgSeed,
            StateOut => lfsr_value
        );

    StepCount     <= std_logic_vector(runs_done);
    PendingSteps  <= std_logic_vector(pending);
    SpanningCount <= std_logic_vector(spanning_cnt);
    TotalOccupied <= std_logic_vector(occupied_sum);
    MeanOccupied  <= std_logic_vector(mean_occ);

    process(Clk)
        variable cur_idx : unsigned(13 downto 0);
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
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_size    <= 64;
                grid_cells   <= 64*64;
                p_thresh     <= (others => '0');
                runs_target  <= (others => '0');
                run_enable   <= '0';
                pending      <= (others => '0');
                runs_done    <= (others => '0');
                spanning_cnt <= (others => '0');
                occupied_sum <= (others => '0');
                mean_occ     <= (others => '0');
                gen_index    <= 0;
                bfs_head     <= 0;
                bfs_tail     <= 0;
                bfs_cnt      <= 0;
                state        <= 0;
                p_spanning   <= '0';
                run_occupied <= (others => '0');
                lfsr_load    <= '0';
                lfsr_step    <= '0';
            else
                lfsr_load <= '0';
                lfsr_step <= '0';

                if CfgInit = '1' then
                    cfg_size_i := min_int(to_integer(unsigned(CfgGridSize)), MAX_GRID);
                    if cfg_size_i < 1 then
                        cfg_size_i := 1;
                    end if;
                    grid_size   <= cfg_size_i;
                    grid_cells  <= cfg_size_i * cfg_size_i;
                    p_thresh    <= unsigned(CfgP);
                    runs_target <= unsigned(CfgRuns);
                    lfsr_load   <= '1';

                    run_enable   <= '0';
                    pending      <= (others => '0');
                    runs_done    <= (others => '0');
                    spanning_cnt <= (others => '0');
                    occupied_sum <= (others => '0');
                    mean_occ     <= (others => '0');
                    gen_index    <= 0;
                    bfs_head     <= 0;
                    bfs_tail     <= 0;
                    bfs_cnt      <= 0;
                    state        <= 0;
                    p_spanning   <= '0';
                    run_occupied <= (others => '0');
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
                        if ((run_enable = '1') or (pending /= 0)) and
                           ((runs_target = 0) or (runs_done < runs_target)) then
                            gen_index    <= 0;
                            run_occupied <= (others => '0');
                            p_spanning   <= '0';
                            state        <= 1;
                        end if;

                    when 1 => -- GRID GENERATION
                        if gen_index < grid_cells then
                            if unsigned(lfsr_value) <= p_thresh then
                                grid_mem(gen_index) <= '1';
                                run_occupied <= run_occupied + 1;
                            else
                                grid_mem(gen_index) <= '0';
                            end if;
                            lfsr_step <= '1';
                            gen_index <= gen_index + 1;
                        else
                            bfs_head <= 0;
                            bfs_tail <= 0;
                            bfs_cnt <= 0;

                            for i in 0 to grid_cells-1 loop
                                visited_mem(i) <= '0';
                            end loop;

                            q_temp := 0;
                            for col in 0 to grid_size-1 loop
                                if grid_mem(col) = '1' then
                                    visited_mem(col) <= '1';
                                    queue_mem(q_temp) <= to_unsigned(col, 14);
                                    q_temp := q_temp + 1;
                                end if;
                            end loop;

                            bfs_cnt <= q_temp;
                            bfs_tail <= q_temp;
                            if bfs_tail >= grid_cells then
                                bfs_tail <= 0;
                            end if;

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

                            cur_idx := queue_mem(head_i);
                            if head_i = (grid_cells - 1) then
                                head_i := 0;
                            else
                                head_i := head_i + 1;
                            end if;
                            cnt_i := cnt_i - 1;

                            row := to_integer(cur_idx) / grid_size;
                            col := to_integer(cur_idx) mod grid_size;
                            if row = grid_size - 1 then
                                p_spanning <= '1';
                            end if;

                            if row > 0 then
                                nidx := to_integer(cur_idx) - grid_size;
                                if visited_mem(nidx) = '0' and grid_mem(nidx) = '1' then
                                    visited_mem(nidx) <= '1';
                                    queue_mem(tail_i) <= to_unsigned(nidx, 14);
                                    if tail_i = (grid_cells - 1) then
                                        tail_i := 0;
                                    else
                                        tail_i := tail_i + 1;
                                    end if;
                                    cnt_i := cnt_i + 1;
                                end if;
                            end if;

                            if row < grid_size - 1 then
                                nidx := to_integer(cur_idx) + grid_size;
                                if visited_mem(nidx) = '0' and grid_mem(nidx) = '1' then
                                    visited_mem(nidx) <= '1';
                                    queue_mem(tail_i) <= to_unsigned(nidx, 14);
                                    if tail_i = (grid_cells - 1) then
                                        tail_i := 0;
                                    else
                                        tail_i := tail_i + 1;
                                    end if;
                                    cnt_i := cnt_i + 1;
                                end if;
                            end if;

                            if col > 0 then
                                nidx := to_integer(cur_idx) - 1;
                                if visited_mem(nidx) = '0' and grid_mem(nidx) = '1' then
                                    visited_mem(nidx) <= '1';
                                    queue_mem(tail_i) <= to_unsigned(nidx, 14);
                                    if tail_i = (grid_cells - 1) then
                                        tail_i := 0;
                                    else
                                        tail_i := tail_i + 1;
                                    end if;
                                    cnt_i := cnt_i + 1;
                                end if;
                            end if;

                            if col < grid_size - 1 then
                                nidx := to_integer(cur_idx) + 1;
                                if visited_mem(nidx) = '0' and grid_mem(nidx) = '1' then
                                    visited_mem(nidx) <= '1';
                                    queue_mem(tail_i) <= to_unsigned(nidx, 14);
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
                        new_runs_done := runs_done + 1;
                        runs_done <= new_runs_done;

                        if p_spanning = '1' then
                            spanning_cnt <= spanning_cnt + 1;
                        end if;

                        occupied_sum <= occupied_sum + run_occupied;
                        if new_runs_done /= 0 then
                            mean_occ <= (occupied_sum + run_occupied) / new_runs_done;
                        else
                            mean_occ <= (others => '0');
                        end if;

                        if pending /= 0 then
                            pending <= pending - 1;
                        end if;

                        if ((run_enable = '1') or (pending /= 0)) and
                           ((runs_target = 0) or (new_runs_done < runs_target)) then
                            gen_index    <= 0;
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
