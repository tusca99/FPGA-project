library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

entity percolation_bfs_frontier is
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
        ChunkOpen     : in std_logic_vector(N_ROWS - 1 downto 0);
        ChunkValid    : in std_logic;
        Busy          : out std_logic;
        Done          : out std_logic;
        Spanning      : out std_logic;
        ConnStepCount : out std_logic_vector(31 downto 0)
    );
end entity percolation_bfs_frontier;

architecture Behavioral of percolation_bfs_frontier is
    signal grid_size          : integer range 1 to MAX_GRID := 64;
    signal grid_cells         : integer range 1 to MAX_CELLS := 64 * 64;
    signal conn_steps_total    : unsigned(31 downto 0) := (others => '0');

    type state_t is (IDLE, CAPTURE, COMPLETE);
    signal state : state_t := IDLE;

    signal stream_index       : integer range 0 to MAX_CELLS := 0;
    signal row_index          : integer range 0 to MAX_GRID - 1 := 0;
    signal row_fill_index     : integer range 0 to MAX_GRID := 0;
    signal p_spanning         : std_logic := '0';
    signal current_open_row   : std_logic_vector(MAX_GRID - 1 downto 0) := (others => '0');
    signal previous_reach_row : std_logic_vector(MAX_GRID - 1 downto 0) := (others => '0');

    function min_int(a, b : integer) return integer is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function;

    function any_set(row : std_logic_vector(MAX_GRID - 1 downto 0); width : integer) return std_logic is
    begin
        if width <= 0 then
            return '0';
        end if;

        if unsigned(row) = to_unsigned(0, row'length) then
            return '0';
        end if;

        return '1';
    end function;

    function reach_row(
        open_row : std_logic_vector(MAX_GRID - 1 downto 0);
        seed_row : std_logic_vector(MAX_GRID - 1 downto 0);
        width : integer
    ) return std_logic_vector is
        variable stage_reach : unsigned(MAX_GRID - 1 downto 0);
        variable open_u      : unsigned(MAX_GRID - 1 downto 0);
    begin
        open_u := unsigned(open_row);
        stage_reach := unsigned(open_row and seed_row);

        if width > 1 then
            stage_reach := stage_reach or ((shift_left(stage_reach, 1) or shift_right(stage_reach, 1)) and open_u);
        end if;

        if width > 2 then
            stage_reach := stage_reach or ((shift_left(stage_reach, 2) or shift_right(stage_reach, 2)) and open_u);
        end if;

        if width > 4 then
            stage_reach := stage_reach or ((shift_left(stage_reach, 4) or shift_right(stage_reach, 4)) and open_u);
        end if;

        if width > 8 then
            stage_reach := stage_reach or ((shift_left(stage_reach, 8) or shift_right(stage_reach, 8)) and open_u);
        end if;

        if width > 16 then
            stage_reach := stage_reach or ((shift_left(stage_reach, 16) or shift_right(stage_reach, 16)) and open_u);
        end if;

        if width > 32 then
            stage_reach := stage_reach or ((shift_left(stage_reach, 32) or shift_right(stage_reach, 32)) and open_u);
        end if;

        if width > 64 then
            stage_reach := stage_reach or ((shift_left(stage_reach, 64) or shift_right(stage_reach, 64)) and open_u);
        end if;

        return std_logic_vector(stage_reach);
    end function;

begin
    Busy <= '1' when state = CAPTURE else '0';
    Done <= '1' when state = COMPLETE else '0';
    Spanning <= p_spanning;
    ConnStepCount <= std_logic_vector(conn_steps_total);

    process(Clk)
        variable cfg_size_i     : integer;
        variable stream_index_v : integer;
        variable row_index_v    : integer;
        variable row_fill_v     : integer;
        variable chunk_cols     : integer;
        variable open_row_v     : std_logic_vector(MAX_GRID - 1 downto 0);
        variable seed_row_v     : std_logic_vector(MAX_GRID - 1 downto 0);
        variable row_reach_v    : std_logic_vector(MAX_GRID - 1 downto 0);
        variable prev_reach_v   : std_logic_vector(MAX_GRID - 1 downto 0);
        variable row_steps_v    : unsigned(31 downto 0);
        variable row_has_reach  : std_logic;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_size          <= 64;
                grid_cells         <= 64 * 64;
                conn_steps_total   <= (others => '0');
                stream_index       <= 0;
                row_index          <= 0;
                row_fill_index     <= 0;
                state              <= IDLE;
                p_spanning         <= '0';
                current_open_row   <= (others => '0');
                previous_reach_row <= (others => '0');
            else
                if CfgInit = '1' then
                    cfg_size_i := min_int(to_integer(unsigned(GridSize)), MAX_GRID);
                    if cfg_size_i < 1 then
                        cfg_size_i := 1;
                    end if;

                    grid_size          <= cfg_size_i;
                    grid_cells         <= cfg_size_i * cfg_size_i;
                    conn_steps_total   <= (others => '0');
                    stream_index       <= 0;
                    row_index          <= 0;
                    row_fill_index     <= 0;
                    state              <= IDLE;
                    p_spanning         <= '0';
                    current_open_row   <= (others => '0');
                    previous_reach_row <= (others => '0');
                else
                    case state is
                        when IDLE =>
                            if Start = '1' then
                                cfg_size_i := min_int(to_integer(unsigned(GridSize)), MAX_GRID);
                                if cfg_size_i < 1 then
                                    cfg_size_i := 1;
                                end if;

                                grid_size          <= cfg_size_i;
                                grid_cells         <= cfg_size_i * cfg_size_i;
                                conn_steps_total   <= (others => '0');
                                stream_index       <= 0;
                                row_index          <= 0;
                                row_fill_index     <= 0;
                                p_spanning         <= '0';
                                current_open_row   <= (others => '0');
                                previous_reach_row <= (others => '0');
                                state              <= CAPTURE;
                            end if;

                        when CAPTURE =>
                            if ChunkValid = '1' then
                                stream_index_v := stream_index;
                                row_index_v := row_index;
                                row_fill_v := row_fill_index;
                                open_row_v := current_open_row;
                                prev_reach_v := previous_reach_row;
                                row_steps_v := conn_steps_total;
                                row_has_reach := '0';

                                chunk_cols := min_int(grid_cells - stream_index_v, N_ROWS);

                                for bit_index in 0 to N_ROWS - 1 loop
                                    if bit_index < chunk_cols then
                                        open_row_v(row_fill_v) := ChunkOpen(bit_index);
                                        row_fill_v := row_fill_v + 1;
                                        stream_index_v := stream_index_v + 1;

                                        if row_fill_v = grid_size then
                                            if row_index_v = 0 then
                                                seed_row_v := open_row_v;
                                            else
                                                seed_row_v := open_row_v and prev_reach_v;
                                            end if;

                                            row_reach_v := reach_row(open_row_v, seed_row_v, grid_size);
                                            prev_reach_v := row_reach_v;
                                            row_steps_v := row_steps_v + to_unsigned(grid_size * 2, 32);

                                            if row_index_v = grid_size - 1 then
                                                row_has_reach := any_set(row_reach_v, grid_size);
                                                if row_has_reach = '1' then
                                                    p_spanning <= '1';
                                                end if;

                                                report "percolation_bfs_frontier row-wise run complete: grid_size=" & integer'image(grid_size) &
                                                       " conn_steps=" & integer'image(to_integer(row_steps_v)) &
                                                       " spanning=" & std_logic'image(row_has_reach)
                                                    severity note;

                                                row_fill_v := 0;
                                                open_row_v := (others => '0');
                                                state <= COMPLETE;
                                            else
                                                row_index_v := row_index_v + 1;
                                                row_fill_v := 0;
                                                open_row_v := (others => '0');
                                            end if;
                                        end if;
                                    end if;
                                end loop;

                                stream_index <= stream_index_v;
                                row_index <= row_index_v;
                                row_fill_index <= row_fill_v;
                                current_open_row <= open_row_v;
                                previous_reach_row <= prev_reach_v;
                                conn_steps_total <= row_steps_v;
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
