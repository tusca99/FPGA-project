library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_connectivity is
    generic (
        MAX_GRID   : integer := 128;
        MAX_CELLS  : integer := 128 * 128;
        VISIT_BITS : integer := 16;
        GRID_BITS  : integer := 7;
        IDX_BITS   : integer := 14
    );
    port (
        Clk           : in std_logic;
        Rst           : in std_logic; -- active low
        CfgInit       : in std_logic;
        GridSize      : in std_logic_vector(15 downto 0);
        Start         : in std_logic;
        GridData      : in std_logic_vector(MAX_CELLS - 1 downto 0);
        Busy          : out std_logic;
        Done          : out std_logic;
        Spanning      : out std_logic;
        ConnStepCount : out std_logic_vector(31 downto 0)
    );
end entity percolation_connectivity;

architecture Behavioral of percolation_connectivity is
    constant VISIT_MAX : unsigned(VISIT_BITS - 1 downto 0) := (others => '1');
    constant QUEUE_BITS : integer := IDX_BITS + 2 * GRID_BITS;

    type visited_t is array (0 to MAX_CELLS - 1) of unsigned(VISIT_BITS - 1 downto 0);
    type queue_t is array (0 to MAX_CELLS - 1) of unsigned(QUEUE_BITS - 1 downto 0);

    signal visited_mem   : visited_t := (others => (others => '0'));
    signal queue_mem     : queue_t;
    signal visit_epoch_s : unsigned(VISIT_BITS - 1 downto 0) := to_unsigned(1, VISIT_BITS);

    signal grid_size      : integer range 1 to MAX_GRID := 64;
    signal grid_cells     : integer range 1 to MAX_CELLS := 64 * 64;
    signal bfs_steps_total : unsigned(31 downto 0) := (others => '0');

    type state_t is (IDLE, BFS_INIT, BFS_LOOP, COMPLETE);
    signal state : state_t := IDLE;

    signal bfs_head   : integer range 0 to MAX_CELLS := 0;
    signal bfs_tail   : integer range 0 to MAX_CELLS := 0;
    signal bfs_cnt    : integer range 0 to MAX_CELLS := 0;
    signal p_spanning : std_logic := '0';

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

begin
    Busy <= '1' when (state = BFS_INIT) or (state = BFS_LOOP) else '0';
    Done <= '1' when state = COMPLETE else '0';
    Spanning <= p_spanning;
    ConnStepCount <= std_logic_vector(bfs_steps_total);

    process(Clk)
        variable cur_entry : unsigned(QUEUE_BITS - 1 downto 0);
        variable cur_idx : integer;
        variable nidx : integer;
        variable row : integer;
        variable col : integer;
        variable cfg_size_i : integer;
        variable q_temp : integer;
        variable head_i : integer;
        variable tail_i : integer;
        variable cnt_i : integer;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_size <= 64;
                grid_cells <= 64 * 64;
                bfs_steps_total <= (others => '0');
                bfs_head <= 0;
                bfs_tail <= 0;
                bfs_cnt <= 0;
                state <= IDLE;
                p_spanning <= '0';
                visit_epoch_s <= to_unsigned(1, VISIT_BITS);
            else
                if CfgInit = '1' then
                    grid_size <= 64;
                    grid_cells <= 64 * 64;
                    bfs_steps_total <= (others => '0');
                    bfs_head <= 0;
                    bfs_tail <= 0;
                    bfs_cnt <= 0;
                    state <= IDLE;
                    p_spanning <= '0';
                    visit_epoch_s <= to_unsigned(1, VISIT_BITS);
                else
                    case state is
                        when IDLE =>
                            if Start = '1' then
                                cfg_size_i := min_int(to_integer(unsigned(GridSize)), MAX_GRID);
                                if cfg_size_i < 1 then
                                    cfg_size_i := 1;
                                end if;

                                grid_size <= cfg_size_i;
                                grid_cells <= cfg_size_i * cfg_size_i;
                                bfs_steps_total <= (others => '0');
                                bfs_head <= 0;
                                bfs_tail <= 0;
                                bfs_cnt <= 0;
                                p_spanning <= '0';
                                visit_epoch_s <= next_epoch(visit_epoch_s);
                                state <= BFS_INIT;
                            end if;

                        when BFS_INIT =>
                            q_temp := 0;
                            bfs_head <= 0;
                            bfs_tail <= 0;
                            bfs_cnt <= 0;

                            for col in 0 to MAX_GRID - 1 loop
                                if col < grid_size then
                                    if GridData(col) = '1' and visited_mem(col) /= visit_epoch_s then
                                        visited_mem(col) <= visit_epoch_s;
                                        queue_mem(q_temp) <= pack_queue(col, 0, col);
                                        q_temp := q_temp + 1;
                                    end if;
                                end if;
                            end loop;

                            bfs_tail <= q_temp;
                            bfs_cnt <= q_temp;

                            if q_temp > 0 then
                                state <= BFS_LOOP;
                            else
                                report "percolation_connectivity run complete: grid_size=" & integer'image(grid_size) &
                                       " bfs_total=" & integer'image(to_integer(bfs_steps_total)) &
                                       " p_spanning=" & std_logic'image(p_spanning)
                                    severity note;
                                state <= COMPLETE;
                            end if;

                        when BFS_LOOP =>
                            if bfs_cnt = 0 then
                                report "percolation_connectivity run complete: grid_size=" & integer'image(grid_size) &
                                       " bfs_total=" & integer'image(to_integer(bfs_steps_total)) &
                                       " p_spanning=" & std_logic'image(p_spanning)
                                    severity note;
                                state <= COMPLETE;
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
                                    if visited_mem(nidx) /= visit_epoch_s and GridData(nidx) = '1' then
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
                                    if visited_mem(nidx) /= visit_epoch_s and GridData(nidx) = '1' then
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
                                    if visited_mem(nidx) /= visit_epoch_s and GridData(nidx) = '1' then
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
                                    if visited_mem(nidx) /= visit_epoch_s and GridData(nidx) = '1' then
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
                            end if;

                        when COMPLETE =>
                            if Start = '0' then
                                state <= IDLE;
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;
end Behavioral;