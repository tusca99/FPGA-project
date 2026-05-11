library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

-- Correct Combinatorial Prefix Frontier
-- Uses bidirectional associative prefix scan for exact horizontal closure.
-- Algorithmically equivalent to iterative +/-1 propagation.
-- Depth: 2 * log2(N) stages for full prefix scan + final OR.
-- For N=64 @ 100MHz: ~7 LUT levels, easily meets timing.

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
        ReachPopcount : out unsigned(15 downto 0)
    );
end entity percolation_bfs_frontier;

architecture prefix_scan of percolation_bfs_frontier is
    type state_t is (IDLE, RUN_READY, RUN_PROCESS, COMPLETE);
    signal state : state_t := IDLE;

    signal grid_steps         : unsigned(31 downto 0) := to_unsigned(N_ROWS_G, 32);
    signal is_last_row        : std_logic := '0';
    signal rows_seen          : unsigned(31 downto 0) := (others => '0');
    signal p_spanning         : std_logic := '0';

    signal current_open       : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal current_seed       : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
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

    -- Prefix scan pair: (A = all_open_in_segment, B = has_reachable_seed_in_segment)
    type pair_t is record
        a : std_logic;  -- AND of all open cells in the segment
        b : std_logic;  -- OR of (seed AND all_open_from_seed) in the segment
    end record;

    type pair_array_t is array (0 to N_ROWS_G - 1) of pair_t;

    -- Associative combine: right_segment o left_segment
    -- If we have left=[l..m] and right=[m+1..r], the combined [l..r] has:
    --   A = right.A AND left.A  (all open in [l..r])
    --   B = right.B OR (right.A AND left.B)  (seed in right part, or seed in left part that connects through right part)
    function combine_pair(left, right : pair_t) return pair_t is
        variable result : pair_t;
    begin
        result.a := right.a and left.a;
        result.b := right.b or (right.a and left.b);
        return result;
    end function;

    -- Kogge-Stone style prefix scan (left-to-right)
    function prefix_scan_ltr(pairs : pair_array_t) return pair_array_t is
        variable temp   : pair_array_t;
        variable result : pair_array_t;
        variable dist   : integer;
    begin
        temp := pairs;
        dist := 1;
        while dist < N_ROWS_G loop
            for i in 0 to N_ROWS_G - 1 loop
                if i >= dist then
                    result(i) := combine_pair(temp(i - dist), temp(i));
                else
                    result(i) := temp(i);
                end if;
            end loop;
            temp := result;
            dist := dist * 2;
        end loop;
        return temp;
    end function;

    -- Reverse array for right-to-left scan
    function reverse_pairs(pairs : pair_array_t) return pair_array_t is
        variable result : pair_array_t;
    begin
        for i in 0 to N_ROWS_G - 1 loop
            result(i) := pairs(N_ROWS_G - 1 - i);
        end loop;
        return result;
    end function;

    -- Compute horizontal reachability from seed and open vectors
    function horizontal_reach(
        seed  : std_logic_vector(N_ROWS_G - 1 downto 0);
        openv : std_logic_vector(N_ROWS_G - 1 downto 0)
    ) return std_logic_vector is
        variable pairs      : pair_array_t;
        variable ltr_prefix : pair_array_t;
        variable rtl_prefix : pair_array_t;
        variable rtl_pairs  : pair_array_t;
        variable result     : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        -- Build element pairs: (A=open, B=open AND seed)
        for i in 0 to N_ROWS_G - 1 loop
            pairs(i).a := openv(i);
            pairs(i).b := openv(i) and seed(i);
        end loop;

        -- Left-to-right prefix scan: seed to the left (or at) reaches i
        ltr_prefix := prefix_scan_ltr(pairs);

        -- Right-to-left prefix scan: seed to the right (or at) reaches i
        rtl_pairs  := reverse_pairs(pairs);
        rtl_prefix := prefix_scan_ltr(rtl_pairs);

        -- Combine: cell i is reachable if any seed in its contiguous open segment reaches it
        for i in 0 to N_ROWS_G - 1 loop
            result(i) := ltr_prefix(i).b or rtl_prefix(N_ROWS_G - 1 - i).b;
        end loop;

        return result;
    end function;

    -- Combinatorial result
    signal reach_result : std_logic_vector(N_ROWS_G - 1 downto 0);

    function count_ones(bits : std_logic_vector) return unsigned is
        variable result : unsigned(15 downto 0) := (others => '0');
    begin
        for index in bits'range loop
            if bits(index) = '1' then
                result := result + 1;
            end if;
        end loop;
        return result;
    end function;

begin
    -- Combinatorial: exact horizontal closure via prefix scan
    reach_result <= horizontal_reach(current_seed, current_open);

    Busy     <= '0' when (state = RUN_READY) else '1';
    Done     <= '1' when (state = COMPLETE)  else '0';
    Spanning <= p_spanning;
    ReachPopcount <= count_ones(reach_result);

    process(Clk)
        variable cfg_steps_u    : unsigned(31 downto 0);
        variable rows_seen_v  : unsigned(31 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state              <= IDLE;
                grid_steps         <= to_unsigned(N_ROWS_G, 32);
                is_last_row        <= '0';
                rows_seen          <= (others => '0');
                p_spanning         <= '0';
                current_open       <= (others => '0');
                current_seed       <= (others => '0');
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
                    if cfg_steps_u = 1 then
                        is_last_row <= '1';
                    else
                        is_last_row <= '0';
                    end if;
                    state              <= IDLE;
                    p_spanning         <= '0';
                    current_open       <= (others => '0');
                    current_seed       <= (others => '0');
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
                                if cfg_steps_u = 1 then
                                    is_last_row <= '1';
                                else
                                    is_last_row <= '0';
                                end if;
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
                                state          <= RUN_PROCESS;
                            end if;

                        when RUN_PROCESS =>
                            -- Single-cycle combinatorial closure (correct prefix scan)
                            previous_reach_row     <= reach_result;
                            previous_reach_row_dup <= reach_result;
                            rows_seen_v := rows_seen + 1;
                            rows_seen   <= rows_seen_v;

                            if is_last_row = '1' then
                                p_spanning <= any_set(reach_result);
                                state      <= COMPLETE;
                            else
                                -- Lookahead for next row
                                if rows_seen_v = grid_steps - 1 then
                                    is_last_row <= '1';
                                end if;
                                state <= RUN_READY;
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
end prefix_scan;
