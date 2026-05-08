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
    type state_t is (IDLE, RUN_READY, RUN_PROCESS, COMPLETE);
    signal state : state_t := IDLE;

    signal grid_steps         : unsigned(31 downto 0) := to_unsigned(N_ROWS_G, 32);
    signal rows_seen          : unsigned(31 downto 0) := (others => '0');
    signal p_spanning         : std_logic := '0';

    -- Row processing registers
    signal current_open       : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal current_seed       : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal current_reach      : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal previous_reach_row     : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal previous_reach_row_dup : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal process_init       : std_logic := '0';

    attribute KEEP : string;
    attribute KEEP of previous_reach_row     : signal is "true";
    attribute KEEP of previous_reach_row_dup : signal is "true";

    attribute MAX_FANOUT : integer;
    attribute MAX_FANOUT of previous_reach_row     : signal is 16;
    attribute MAX_FANOUT of previous_reach_row_dup : signal is 16;

    function any_set(row : std_logic_vector(N_ROWS_G - 1 downto 0)) return std_logic is
    begin
        if unsigned(row) = to_unsigned(0, row'length) then
            return '0';
        end if;
        return '1';
    end function;

begin
    Busy     <= '0' when (state = RUN_READY) else '1';
    Done     <= '1' when (state = COMPLETE)  else '0';
    Spanning <= p_spanning;

    process(Clk)
        variable cfg_steps_u    : unsigned(31 downto 0);
        variable rows_seen_v  : unsigned(31 downto 0);
        variable new_reach    : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable left_shift   : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable right_shift  : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state              <= IDLE;
                grid_steps         <= to_unsigned(N_ROWS_G, 32);
                rows_seen          <= (others => '0');
                p_spanning         <= '0';
                current_open       <= (others => '0');
                current_seed       <= (others => '0');
                current_reach      <= (others => '0');
                previous_reach_row <= (others => '0');
                previous_reach_row_dup <= (others => '0');
                process_init       <= '0';
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
                    current_open       <= (others => '0');
                    current_seed       <= (others => '0');
                    current_reach      <= (others => '0');
                    previous_reach_row <= (others => '0');
                    previous_reach_row_dup <= (others => '0');
                    process_init       <= '0';
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
                                state              <= RUN_READY;
                            end if;

                        when RUN_READY =>
                            if ChunkValid = '1' then
                                current_open <= ChunkOpen;
                                if rows_seen = 0 then
                                    current_seed <= ChunkOpen;
                                else
                                    current_seed <= ChunkOpen and previous_reach_row_dup;
                                end if;
                                process_init   <= '1';
                                state          <= RUN_PROCESS;
                            end if;

                        when RUN_PROCESS =>
                            if process_init = '1' then
                                -- First cycle: initialize reachability
                                current_reach <= current_open and current_seed;
                                process_init  <= '0';
                            else
                                -- Iterate: reach = reach | ((reach << 1 | reach >> 1) & open)
                                left_shift  := current_reach(N_ROWS_G - 2 downto 0) & '0';
                                right_shift := '0' & current_reach(N_ROWS_G - 1 downto 1);
                                new_reach   := current_reach or ((left_shift or right_shift) and current_open);

                                if new_reach = current_reach then
                                    -- Converged: save result
                                    previous_reach_row     <= new_reach;
                                    previous_reach_row_dup <= new_reach;
                                    rows_seen_v := rows_seen + 1;
                                    rows_seen   <= rows_seen_v;

                                    if rows_seen_v = grid_steps then
                                        -- Last row: check spanning
                                        if any_set(new_reach) = '1' then
                                            p_spanning <= '1';
                                        end if;
                                        report "percolation_bfs_frontier run complete: grid_width=" & integer'image(N_ROWS_G) &
                                               " grid_steps=" & integer'image(to_integer(grid_steps)) &
                                               " spanning=" & std_logic'image(any_set(new_reach))
                                            severity note;
                                        state <= COMPLETE;
                                    else
                                        state <= RUN_READY;
                                    end if;
                                else
                                    current_reach <= new_reach;
                                end if;
                            end if;

                        when COMPLETE =>
                            state <= IDLE;

                        when others =>
                            state <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
