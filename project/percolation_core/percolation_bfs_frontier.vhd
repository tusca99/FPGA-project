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
    signal grid_steps         : unsigned(31 downto 0) := to_unsigned(N_ROWS_G, 32);
    signal rows_seen          : unsigned(31 downto 0) := (others => '0');
    signal p_spanning         : std_logic := '0';
    signal previous_reach_row     : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal previous_reach_row_dup : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');

    attribute KEEP : string;
    attribute KEEP of previous_reach_row     : signal is "true";
    attribute KEEP of previous_reach_row_dup : signal is "true";

    attribute MAX_FANOUT : integer;
    attribute MAX_FANOUT of previous_reach_row     : signal is 16;
    attribute MAX_FANOUT of previous_reach_row_dup : signal is 16;

    type state_t is (IDLE, RUN, COMPLETE);
    signal state : state_t := IDLE;

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
    Busy <= '0' when state = RUN else '1';
    Done <= '1' when state = COMPLETE else '0';
    Spanning <= p_spanning;

    process(Clk)
        variable cfg_steps_u    : unsigned(31 downto 0);
        variable rows_seen_v    : unsigned(31 downto 0);
        variable seed_row_v     : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable row_reach_v    : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_steps         <= to_unsigned(N_ROWS_G, 32);
                rows_seen          <= (others => '0');
                state              <= IDLE;
                p_spanning         <= '0';
                previous_reach_row <= (others => '0');
                previous_reach_row_dup <= (others => '0');
            else
                if CfgInit = '1' then
                    if GridSteps = 0 then
                        cfg_steps_u := to_unsigned(1, 32);
                    else
                        cfg_steps_u := GridSteps;
                    end if;

                    grid_steps         <= cfg_steps_u;
                    rows_seen          <= (others => '0');
                    state              <= IDLE;
                    p_spanning         <= '0';
                    previous_reach_row <= (others => '0');
                    previous_reach_row_dup <= (others => '0');
                else
                    case state is
                        when IDLE =>
                            if Start = '1' then
                                if GridSteps = 0 then
                                    cfg_steps_u := to_unsigned(1, 32);
                                else
                                    cfg_steps_u := GridSteps;
                                end if;

                                grid_steps         <= cfg_steps_u;
                                rows_seen          <= (others => '0');
                                p_spanning         <= '0';
                                previous_reach_row <= (others => '0');
                                previous_reach_row_dup <= (others => '0');
                                state              <= RUN;
                            end if;

                        when RUN =>
                            rows_seen_v := rows_seen;

                            if (ChunkValid = '1') and (rows_seen_v < grid_steps) then
                                -- Compute seed using previous reachability (registered value from last cycle)
                                if rows_seen_v = 0 then
                                    seed_row_v := ChunkOpen;
                                else
                                    seed_row_v := ChunkOpen and previous_reach_row_dup;
                                end if;

                                -- Compute horizontal reachability in one cycle
                                row_reach_v := reach_row(ChunkOpen, seed_row_v, N_ROWS_G);

                                -- Update previous reachability for next row
                                previous_reach_row <= row_reach_v;
                                previous_reach_row_dup <= row_reach_v;

                                -- Check spanning on last row
                                if rows_seen_v = grid_steps - 1 then
                                    if any_set(row_reach_v, N_ROWS_G) = '1' then
                                        p_spanning <= '1';
                                    end if;

                                    report "percolation_bfs_frontier row-wise run complete: grid_width=" & integer'image(N_ROWS_G) &
                                           " grid_steps=" & integer'image(to_integer(grid_steps)) &
                                           " spanning=" & std_logic'image(any_set(row_reach_v, N_ROWS_G))
                                        severity note;
                                end if;

                                -- Increment counter
                                rows_seen_v := rows_seen_v + 1;
                            end if;

                            rows_seen <= rows_seen_v;

                            if rows_seen_v = grid_steps then
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
