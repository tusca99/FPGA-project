library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

entity percolation_hk_row_wise is
        generic (
            MAX_GRID   : integer := 128;
            MAX_CELLS  : integer := 128 * 128;
            LABEL_BITS : integer := 16
        );
        port (
            Clk           : in std_logic;
            Rst           : in std_logic; -- active low
            CfgInit       : in std_logic;
            GridSize      : in std_logic_vector(15 downto 0);
            Start         : in std_logic;
            ChunkOpen     : in std_logic_vector(N_ROWS - 1 downto 0);
            ChunkValid    : in std_logic;
            Busy          : out std_logic;
            Done          : out std_logic;
            Spanning      : out std_logic;
            ConnStepCount : out std_logic_vector(31 downto 0)
        );
    end entity percolation_hk_row_wise;

    architecture Behavioral of percolation_hk_row_wise is
        subtype label_t is integer range 0 to MAX_CELLS;

        type label_row_t is array (0 to MAX_GRID - 1) of label_t;
        type label_parent_t is array (0 to MAX_CELLS) of label_t;
        type flag_t is array (0 to MAX_CELLS) of std_logic;

        type state_t is (IDLE, RUN, COMPLETE);

        signal grid_size        : integer range 1 to MAX_GRID := 64;
        signal grid_cells       : integer range 1 to MAX_CELLS := 64 * 64;
        signal row_index_s      : integer range 0 to MAX_GRID := 0;
        signal col_index_s      : integer range 0 to MAX_GRID := 0;
        signal stream_index_s   : integer range 0 to MAX_CELLS := 0;
        signal next_label_s     : integer range 1 to MAX_CELLS := 1;
        signal state            : state_t := IDLE;
        signal curr_labels_s    : label_row_t := (others => 0);
        signal prev_labels_s    : label_row_t := (others => 0);
        signal parent_mem       : label_parent_t := (others => 0);
        signal touch_top_mem    : flag_t := (others => '0');
        signal touch_bottom_mem : flag_t := (others => '0');
        signal conn_steps_total : unsigned(31 downto 0) := (others => '0');
        signal p_spanning       : std_logic := '0';

        function min_int(a, b : integer) return integer is
        begin
            if a < b then
                return a;
            else
                return b;
            end if;
        end function;

        function find_root(parent : label_parent_t; label_in : label_t) return label_t is
            variable current : label_t := label_in;
        begin
            if current = 0 then
                return 0;
            end if;

            for hop in 0 to MAX_CELLS - 1 loop
                if parent(current) = current then
                    return current;
                end if;
                current := parent(current);
            end loop;

            return current;
        end function;

    begin
        Busy <= '1' when state = RUN else '0';
        Done <= '1' when state = COMPLETE else '0';
        Spanning <= p_spanning;
        ConnStepCount <= std_logic_vector(conn_steps_total);

        process(Clk)
            variable cfg_size_i      : integer;
            variable curr_labels_v   : label_row_t;
            variable prev_labels_v   : label_row_t;
            variable parent_v        : label_parent_t;
            variable top_v           : flag_t;
            variable bottom_v        : flag_t;
            variable next_label_v    : integer;
            variable spanning_v      : std_logic;
            variable row_index_v     : integer;
            variable col_index_v     : integer;
            variable stream_index_v  : integer;
            variable left_label      : label_t;
            variable up_label        : label_t;
            variable left_root       : label_t;
            variable up_root         : label_t;
            variable root_label      : label_t;
            variable row_top         : std_logic;
            variable row_bottom      : std_logic;
            variable current_label   : label_t;
            variable conn_steps_inc  : integer;
            variable bit_is_open     : std_logic;
            variable completed_row   : integer;
        begin
            if rising_edge(Clk) then
                if Rst = '0' then
                    grid_size        <= 64;
                    grid_cells       <= 64 * 64;
                    row_index_s      <= 0;
                    col_index_s      <= 0;
                    stream_index_s   <= 0;
                    next_label_s     <= 1;
                    state            <= IDLE;
                    curr_labels_s    <= (others => 0);
                    prev_labels_s    <= (others => 0);
                    parent_mem       <= (others => 0);
                    touch_top_mem    <= (others => '0');
                    touch_bottom_mem <= (others => '0');
                    conn_steps_total <= (others => '0');
                    p_spanning       <= '0';
                else
                    if CfgInit = '1' then
                        cfg_size_i := min_int(to_integer(unsigned(GridSize)), MAX_GRID);
                        if cfg_size_i < 1 then
                            cfg_size_i := 1;
                        end if;

                        grid_size        <= cfg_size_i;
                        grid_cells       <= cfg_size_i * cfg_size_i;
                        row_index_s      <= 0;
                        col_index_s      <= 0;
                        stream_index_s   <= 0;
                        next_label_s     <= 1;
                        state            <= IDLE;
                        curr_labels_s    <= (others => 0);
                        prev_labels_s    <= (others => 0);
                        parent_mem       <= (others => 0);
                        touch_top_mem    <= (others => '0');
                        touch_bottom_mem <= (others => '0');
                        conn_steps_total <= (others => '0');
                        p_spanning       <= '0';
                    else
                        case state is
                            when IDLE =>
                                if Start = '1' then
                                    cfg_size_i := min_int(to_integer(unsigned(GridSize)), MAX_GRID);
                                    if cfg_size_i < 1 then
                                        cfg_size_i := 1;
                                    end if;

                                    grid_size        <= cfg_size_i;
                                    grid_cells       <= cfg_size_i * cfg_size_i;
                                    row_index_s      <= 0;
                                    col_index_s      <= 0;
                                    stream_index_s   <= 0;
                                    next_label_s     <= 1;
                                    conn_steps_total <= (others => '0');
                                    p_spanning       <= '0';
                                    curr_labels_s    <= (others => 0);
                                    prev_labels_s    <= (others => 0);
                                    parent_mem       <= (others => 0);
                                    touch_top_mem    <= (others => '0');
                                    touch_bottom_mem <= (others => '0');
                                    state            <= RUN;
                                end if;

                            when RUN =>
                                if ChunkValid = '1' then
                                    curr_labels_v  := curr_labels_s;
                                    prev_labels_v  := prev_labels_s;
                                    parent_v       := parent_mem;
                                    top_v          := touch_top_mem;
                                    bottom_v       := touch_bottom_mem;
                                    next_label_v   := next_label_s;
                                    spanning_v     := p_spanning;
                                    row_index_v    := row_index_s;
                                    col_index_v    := col_index_s;
                                    stream_index_v := stream_index_s;
                                    conn_steps_inc  := 0;

                                    for bit_index in 0 to N_ROWS - 1 loop
                                        if stream_index_v < grid_cells then
                                            bit_is_open := ChunkOpen(bit_index);

                                            row_top := '0';
                                            if row_index_v = 0 then
                                                row_top := '1';
                                            end if;

                                            row_bottom := '0';
                                            if row_index_v = grid_size - 1 then
                                                row_bottom := '1';
                                            end if;

                                            left_label := 0;
                                            if col_index_v > 0 then
                                                left_label := curr_labels_v(col_index_v - 1);
                                            end if;

                                            up_label := prev_labels_v(col_index_v);
                                            root_label := 0;

                                            if bit_is_open = '1' then
                                                if left_label = 0 and up_label = 0 then
                                                    if next_label_v < MAX_CELLS then
                                                        next_label_v := next_label_v + 1;
                                                        current_label := next_label_v;
                                                    else
                                                        current_label := MAX_CELLS;
                                                    end if;

                                                    parent_v(current_label) := current_label;
                                                    root_label := current_label;
                                                else
                                                    if left_label /= 0 then
                                                        left_root := find_root(parent_v, left_label);
                                                    else
                                                        left_root := 0;
                                                    end if;

                                                    if up_label /= 0 then
                                                        up_root := find_root(parent_v, up_label);
                                                    else
                                                        up_root := 0;
                                                    end if;

                                                    if left_root = 0 then
                                                        root_label := up_root;
                                                    elsif up_root = 0 then
                                                        root_label := left_root;
                                                    elsif left_root <= up_root then
                                                        root_label := left_root;
                                                        parent_v(up_root) := left_root;
                                                    else
                                                        root_label := up_root;
                                                        parent_v(left_root) := up_root;
                                                    end if;
                                                end if;

                                                if root_label /= 0 then
                                                    top_v(root_label) := top_v(root_label) or row_top;
                                                    bottom_v(root_label) := bottom_v(root_label) or row_bottom;

                                                    if left_label /= 0 then
                                                        left_root := find_root(parent_v, left_label);
                                                        top_v(root_label) := top_v(root_label) or top_v(left_root);
                                                        bottom_v(root_label) := bottom_v(root_label) or bottom_v(left_root);
                                                    end if;

                                                    if up_label /= 0 then
                                                        up_root := find_root(parent_v, up_label);
                                                        top_v(root_label) := top_v(root_label) or top_v(up_root);
                                                        bottom_v(root_label) := bottom_v(root_label) or bottom_v(up_root);
                                                    end if;

                                                    curr_labels_v(col_index_v) := root_label;

                                                    if top_v(root_label) = '1' and bottom_v(root_label) = '1' then
                                                        spanning_v := '1';
                                                    end if;
                                                end if;
                                            else
                                                curr_labels_v(col_index_v) := 0;
                                            end if;

                                            stream_index_v := stream_index_v + 1;
                                            col_index_v := col_index_v + 1;

                                            if col_index_v = grid_size then
                                                completed_row := row_index_v;
                                                prev_labels_v := curr_labels_v;
                                                curr_labels_v := (others => 0);
                                                col_index_v := 0;
                                                row_index_v := row_index_v + 1;
                                                conn_steps_inc := conn_steps_inc + 1;

                                                report "percolation_hk_row_wise row complete: grid_size=" & integer'image(grid_size) &
                                                       " row_index=" & integer'image(completed_row) &
                                                       " conn_total=" & integer'image(to_integer(conn_steps_total) + conn_steps_inc) &
                                                       " p_spanning=" & std_logic'image(spanning_v)
                                                    severity note;
                                            end if;
                                        end if;
                                    end loop;

                                    row_index_s      <= row_index_v;
                                    col_index_s      <= col_index_v;
                                    stream_index_s   <= stream_index_v;
                                    curr_labels_s    <= curr_labels_v;
                                    prev_labels_s    <= prev_labels_v;
                                    parent_mem       <= parent_v;
                                    touch_top_mem    <= top_v;
                                    touch_bottom_mem <= bottom_v;
                                    next_label_s     <= next_label_v;
                                    conn_steps_total <= conn_steps_total + to_unsigned(conn_steps_inc, 32);
                                    p_spanning       <= spanning_v;

                                    if stream_index_v >= grid_cells then
                                        state <= COMPLETE;
                                    end if;
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