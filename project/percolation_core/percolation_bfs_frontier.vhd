library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

entity percolation_bfs_frontier is
    generic (
        N_ROWS_G : positive := 64
    );
    port (
        Clk           : in std_logic;
        Rst           : in std_logic; -- active low
        CfgInit       : in std_logic;
        GridSteps     : in unsigned(31 downto 0);
        Start         : in std_logic;
        ChunkOpen     : in std_logic_vector(N_ROWS_G - 1 downto 0);
        ChunkValid    : in std_logic;
        Busy          : out std_logic;
        Done          : out std_logic;
        Spanning      : out std_logic
    );
end entity percolation_bfs_frontier;

architecture Behavioral of percolation_bfs_frontier is
    signal grid_steps         : integer := N_ROWS_G;
    signal grid_cells         : integer := N_ROWS_G * N_ROWS_G;

    type state_t is (IDLE, CAPTURE, COMPLETE);
    signal state : state_t := IDLE;

    signal stream_index       : integer := 0;
    signal row_index          : integer := 0;
    signal row_fill_index     : integer range 0 to N_ROWS_G := 0;
    signal pending_row_valid  : std_logic := '0';
    signal pending_row_index  : integer := 0;
    signal p_spanning         : std_logic := '0';
    signal current_open_row   : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal pending_open_row   : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal previous_reach_row : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');

    function min_int(a, b : integer) return integer is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function;

    function chunk_mask(width : integer) return std_logic_vector is
        variable mask : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    begin
        for index in 0 to N_ROWS_G - 1 loop
            if index < width then
                mask(index) := '1';
            end if;
        end loop;

        return mask;
    end function;

    function any_set(row : std_logic_vector(N_ROWS_G - 1 downto 0); width : integer) return std_logic is
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
        open_row : std_logic_vector(N_ROWS_G - 1 downto 0);
        seed_row : std_logic_vector(N_ROWS_G - 1 downto 0);
        width : integer
    ) return std_logic_vector is
        variable stage_reach : unsigned(N_ROWS_G - 1 downto 0);
        variable open_u      : unsigned(N_ROWS_G - 1 downto 0);
        variable step        : integer := 1;
    begin
        open_u := unsigned(open_row);
        stage_reach := unsigned(open_row and seed_row);

        while step < N_ROWS_G loop
            if step < width then
                stage_reach := stage_reach or ((shift_left(stage_reach, step) or shift_right(stage_reach, step)) and open_u);
            end if;

            step := step * 2;
        end loop;

        return std_logic_vector(stage_reach);
    end function;

begin
    Busy <= '1' when state = CAPTURE else '0';
    Done <= '1' when state = COMPLETE else '0';
    Spanning <= p_spanning;

    process(Clk)
        variable cfg_steps_i    : integer;
        variable stream_index_v : integer;
        variable row_index_v    : integer;
        variable row_fill_v     : integer;
        variable pending_row_index_v : integer;
        variable pending_row_valid_v : std_logic;
        variable chunk_cols     : integer;
        variable fill_row_v     : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable pending_row_v  : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable seed_row_v     : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable row_reach_v    : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable prev_reach_v   : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable row_has_reach  : std_logic;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_steps         <= N_ROWS_G;
                grid_cells         <= N_ROWS_G * N_ROWS_G;
                stream_index       <= 0;
                row_index          <= 0;
                row_fill_index     <= 0;
                pending_row_valid  <= '0';
                pending_row_index  <= 0;
                state              <= IDLE;
                p_spanning         <= '0';
                current_open_row   <= (others => '0');
                pending_open_row   <= (others => '0');
                previous_reach_row <= (others => '0');
            else
                if CfgInit = '1' then
                    cfg_steps_i := to_integer(GridSteps);
                    if cfg_steps_i < 1 then
                        cfg_steps_i := 1;
                    end if;

                    grid_steps         <= cfg_steps_i;
                    grid_cells         <= N_ROWS_G * cfg_steps_i;
                    stream_index       <= 0;
                    row_index          <= 0;
                    row_fill_index     <= 0;
                    pending_row_valid  <= '0';
                    pending_row_index  <= 0;
                    state              <= IDLE;
                    p_spanning         <= '0';
                    current_open_row   <= (others => '0');
                    pending_open_row   <= (others => '0');
                    previous_reach_row <= (others => '0');
                else
                    case state is
                        when IDLE =>
                            if Start = '1' then
                                cfg_steps_i := to_integer(GridSteps);
                                if cfg_steps_i < 1 then
                                    cfg_steps_i := 1;
                                end if;

                                grid_steps         <= cfg_steps_i;
                                grid_cells         <= N_ROWS_G * cfg_steps_i;
                                stream_index       <= 0;
                                row_index          <= 0;
                                row_fill_index     <= 0;
                                pending_row_valid  <= '0';
                                pending_row_index  <= 0;
                                p_spanning         <= '0';
                                current_open_row   <= (others => '0');
                                pending_open_row   <= (others => '0');
                                previous_reach_row <= (others => '0');
                                state              <= CAPTURE;
                            end if;

                        when CAPTURE =>
                            stream_index_v := stream_index;
                            row_index_v := row_index;
                            row_fill_v := row_fill_index;
                            pending_row_index_v := pending_row_index;
                            pending_row_valid_v := pending_row_valid;
                            fill_row_v := current_open_row;
                            pending_row_v := pending_open_row;
                            prev_reach_v := previous_reach_row;
                            row_has_reach := '0';

                            if pending_row_valid_v = '1' then
                                if pending_row_index_v = 0 then
                                    seed_row_v := pending_row_v;
                                else
                                    seed_row_v := pending_row_v and prev_reach_v;
                                end if;

                                row_reach_v := reach_row(pending_row_v, seed_row_v, N_ROWS_G);
                                prev_reach_v := row_reach_v;

                                if pending_row_index_v = grid_steps - 1 then
                                    row_has_reach := any_set(row_reach_v, N_ROWS_G);
                                    if row_has_reach = '1' then
                                        p_spanning <= '1';
                                    end if;

                                    report "percolation_bfs_frontier row-wise run complete: grid_width=" & integer'image(N_ROWS_G) &
                                           " grid_steps=" & integer'image(grid_steps) &
                                           " spanning=" & std_logic'image(row_has_reach)
                                        severity note;

                                    pending_row_v := (others => '0');
                                end if;

                                pending_row_valid_v := '0';
                            end if;

                            if ChunkValid = '1' and stream_index_v < grid_cells then
                                    chunk_cols := min_int(grid_cells - stream_index_v, N_ROWS_G);

                                if row_fill_v = 0 then
                                        fill_row_v := ChunkOpen and chunk_mask(chunk_cols);
                                end if;

                                row_fill_v := row_fill_v + chunk_cols;
                                stream_index_v := stream_index_v + chunk_cols;

                                if row_fill_v = N_ROWS_G then
                                    pending_row_v := fill_row_v;
                                    pending_row_valid_v := '1';
                                    pending_row_index_v := row_index_v;
                                    if row_index_v < grid_steps - 1 then
                                        row_index_v := row_index_v + 1;
                                    end if;
                                    row_fill_v := 0;
                                    fill_row_v := (others => '0');
                                end if;
                            end if;

                            stream_index <= stream_index_v;
                            row_index <= row_index_v;
                            row_fill_index <= row_fill_v;
                            pending_row_index <= pending_row_index_v;
                            pending_row_valid <= pending_row_valid_v;
                            current_open_row <= fill_row_v;
                            pending_open_row <= pending_row_v;
                            previous_reach_row <= prev_reach_v;

                            if (stream_index_v = grid_cells) and (pending_row_valid_v = '0') and (row_fill_v = 0) then
                                state <= COMPLETE;
                            end if;

                        when COMPLETE =>
                            state <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
