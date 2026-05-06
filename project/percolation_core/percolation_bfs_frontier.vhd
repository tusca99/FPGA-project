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
        Spanning      : out std_logic;
        RowAcceptPulse : out std_logic;
        RowProcessPulse : out std_logic;
        RowsSeen      : out std_logic_vector(31 downto 0);
        DonePulse     : out std_logic
    );
end entity percolation_bfs_frontier;

architecture Behavioral of percolation_bfs_frontier is
    signal grid_steps         : integer := N_ROWS_G;
    signal rows_seen          : integer := 0;

    type state_t is (IDLE, RUN, COMPLETE);
    signal state : state_t := IDLE;

    signal row_index          : integer := 0;
    signal p_spanning         : std_logic := '0';
    signal previous_reach_row : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal s0_valid            : std_logic := '0';
    signal s0_open_row         : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal s0_seed_row         : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal s0_row_index        : integer := 0;
    signal row_accept_pulse_s  : std_logic := '0';
    signal row_process_pulse_s : std_logic := '0';
    signal done_pulse_s        : std_logic := '0';

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
    Busy <= '1' when (state /= RUN) or (s0_valid = '1') else '0';
    Done <= '1' when state = COMPLETE else '0';
    Spanning <= p_spanning;
    RowAcceptPulse <= row_accept_pulse_s;
    RowProcessPulse <= row_process_pulse_s;
    RowsSeen <= std_logic_vector(to_unsigned(rows_seen, 32));
    DonePulse <= done_pulse_s;

    process(Clk)
        variable cfg_steps_i    : integer;
        variable rows_seen_v    : integer;
        variable row_index_v    : integer;
        variable prev_reach_v   : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable s0_valid_v     : std_logic;
        variable s0_open_v      : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable s0_seed_v      : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable s0_row_index_v : integer;
        variable open_row_v     : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable seed_row_v     : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable row_reach_v    : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable row_has_reach  : std_logic;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                grid_steps         <= N_ROWS_G;
                rows_seen          <= 0;
                row_index          <= 0;
                state              <= IDLE;
                p_spanning         <= '0';
                previous_reach_row <= (others => '0');
                s0_valid            <= '0';
                s0_open_row         <= (others => '0');
                s0_seed_row         <= (others => '0');
                s0_row_index        <= 0;
                row_accept_pulse_s  <= '0';
                row_process_pulse_s <= '0';
                done_pulse_s        <= '0';
            else
                row_accept_pulse_s  <= '0';
                row_process_pulse_s <= '0';
                done_pulse_s        <= '0';
                if CfgInit = '1' then
                    cfg_steps_i := to_integer(GridSteps);
                    if cfg_steps_i < 1 then
                        cfg_steps_i := 1;
                    end if;

                    grid_steps         <= cfg_steps_i;
                    rows_seen          <= 0;
                    row_index          <= 0;
                    state              <= IDLE;
                    p_spanning         <= '0';
                    previous_reach_row <= (others => '0');
                    s0_valid            <= '0';
                    s0_open_row         <= (others => '0');
                    s0_seed_row         <= (others => '0');
                    s0_row_index        <= 0;
                    row_accept_pulse_s  <= '0';
                    row_process_pulse_s <= '0';
                    done_pulse_s        <= '0';
                else
                    case state is
                        when IDLE =>
                            if Start = '1' then
                                cfg_steps_i := to_integer(GridSteps);
                                if cfg_steps_i < 1 then
                                    cfg_steps_i := 1;
                                end if;

                                grid_steps         <= cfg_steps_i;
                                rows_seen          <= 0;
                                row_index          <= 0;
                                p_spanning         <= '0';
                                previous_reach_row <= (others => '0');
                                s0_valid            <= '0';
                                s0_open_row         <= (others => '0');
                                s0_seed_row         <= (others => '0');
                                s0_row_index        <= 0;
                                row_accept_pulse_s  <= '0';
                                row_process_pulse_s <= '0';
                                done_pulse_s        <= '0';
                                state              <= RUN;
                            end if;

                        when RUN =>
                            rows_seen_v := rows_seen;
                            row_index_v := row_index;
                            prev_reach_v := previous_reach_row;
                            s0_valid_v := s0_valid;
                            s0_open_v := s0_open_row;
                            s0_seed_v := s0_seed_row;
                            s0_row_index_v := s0_row_index;
                            row_has_reach := '0';

                            if s0_valid_v = '1' then
                                row_reach_v := reach_row(s0_open_v, s0_seed_v, N_ROWS_G);
                                prev_reach_v := row_reach_v;
                                row_process_pulse_s <= '1';

                                if s0_row_index_v = grid_steps - 1 then
                                    row_has_reach := any_set(row_reach_v, N_ROWS_G);
                                    if row_has_reach = '1' then
                                        p_spanning <= '1';
                                    end if;

                                    report "percolation_bfs_frontier row-wise run complete: grid_width=" & integer'image(N_ROWS_G) &
                                           " grid_steps=" & integer'image(grid_steps) &
                                           " spanning=" & std_logic'image(row_has_reach)
                                        severity note;
                                end if;

                                s0_valid_v := '0';
                            elsif (ChunkValid = '1') and (rows_seen_v < grid_steps) then
                                open_row_v := ChunkOpen;

                                if row_index_v = 0 then
                                    seed_row_v := open_row_v;
                                else
                                    seed_row_v := open_row_v and prev_reach_v;
                                end if;

                                s0_open_v := open_row_v;
                                s0_seed_v := seed_row_v;
                                s0_row_index_v := row_index_v;
                                s0_valid_v := '1';
                                row_accept_pulse_s <= '1';

                                rows_seen_v := rows_seen_v + 1;
                                if row_index_v < grid_steps - 1 then
                                    row_index_v := row_index_v + 1;
                                end if;
                            end if;

                            rows_seen <= rows_seen_v;
                            row_index <= row_index_v;
                            previous_reach_row <= prev_reach_v;
                            s0_valid <= s0_valid_v;
                            s0_open_row <= s0_open_v;
                            s0_seed_row <= s0_seed_v;
                            s0_row_index <= s0_row_index_v;

                            if (rows_seen_v = grid_steps) and (s0_valid_v = '0') then
                                state <= COMPLETE;
                                done_pulse_s <= '1';
                            end if;

                        when COMPLETE =>
                            state <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
