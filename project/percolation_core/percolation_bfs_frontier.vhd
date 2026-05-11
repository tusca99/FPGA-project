library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

-- Pipelined Prefix Network Frontier
-- Splits the log2(N) combinatorial stages into 2 pipeline stages.
-- Stage 1: shifts 1, 2, 4  (local propagation)
-- Stage 2: shifts 8, 16, 32 (long-range propagation)
-- Throughput: 1 row / clock cycle (3-cycle latency: latch -> stage1 -> stage2 -> save)
-- For N=64 @ 100MHz: each stage is ~3 logic levels, giving ~5ns slack.

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

architecture pipelined of percolation_bfs_frontier is
    type state_t is (IDLE, RUNNING, COMPLETE);
    signal state : state_t := IDLE;

    signal grid_steps     : unsigned(31 downto 0) := to_unsigned(N_ROWS_G, 32);
    signal rows_sent      : unsigned(31 downto 0) := (others => '0');
    signal rows_completed : unsigned(31 downto 0) := (others => '0');
    signal p_spanning     : std_logic := '0';

    -- Pipeline stage 0: input latch
    signal s0_open     : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal s0_seed     : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal s0_valid    : std_logic := '0';

    -- Pipeline stage 1: local shifts (d=1,2,4)
    signal s1_reach    : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal s1_open     : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal s1_valid    : std_logic := '0';

    -- Pipeline stage 2: long-range shifts (d=8,16,32)
    signal s2_reach    : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal s2_valid    : std_logic := '0';

    -- Previous row reachability for vertical seeding
    signal previous_reach_row     : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal previous_reach_row_dup : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');

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

    -- Single prefix stage: reach = reach | ((reach << d | reach >> d) & open)
    function prefix_stage(
        reach : std_logic_vector(N_ROWS_G - 1 downto 0);
        openv : std_logic_vector(N_ROWS_G - 1 downto 0);
        shift : integer
    ) return std_logic_vector is
        variable left  : std_logic_vector(N_ROWS_G - 1 downto 0);
        variable right : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        if shift >= N_ROWS_G then
            return reach;
        end if;
        left  := reach(N_ROWS_G - 1 - shift downto 0) & (shift - 1 downto 0 => '0');
        right := (shift - 1 downto 0 => '0') & reach(N_ROWS_G - 1 downto shift);
        return reach or ((left or right) and openv);
    end function;

    -- Chain of 3 prefix stages
    function prefix_chain(
        seed  : std_logic_vector(N_ROWS_G - 1 downto 0);
        openv : std_logic_vector(N_ROWS_G - 1 downto 0);
        d1    : integer;
        d2    : integer;
        d3    : integer
    ) return std_logic_vector is
        variable reach : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        reach := seed;
        reach := prefix_stage(reach, openv, d1);
        reach := prefix_stage(reach, openv, d2);
        reach := prefix_stage(reach, openv, d3);
        return reach;
    end function;

    -- Combinatorial stage outputs
    signal stage1_reach : std_logic_vector(N_ROWS_G - 1 downto 0);
    signal stage2_reach : std_logic_vector(N_ROWS_G - 1 downto 0);

begin
    -- Combinatorial: Stage 1 (local shifts d=1,2,4)
    stage1_reach <= prefix_chain(s0_seed, s0_open, 1, 2, 4);

    -- Combinatorial: Stage 2 (long-range shifts d=8,16,32)
    stage2_reach <= prefix_chain(s1_reach, s1_open, 8, 16, 32);

    -- Busy is '0' when we can accept a new row this cycle
    Busy <= '0' when (state = RUNNING and rows_sent < grid_steps) else '1';
    Done     <= '1' when (state = COMPLETE)  else '0';
    Spanning <= p_spanning;

    process(Clk)
        variable cfg_steps_u : unsigned(31 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state              <= IDLE;
                grid_steps         <= to_unsigned(N_ROWS_G, 32);
                rows_sent          <= (others => '0');
                rows_completed     <= (others => '0');
                p_spanning         <= '0';
                s0_valid           <= '0';
                s1_valid           <= '0';
                s2_valid           <= '0';
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
                    rows_sent          <= (others => '0');
                    rows_completed     <= (others => '0');
                    p_spanning         <= '0';
                    s0_valid           <= '0';
                    s1_valid           <= '0';
                    s2_valid           <= '0';
                    previous_reach_row <= (others => '0');
                    previous_reach_row_dup <= (others => '0');
                    state              <= IDLE;
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
                                rows_sent          <= (others => '0');
                                rows_completed     <= (others => '0');
                                p_spanning         <= '0';
                                s0_valid           <= '0';
                                s1_valid           <= '0';
                                s2_valid           <= '0';
                                previous_reach_row <= (others => '0');
                                previous_reach_row_dup <= (others => '0');
                                state              <= RUNNING;
                            end if;

                        when RUNNING =>
                            -- Stage 0: Latch input row if valid and room remains
                            if ChunkValid = '1' and rows_sent < grid_steps then
                                s0_open  <= ChunkOpen;
                                if rows_sent = 0 then
                                    s0_seed <= ChunkOpen;
                                else
                                    s0_seed <= ChunkOpen and previous_reach_row_dup;
                                end if;
                                s0_valid <= '1';
                                rows_sent <= rows_sent + 1;
                            else
                                s0_valid <= '0';
                            end if;

                            -- Stage 1: Register local prefix result
                            s1_reach <= stage1_reach;
                            s1_open  <= s0_open;
                            s1_valid <= s0_valid;

                            -- Stage 2: Register long-range prefix result
                            s2_reach <= stage2_reach;
                            s2_valid <= s1_valid;

                            -- Stage 3: Save result and check completion
                            if s2_valid = '1' then
                                previous_reach_row     <= s2_reach;
                                previous_reach_row_dup <= s2_reach;
                                rows_completed <= rows_completed + 1;

                                if rows_completed + 1 = grid_steps then
                                    p_spanning <= any_set(s2_reach);
                                    state      <= COMPLETE;
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
end pipelined;
