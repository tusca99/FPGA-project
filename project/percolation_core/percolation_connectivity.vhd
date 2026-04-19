library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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
        RowOpen       : in std_logic_vector(MAX_GRID - 1 downto 0);
        RowValid      : in std_logic;
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

    type state_t is (IDLE, WAIT_ROW, SCAN_ROW, COMPLETE);

    signal grid_size         : integer range 1 to MAX_GRID := 64;
    signal row_index_s       : integer range 0 to MAX_GRID := 0;
    signal col_index_s       : integer range 0 to MAX_GRID := 0;
    signal next_label_s      : integer range 1 to MAX_CELLS := 1;
    signal state             : state_t := IDLE;
    signal row_data_s        : std_logic_vector(MAX_GRID - 1 downto 0) := (others => '0');
    signal prev_labels_s     : label_row_t := (others => 0);
    signal curr_labels_s     : label_row_t := (others => 0);
    signal parent_mem        : label_parent_t := (others => 0);
    signal touch_top_mem     : flag_t := (others => '0');
    signal touch_bottom_mem  : flag_t := (others => '0');
    signal conn_steps_total  : unsigned(31 downto 0) := (others => '0');
    signal p_spanning        : std_logic := '0';

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
    Busy <= '1' when state = SCAN_ROW else '0';
    Done <= '1' when state = COMPLETE else '0';
    Spanning <= p_spanning;
    ConnStepCount <= std_logic_vector(conn_steps_total);

    process(Clk)
        variable cfg_size_i    : integer;
        variable curr_labels_v : label_row_t;
        variable parent_v      : label_parent_t;
        variable touch_top_v   : flag_t;
        variable touch_bottom_v: flag_t;
        variable next_label_v  : integer;
        variable spanning_v    : std_logic;
        variable left_label    : label_t;
        variable up_label      : label_t;
        variable left_root     : label_t;
        variable up_root       : label_t;
        variable root_label    : label_t;
        variable row_top       : std_logic;
        variable row_bottom    : std_logic;
        variable current_label  : label_t;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_size        <= 64;
                row_index_s      <= 0;
                col_index_s      <= 0;
                next_label_s     <= 1;
                state            <= IDLE;
                row_data_s       <= (others => '0');
                prev_labels_s    <= (others => 0);
                curr_labels_s    <= (others => 0);
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
                    row_index_s      <= 0;
                    col_index_s      <= 0;
                    next_label_s     <= 1;
                    state            <= IDLE;
                    row_data_s       <= (others => '0');
                    prev_labels_s    <= (others => 0);
                    curr_labels_s    <= (others => 0);
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
                                row_index_s      <= 0;
                                col_index_s      <= 0;
                                next_label_s     <= 1;
                                conn_steps_total <= (others => '0');
                                p_spanning       <= '0';
                                row_data_s       <= (others => '0');
                                prev_labels_s    <= (others => 0);
                                curr_labels_s    <= (others => 0);
                                parent_mem       <= (others => 0);
                                touch_top_mem    <= (others => '0');
                                touch_bottom_mem <= (others => '0');
                                state            <= WAIT_ROW;
                            end if;

                        when WAIT_ROW =>
                            if RowValid = '1' then
                                row_data_s    <= RowOpen;
                                curr_labels_s <= (others => 0);
                                state         <= SCAN_ROW;
                            end if;

                        when SCAN_ROW =>
                            curr_labels_v := (others => 0);
                            parent_v := parent_mem;
                            touch_top_v := touch_top_mem;
                            touch_bottom_v := touch_bottom_mem;
                            next_label_v := next_label_s;
                            spanning_v := p_spanning;

                            row_top := '0';
                            if row_index_s = 0 then
                                row_top := '1';
                            end if;

                            row_bottom := '0';
                            if row_index_s = grid_size - 1 then
                                row_bottom := '1';
                            end if;

                            for col in 0 to MAX_GRID - 1 loop
                                if col < grid_size then
                                    if row_data_s(col) = '1' then
                                        left_label := 0;
                                        if col > 0 then
                                            left_label := curr_labels_v(col - 1);
                                        end if;

                                        up_label := prev_labels_s(col);
                                        root_label := 0;

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
                                            touch_top_v(root_label) := row_top;
                                            touch_bottom_v(root_label) := row_bottom;

                                            if left_label /= 0 then
                                                left_root := find_root(parent_v, left_label);
                                                touch_top_v(root_label) := touch_top_v(root_label) or touch_top_v(left_root);
                                                touch_bottom_v(root_label) := touch_bottom_v(root_label) or touch_bottom_v(left_root);
                                            end if;

                                            if up_label /= 0 then
                                                up_root := find_root(parent_v, up_label);
                                                touch_top_v(root_label) := touch_top_v(root_label) or touch_top_v(up_root);
                                                touch_bottom_v(root_label) := touch_bottom_v(root_label) or touch_bottom_v(up_root);
                                            end if;

                                            curr_labels_v(col) := root_label;

                                            if touch_top_v(root_label) = '1' and touch_bottom_v(root_label) = '1' then
                                                spanning_v := '1';
                                            end if;
                                        end if;
                                    end if;
                                end if;
                            end loop;

                            parent_mem <= parent_v;
                            touch_top_mem <= touch_top_v;
                            touch_bottom_mem <= touch_bottom_v;
                            next_label_s <= next_label_v;
                            prev_labels_s <= curr_labels_v;
                            curr_labels_s <= curr_labels_v;
                            conn_steps_total <= conn_steps_total + 1;
                            p_spanning <= spanning_v;

                            report "percolation_hk_row_wise row complete: grid_size=" & integer'image(grid_size) &
                                   " row_index=" & integer'image(row_index_s) &
                                   " conn_total=" & integer'image(to_integer(conn_steps_total + 1)) &
                                   " p_spanning=" & std_logic'image(spanning_v)
                                severity note;

                            if row_index_s = grid_size - 1 then
                                state <= COMPLETE;
                            else
                                row_index_s <= row_index_s + 1;
                                state <= WAIT_ROW;
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