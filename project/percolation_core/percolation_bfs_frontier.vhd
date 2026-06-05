-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: percolation_bfs_frontier
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--   - rng_pkg.vhd
--
-- -------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

-- Pipelined Prefix Frontier (3 cycles per row)
-- Cycle 1: RUN_READY - latch inputs (current_open, current_seed)
-- Cycle 2: RUN_COMPUTE - compute reach_result_reg from latched inputs
-- Cycle 3: RUN_SAVE - save previous_reach_row, compute reach_popcount_reg
-- This breaks the long combinatorial path into two registered stages.

-- The horizontal reachability function computes the connectivity of open sites in a single row given the seed from the previous row.
-- It uses a parallel prefix scan approach to resolve connectivity in O(1) latency.
entity percolation_bfs_frontier is
    generic (
        N_ROWS_G : positive := 64       -- Number of rows in the grid, also determines the width of the input vectors
    );
    port (
        Clk           : in std_logic;
        Rst           : in std_logic;                               -- active low
        CfgInit       : in std_logic;                               -- active high, initializes configuration and resets internal state
        GridSteps     : in unsigned(31 downto 0);                   -- Number of rows to process in the current run
        Start         : in std_logic;                               -- active high, starts the BFS frontier processing for the configured number of rows
        ChunkOpen     : in std_logic_vector(N_ROWS_G - 1 downto 0); -- Open sites for the current row being processed
        ChunkValid    : in std_logic;                               -- Indicates that the current ChunkOpen is valid and can be processed (high for one cycle when new data is available)
        Busy          : out std_logic;                              -- High when the module is processing and should not be started again
        Done          : out std_logic;                              -- High for one cycle when the BFS frontier has completed processing the configured number of rows
        Spanning      : out std_logic;                              -- High if the BFS frontier finds a spanning cluster connecting the top to the bottom of the grid after processing all rows
        ReachPopcount : out unsigned(31 downto 0)                   -- The number of reachable sites in the last processed row, used for statistics and analysis
    );
end entity percolation_bfs_frontier;

architecture pipelined_prefix of percolation_bfs_frontier is
    -- State machine states
    type state_t is (IDLE, RUN_READY, RUN_COMPUTE, RUN_SAVE, COMPLETE);
    signal state : state_t := IDLE;

    signal grid_steps         : unsigned(31 downto 0) := to_unsigned(N_ROWS_G, 32); -- Configured number of rows to process, loaded on CfgInit or Start
    signal is_last_row        : std_logic := '0';                                   -- Flag to indicate when processing the last row, used to determine when to check for spanning cluster
    signal rows_seen          : unsigned(31 downto 0) := (others => '0');           -- Counter for how many rows have been processed so far
    signal p_spanning         : std_logic := '0';                                   -- Register for the Spanning output, updated at the end of processing the last row

    signal current_open       : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');     -- Registered input for the current row's open sites
    signal current_seed       : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');     -- Registered seed for the current row, computed from the previous row's reachability
    signal previous_reach_row     : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0'); -- Registered reachability result from the previous row, used to compute the seed for the current row

    -- Pipelined reachability result
    signal reach_result_reg   : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0'); -- Registered output of the horizontal reachability function for the current row, used to save state and compute spanning condition
    signal reach_popcount_reg : unsigned(31 downto 0) := (others => '0');                   -- Registered output for the count of reachable sites in the current row, computed from reach_result_reg

    -- Utility function to check if any site in the row is reachable (used to determine spanning condition at the end)
    function any_set(row : std_logic_vector(N_ROWS_G - 1 downto 0)) return std_logic is
    begin
        if unsigned(row) = to_unsigned(0, row'length) then  -- check if all bits are '0'
            return '0';
        end if;
        return '1';
    end function;

    -- Prefix scan pair: (A = all_open_in_segment, B = has_reachable_seed_in_segment)
    type pair_t is record
        a : std_logic;
        b : std_logic;
    end record;

    -- Array of pairs for the prefix scan
    type pair_array_t is array (0 to N_ROWS_G - 1) of pair_t;

    -- Combines two pairs according to the logic of connectivity:
    -- A segment is fully open if both left and right segments are fully open (AND)
    -- A segment has a reachable seed if either the right segment has a reachable seed, 
    -- or the right segment is fully open and the left segment has a reachable seed (right.b OR (right.a AND left.b)).
    -- This logic captures the idea that connectivity can propagate through fully open segments, and that a reachable seed (percolation) can extend through open sites.
    function combine_pair(left, right : pair_t) return pair_t is
        variable result : pair_t;
    begin
        result.a := right.a and left.a;
        result.b := right.b or (right.a and left.b);
        return result;
    end function;

    -- Performs a parallel prefix scan from left to right on the array of pairs,
    -- using the combine_pair function to compute the cumulative connectivity information across the row.
    function prefix_scan_ltr(pairs : pair_array_t) return pair_array_t is
        variable temp   : pair_array_t; -- Temporary array to hold intermediate results during the scan
        variable result : pair_array_t; -- Final result of the prefix scan, where each element contains the connectivity information for the segment up to that point
        variable dist   : integer;      -- Distance for the current step of the scan, starts at 1 and doubles each iteration to combine pairs in a tree-like fashion
    begin
        temp := pairs;
        dist := 1;
        while dist < N_ROWS_G loop              -- loop until the distance exceeds the number of elements, ensuring that all pairs are combined
            for i in 0 to N_ROWS_G - 1 loop     -- iterate over each element in the array
                if i >= dist then               -- For elements at index i, combine with the element at index i - dist to accumulate connectivity information
                    result(i) := combine_pair(temp(i - dist), temp(i));
                else
                    result(i) := temp(i);
                end if;
            end loop;
            temp := result;
            dist := dist * 2;                   -- Double the distance for the next iteration, effectively combining pairs in a binary tree structure to achieve O(log N) steps
        end loop;
        return temp;
    end function;

    -- Reverses the order of the pairs in the array, used to perform a right-to-left prefix scan by 
    -- first reversing the input, applying the left-to-right scan, and then reversing the output back.
    function reverse_pairs(pairs : pair_array_t) return pair_array_t is
        variable result : pair_array_t;
    begin
        for i in 0 to N_ROWS_G - 1 loop
            result(i) := pairs(N_ROWS_G - 1 - i);
        end loop;
        return result;
    end function;

    -- Computes the horizontal reachability for the current row based on the seed from the previous row and the open sites in the current row.
    function horizontal_reach(
        seed  : std_logic_vector(N_ROWS_G - 1 downto 0);        -- Seed from the previous row, indicating which sites are reachable based on the connectivity of the previous row
        openv : std_logic_vector(N_ROWS_G - 1 downto 0)         -- Open sites in the current row, where '1' indicates an open site and '0' indicates a blocked site
    ) return std_logic_vector is
        -- Mathematically computes site-to-site connectivity in a horizontal line O(1) latency. 
        -- Represents connectivity pairs conceptually traversing both Left-To-Right (LTR) 
        -- and Right-To-Left (RTL) resolving the associative parallel prefix scan spanning graph completely.
        variable pairs      : pair_array_t;
        variable ltr_prefix : pair_array_t;
        variable rtl_prefix : pair_array_t;
        variable rtl_pairs  : pair_array_t;
        variable result     : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        for i in 0 to N_ROWS_G - 1 loop
            pairs(i).a := openv(i);                 -- A segment is fully open if the current site is open (openv(i) = '1')
            pairs(i).b := openv(i) and seed(i);     -- A segment has a reachable seed if the current site is open and the seed from the previous row indicates it is reachable (seed(i) = '1')
        end loop;

        ltr_prefix := prefix_scan_ltr(pairs);       -- Compute left-to-right prefix scan to determine connectivity from the left side
        rtl_pairs  := reverse_pairs(pairs);         -- Reverse the pairs to prepare for right-to-left scan
        rtl_prefix := prefix_scan_ltr(rtl_pairs);   -- Compute left-to-right prefix scan on the reversed pairs, which effectively gives us the right-to-left connectivity information

        for i in 0 to N_ROWS_G - 1 loop
            result(i) := ltr_prefix(i).b or rtl_prefix(N_ROWS_G - 1 - i).b; -- A site is reachable if it has a reachable seed from either the left or the right side, which is determined by the b component of the prefix scans
        end loop;

        return result;
    end function;

    -- Utility function to count the number of '1's in a std_logic_vector, used to compute the number of reachable sites in the current row for statistics and analysis.
    function count_ones(bits : std_logic_vector) return unsigned is
        variable result : unsigned(31 downto 0) := (others => '0');
    begin
        for index in bits'range loop
            if bits(index) = '1' then
                result := result + 1;
            end if;
        end loop;
        return result;
    end function;

    -- Combinatorial: computed from registered inputs
    signal reach_comb : std_logic_vector(N_ROWS_G - 1 downto 0);

begin
    -- Compute the horizontal reachability for the current row based on the registered seed and open sites. 
    -- This is a combinatorial function that will be registered in the next cycle to break the long path.
    reach_comb <= horizontal_reach(current_seed, current_open);

    -- Output assignments based on the state machine
    Busy     <= '0' when (state = RUN_READY) else '1';
    Done     <= '1' when (state = COMPLETE)  else '0';
    Spanning <= p_spanning;
    ReachPopcount <= reach_popcount_reg;

    process(Clk)
        variable cfg_steps_u    : unsigned(31 downto 0);    -- Variable to hold the configured number of steps during initialization or start
        variable rows_seen_v    : unsigned(31 downto 0);    -- Variable to hold the incremented value of rows_seen during the RUN_SAVE state
    begin
        if rising_edge(Clk) then
            -- Reset and configuration handling: On reset, initialize all state and registers to default values. 
            if Rst = '0' then
                state              <= IDLE;
                grid_steps         <= to_unsigned(N_ROWS_G, 32);
                is_last_row        <= '0';
                rows_seen          <= (others => '0');
                p_spanning         <= '0';
                current_open       <= (others => '0');
                current_seed       <= (others => '0');
                previous_reach_row <= (others => '0');
                reach_result_reg   <= (others => '0');
                reach_popcount_reg <= (others => '0');
            else
                -- Configuration initialization: When CfgInit is high, load the configuration parameters and reset the internal state to prepare for a new run.
                if CfgInit = '1' then
                    -- Load the configured number of steps, ensuring that if GridSteps is set to 0, it defaults to 1 to avoid processing zero rows.
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
                    reach_result_reg   <= (others => '0');
                    reach_popcount_reg <= (others => '0');
                else
                    case state is
                        -- IDLE: Wait for the Start signal to begin processing. When Start is high, load the configuration parameters and initialize the state for the BFS frontier processing.
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
                                reach_result_reg   <= (others => '0');
                                reach_popcount_reg <= (others => '0');
                                state              <= RUN_READY;
                            end if;
                        -- RUN_READY: Wait for the ChunkValid signal to latch the current row's open sites and compute the seed for the current row based on the previous row's reachability.
                        when RUN_READY => -- Cycle 1: Seed Propagation check
                            if ChunkValid = '1' then
                                current_open     <= ChunkOpen;
                                if rows_seen = 0 then
                                    -- First line inherits spanning seed explicitly equal to its randomly open sites
                                    current_seed <= ChunkOpen;
                                else
                                    -- All subsequent horizontal lines act as filters masking the prior horizontal reach
                                    current_seed <= ChunkOpen and previous_reach_row;
                                end if;
                                state            <= RUN_COMPUTE;
                            end if;
                        -- RUN_COMPUTE: Compute the horizontal reachability for the current row based on the registered seed and open sites.
                        when RUN_COMPUTE => -- Cycle 2: Resolves horizontal bidirectional prefix scan functionally
                            -- Register reachability combinational tree output (LUT-heavy)
                            -- This breaks the long combinatorial path into two registered stages, reducing the critical path and allowing for larger designs.
                            reach_result_reg <= reach_comb;
                            state            <= RUN_SAVE;
                        -- RUN_SAVE: Latch the computed reachability and update the state for the next iteration.
                        when RUN_SAVE => -- Cycle 3: Latch state
                            -- Save horizontal reachability map and count valid connected density concurrently 
                            previous_reach_row     <= reach_result_reg;
                            reach_popcount_reg     <= count_ones(reach_result_reg);
                            rows_seen_v := rows_seen + 1;
                            rows_seen   <= rows_seen_v;

                            -- If this is the last row, determine if there is a spanning cluster by checking if any site in the reachability result is reachable.
                            if is_last_row = '1' then
                                p_spanning <= any_set(reach_result_reg);
                                state      <= COMPLETE;
                            else
                                if rows_seen_v = grid_steps - 1 then
                                    is_last_row <= '1';
                                end if;
                                state <= RUN_READY;
                            end if;
                        -- COMPLETE: The BFS frontier has completed processing the configured number of rows. 
                        -- The Done signal will be high for one cycle. After this, the state machine returns to IDLE to wait for the next run.
                        when COMPLETE =>
                            state <= IDLE;

                        when others =>
                            state <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;
end pipelined_prefix;
