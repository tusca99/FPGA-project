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

    type state_t is (IDLE, RUN, COMPLETE);
    signal state : state_t := IDLE;

    signal stream_index       : integer := 0;
    signal row_index          : integer := 0;
    signal p_spanning         : std_logic := '0';
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

    function ceil_log2(value : integer) return integer is
        variable v : integer := value - 1;
        variable r : integer := 0;
    begin
        while v > 0 loop
            v := v / 2;
            r := r + 1;
        end loop;

        if r < 1 then
            r := 1;
        end if;

        return r;
    end function;

    constant PIPE_STAGES_C : integer := ceil_log2(N_ROWS_G);

    signal pipe_active      : std_logic := '0';
    signal pipe_stage       : integer range 0 to PIPE_STAGES_C - 1 := 0;
    signal pipe_open_row    : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal pipe_reach_row   : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal pipe_row_index   : integer := 0;

begin
    Busy <= '1' when (state = RUN and pipe_active = '1' and pipe_stage /= PIPE_STAGES_C - 1) else '0';
    Done <= '1' when state = COMPLETE else '0';
    Spanning <= p_spanning;

    process(Clk)
        variable cfg_steps_i    : integer;
        variable stream_index_v : integer;
        variable row_index_v    : integer;
        variable pipe_active_v  : std_logic;
        variable pipe_stage_v   : integer;
        variable pipe_open_v    : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable pipe_reach_v   : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable pipe_row_index_v : integer;
        variable prev_reach_v   : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable stage_reach_u  : unsigned(N_ROWS_G - 1 downto 0);
        variable open_u         : unsigned(N_ROWS_G - 1 downto 0);
        variable step           : integer;
        variable row_has_reach  : std_logic;
        variable chunk_cols     : integer;
        variable open_row_v     : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_steps         <= N_ROWS_G;
                grid_cells         <= N_ROWS_G * N_ROWS_G;
                stream_index       <= 0;
                row_index          <= 0;
                state              <= IDLE;
                p_spanning         <= '0';
                previous_reach_row <= (others => '0');
                pipe_active        <= '0';
                pipe_stage         <= 0;
                pipe_open_row      <= (others => '0');
                pipe_reach_row     <= (others => '0');
                pipe_row_index     <= 0;
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
                    state              <= IDLE;
                    p_spanning         <= '0';
                    previous_reach_row <= (others => '0');
                    pipe_active        <= '0';
                    pipe_stage         <= 0;
                    pipe_open_row      <= (others => '0');
                    pipe_reach_row     <= (others => '0');
                    pipe_row_index     <= 0;
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
                                p_spanning         <= '0';
                                previous_reach_row <= (others => '0');
                                pipe_active        <= '0';
                                pipe_stage         <= 0;
                                pipe_open_row      <= (others => '0');
                                pipe_reach_row     <= (others => '0');
                                pipe_row_index     <= 0;
                                state              <= RUN;
                            end if;

                        when RUN =>
                            stream_index_v := stream_index;
                            row_index_v := row_index;
                            pipe_active_v := pipe_active;
                            pipe_stage_v := pipe_stage;
                            pipe_open_v := pipe_open_row;
                            pipe_reach_v := pipe_reach_row;
                            pipe_row_index_v := pipe_row_index;
                            prev_reach_v := previous_reach_row;
                            row_has_reach := '0';

                            if pipe_active_v = '1' then
                                stage_reach_u := unsigned(pipe_reach_v);
                                open_u := unsigned(pipe_open_v);
                                step := 2 ** pipe_stage_v;
                                if step < N_ROWS_G then
                                    stage_reach_u := stage_reach_u or
                                        ((shift_left(stage_reach_u, step) or shift_right(stage_reach_u, step)) and open_u);
                                end if;
                                pipe_reach_v := std_logic_vector(stage_reach_u);

                                if pipe_stage_v = PIPE_STAGES_C - 1 then
                                    pipe_active_v := '0';
                                    pipe_stage_v := 0;
                                    prev_reach_v := pipe_reach_v;

                                    if pipe_row_index_v = grid_steps - 1 then
                                        row_has_reach := any_set(pipe_reach_v, N_ROWS_G);
                                        if row_has_reach = '1' then
                                            p_spanning <= '1';
                                        end if;

                                        report "percolation_bfs_frontier row-wise run complete: grid_width=" & integer'image(N_ROWS_G) &
                                               " grid_steps=" & integer'image(grid_steps) &
                                               " spanning=" & std_logic'image(row_has_reach)
                                            severity note;
                                    end if;
                                else
                                    pipe_stage_v := pipe_stage_v + 1;
                                end if;
                            end if;

                            if (pipe_active_v = '0') and (ChunkValid = '1') and (stream_index_v < grid_cells) then
                                chunk_cols := min_int(grid_cells - stream_index_v, N_ROWS_G);
                                open_row_v := ChunkOpen and chunk_mask(chunk_cols);
                                pipe_open_v := open_row_v;

                                if row_index_v = 0 then
                                    pipe_reach_v := open_row_v;
                                else
                                    pipe_reach_v := open_row_v and prev_reach_v;
                                end if;

                                pipe_row_index_v := row_index_v;
                                pipe_active_v := '1';
                                pipe_stage_v := 0;
                                stream_index_v := stream_index_v + chunk_cols;

                                if row_index_v < grid_steps - 1 then
                                    row_index_v := row_index_v + 1;
                                end if;
                            end if;

                            stream_index <= stream_index_v;
                            row_index <= row_index_v;
                            pipe_active <= pipe_active_v;
                            pipe_stage <= pipe_stage_v;
                            pipe_open_row <= pipe_open_v;
                            pipe_reach_row <= pipe_reach_v;
                            pipe_row_index <= pipe_row_index_v;
                            previous_reach_row <= prev_reach_v;

                            if (stream_index_v = grid_cells) and (pipe_active_v = '0') then
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
