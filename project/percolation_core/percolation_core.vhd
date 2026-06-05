-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: percolation_core
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--   - rng_pkg.vhd
--   - rng_hybrid_64.vhd
--   - percolation_bfs_frontier.vhd
--
-- -------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

-- entity to orchestrate percolation simulation: generates random grids, feeds them to the BFS frontier, and accumulates statistics across multiple runs
entity percolation_core is
    generic (
        N_ROWS_G : positive := 32                           -- width of the grid (number of sites per row if interpreting the grid as a 2D lattice)
    );
    port (
        Clk            : in std_logic;
        Rst            : in std_logic;                      -- active low

        -- Fine-grain run control: allows for both continuous streaming execution and stepwise execution with a configurable number of runs per step.
        RunEn          : in std_logic;                      -- master run enable: if high, the core will continuously execute percolation runs back-to-back until stopped or until it hits the runs_target limit.
        StepAddValid   : in std_logic;                      -- stepwise run control: if high, the core will add the value in StepAddCount to the pending runs counter.
        StepAddCount   : in std_logic_vector(31 downto 0);  -- the number of runs to add to the pending counter when StepAddValid is high.

        -- configuration
        CfgP           : in std_logic_vector(31 downto 0);  -- threshold fixed point [0,1) as 32-bit UQ32
        CfgStepsPerRun : in unsigned(31 downto 0);          -- rows / temporal steps per run
        CfgSeed        : in std_logic_vector(31 downto 0);  -- seeds the RNG bank (AES seeding + Trivium state initialization)
        CfgRuns        : in std_logic_vector(31 downto 0);  -- target number of runs
        CfgInit        : in std_logic;                      -- reload config + reset state

        -- status/metrics
        StepCount      : out std_logic_vector(31 downto 0);     -- how many runs it has done
        SpanningCount  : out std_logic_vector(31 downto 0);     -- how many runs had a spanning cluster
        TotalOccupied  : out std_logic_vector(31 downto 0);     -- total number of occupied sites across all runs (for calculating average occupancy)
        SpanningOccupied : out std_logic_vector(31 downto 0);   -- total number of occupied sites in runs that had spanning clusters (for calculating average occupancy of spanning runs, mass)
        Done           : out std_logic
    );
end percolation_core;

architecture Behavioral of percolation_core is

    -- -------------------------------------------------------------------------
    -- Run Controls & Metrics Accumulators
    -- -------------------------------------------------------------------------
    signal runs_target  : unsigned(31 downto 0) := (others => '0');

    signal run_enable               : std_logic := '0';                            -- internal run enable that gates the state machine, allowing for both continuous and stepped execution modes
    signal pending                  : unsigned(31 downto 0) := (others => '0');    -- counts how many runs are pending execution based on the stepwise control inputs, decremented each time a run completes
    signal runs_done                : unsigned(31 downto 0) := (others => '0');    -- counts how many runs have completed, used for both status output and to determine when we've hit the runs_target limit
    signal spanning_cnt             : unsigned(31 downto 0) := (others => '0');    -- counts how many runs had a spanning cluster, used for calculating the probability of spanning and for status output
    signal occupied_sum             : unsigned(31 downto 0) := (others => '0');    -- accumulates the total number of occupied sites across all runs, used for calculating average occupancy and for status output
    signal spanning_occupied_sum    : unsigned(31 downto 0) := (others => '0');    -- accumulates the total number of occupied sites in runs that had spanning clusters, used for calculating average occupancy of spanning runs (mass) and for status output
    
    -- Popcount precision for accumulator
    subtype occupied_count_t is unsigned(31 downto 0);              -- subtipe used to learn the necessary bit width for counting occupied sites
    signal run_occupied : occupied_count_t := (others => '0');
    signal run_spanning_occupied : occupied_count_t := (others => '0');

    -- -------------------------------------------------------------------------
    -- Core State Machine & Pipeline Registers
    -- -------------------------------------------------------------------------
    signal state        : integer range 0 to 2 := 0;                                        -- 0 = IDLE/READY, 1 = RUNNING, 2 = COMPLETE
    signal row_pending  : std_logic := '0';                                                 -- Indicates that a row has been sent to the frontier and we're waiting the busy/done signal
    signal row_popcount_pipe : occupied_count_t := (others => '0');                         -- Pipeline register to hold the popcount of the current row while waiting for the frontier to process it. This allows us to accumulate occupancy in a pipelined fashion without stalling the RNG or frontier.
    signal frontier_start_s   : std_logic := '0';                                           -- Start signal for the frontier, pulsed for one cycle to indicate a new run is starting with the first row.
    signal hk_chunk_valid_s : std_logic := '0';                                             -- Valid signal for the current row being sent to the frontier. This is pulsed for one cycle when we send a new row of open sites.
    signal hk_chunk_open_s  : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');   -- The current row of open sites being sent to the frontier, registered to align with the valid signal and the frontier's busy/done handshake.
    signal frontier_busy_s    : std_logic := '0';                                           -- Busy signal from the frontier indicating it's processing the current row and not ready for the next one. 
    signal frontier_done_s    : std_logic := '0';                                           -- Done signal from the frontier indicating it has completed processing the configured number of rows for the current run and has valid output metrics. 
    signal frontier_spanning_s : std_logic := '0';                                          -- Spanning signal from the frontier indicating whether the current run had a spanning cluster.
    signal frontier_reach_pop_s : unsigned(31 downto 0) := (others => '0');                 -- Reachability popcount from the frontier for the current row, used to accumulate the number of occupied sites that are part of the spanning cluster.
    
    -- Function to compute the bit width for popcount accumulators based on the number of rows.
    -- Popcount width: ceil(log2(N_ROWS_G + 1))
    function popcount_width(n : positive) return integer is
        variable width : integer := 1;
        variable p     : integer := 2;
    begin
        while p < n + 1 loop
            width := width + 1;
            p := p * 2;
        end loop;
        return width;
    end function;

    constant POPCOUNT_WIDTH_C : integer := popcount_width(N_ROWS_G);

    -- separate config signals to initialize/reset the RNG and frontier sub-modules independently, used for debugging and to ensure proper sequencing of resets and initializations.
    signal cfg_init_rng   : std_logic := '0';
    signal cfg_init_front : std_logic := '0';

    signal rng_site_open_s   : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');  -- current row of open sites from the RNG, used to feed the frontier. This is registered to align with the frontier's busy/done handshake.
    signal rng_site_open_reg : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');  -- pipeline register for the current row of open sites from the RNG, allowing us to decouple the RNG's output timing from the frontier's processing timing.
    signal rng_all_valid_s   : std_logic := '0';                                    -- signal from the RNG indicating that all output rows are valid and the RNG has completed any necessary initialization/warming.
    signal rng_busy_s        : std_logic := '1';                                    -- busy signal from the RNG indicating that it is still initializing/warming or is currently processing and not ready to output valid rows. 
    signal rng_master_key_s  : std_logic_vector(127 downto 0) := (others => '0');   -- master key for the RNG's AES seeding, derived from the CfgSeed input. This is computed once at the beginning of each run and remains constant for that run, ensuring that the RNG produces a deterministic sequence of random bits for each run based on the seed.
    signal rng_run_tag_s     : std_logic_vector(31 downto 0) := (others => '0');    -- run tag for the RNG, used to generate different random sequences for each run. This is derived from the CfgSeed and can be incremented or modified for each run to ensure variability in the random sequences across runs.

    -- Constants for RNG seeding: these are arbitrary constants used to derive the master key for the RNG from the input seed. 
    -- They can be any fixed values, but using well-known constants like the golden ratio can help ensure good distribution of bits in the derived key.
    -- This allows to produce a 128-bit master key for the RNG from a single 32-bit seed input, which is necessary for the AES-based seeding mechanism in the RNG.
    -- (the simple 32-bit seed input has been used to reduce the bit width of the UART configuration interface, which is a bottleneck for large seeds.)
    constant C_GOLDEN1 : unsigned(31 downto 0) := x"9E3779B9";
    constant C_GOLDEN2 : unsigned(31 downto 0) := x"243F6A88";

    -- Utility function to count the number of '1' bits in a std_logic_vector, used for calculating occupancy.
    function count_ones(bits : std_logic_vector) return occupied_count_t is
        variable result : occupied_count_t := (others => '0');
    begin
        for index in bits'range loop
            if bits(index) = '1' then
                result := result + 1;
            end if;
        end loop;

        return result;
    end function;

    -- Utility function to convert the flag_array_t type from the RNG (which is an array of std_logic) into a std_logic_vector that can be fed to the frontier. 
    -- The RNG outputs its random bits in a different utility format than the standard that the frontier expects.
    function flags_to_slv(flags : flag_array_t) return std_logic_vector is
        variable bits : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    begin
        for index in flags'range loop
            bits(index) := flags(index);
        end loop;

        return bits;
    end function;

    -- Utility function to derive the master key for the RNG from the input seed. 
    -- This function takes the 32-bit seed and produces a 128-bit master key by applying some simple transformations and combinations of the seed with fixed constants.
    function seed_to_master_key(seed : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable seed_u : unsigned(31 downto 0) := unsigned(seed);
        variable key_u  : unsigned(127 downto 0) := (others => '0');
    begin
        key_u(31 downto 0)   := seed_u;
        key_u(63 downto 32)  := not seed_u;
        key_u(95 downto 64)  := seed_u xor C_GOLDEN1;
        key_u(127 downto 96) := seed_u + C_GOLDEN2;
        return std_logic_vector(key_u);
    end function;

begin
    rng_master_key_s <= seed_to_master_key(CfgSeed);
    rng_run_tag_s <= CfgSeed;

    -- -------------------------------------------------------------------------
    -- Sub-module: Hybrid RNG (AES Seeder + Trivium Arrays)
    -- Provides an independent fresh row of stochastic bits every single clock cycle.
    -- -------------------------------------------------------------------------
    rng_inst : entity work.rng_hybrid_64
        generic map (
            N_ROWS_G => N_ROWS_G
        )
        port map (
            clk        => Clk,
            rst        => cfg_init_rng,
            master_key => rng_master_key_s,
            run_tag    => rng_run_tag_s,
            threshold  => CfgP,
            words_out  => open,             -- output used only for debugging and validation, not needed for the percolation core functionality
            valid_mask => open,             -- output used only for debugging and validation, not needed for the percolation core functionality
            site_open  => rng_site_open_s,
            all_valid  => rng_all_valid_s,
            busy       => rng_busy_s
        );

    -- -------------------------------------------------------------------------
    -- Sub-module: BFS Frontier 
    -- Pipelined reachability graph analyzer. Consumes rows from the RNG 
    -- and assesses end-to-end traversal mathematically via bidirectional prefix scan.
    -- -------------------------------------------------------------------------
    frontier_inst : entity work.percolation_bfs_frontier
        generic map (
            N_ROWS_G => N_ROWS_G
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            CfgInit       => cfg_init_front,
            GridSteps     => CfgStepsPerRun,
            Start         => frontier_start_s,
            ChunkOpen     => hk_chunk_open_s,
            ChunkValid    => hk_chunk_valid_s,
            Busy          => frontier_busy_s,
            Done          => frontier_done_s,
            Spanning      => frontier_spanning_s,
            ReachPopcount => frontier_reach_pop_s
        );

    StepCount           <= std_logic_vector(runs_done);                                         -- output the number of completed runs as a status metric
    SpanningCount       <= std_logic_vector(spanning_cnt);                                      -- output the number of runs that had spanning clusters as a status metric
    TotalOccupied       <= std_logic_vector(occupied_sum);                                      -- output the total number of occupied sites across all runs as a status metric
    SpanningOccupied    <= std_logic_vector(spanning_occupied_sum);                             -- output the total number of occupied sites in runs that had spanning clusters as a status metric
    Done                <= '1' when (runs_target /= 0) and (runs_done >= runs_target) else '0'; -- output a Done signal that goes high when we've hit the target number of runs, allowing the master controller to know when the core has completed its work.

    -- -------------------------------------------------------------------------
    -- Main Core State Machine
    -- Orchestrates row generation from RNG, feeds the BFS frontier at line-rate,
    -- and aggregates final percolation statistics across multiple continuous runs.
    -- -------------------------------------------------------------------------
    process(Clk)
        variable new_runs_done   : unsigned(31 downto 0);                   -- variable to hold the incremented runs_done value before assigning it, allowing us to use the updated value in the same cycle for calculations and reporting.
        variable row_bits_v      : std_logic_vector(N_ROWS_G - 1 downto 0); -- variable to hold the current row of open sites in the format needed to feed the frontier, allowing us to compute it combinationally from the registered RNG output before sending it to the frontier.
    begin
        if rising_edge(Clk) then
            -- reset (active low) and configuration handling
            if Rst = '0' then
                runs_target       <= (others => '0');
                run_enable        <= '0';
                pending           <= (others => '0');
                runs_done         <= (others => '0');
                spanning_cnt      <= (others => '0');
                occupied_sum      <= (others => '0');
                run_occupied      <= (others => '0');
                state             <= 0;
                frontier_start_s  <= '0';
                hk_chunk_valid_s  <= '0';
                hk_chunk_open_s   <= (others => '0');
            else
                -- configuration initialization: when CfgInit is pulsed, we load the configuration parameters and reset all the accumulators and state variables to prepare for a new series of runs.
                if CfgInit = '1' then
                    cfg_init_rng   <= '1';
                    cfg_init_front <= '1';
                    runs_target    <= unsigned(CfgRuns);
                    run_enable     <= '0';
                    pending        <= (others => '0');
                    runs_done      <= (others => '0');
                    spanning_cnt   <= (others => '0');
                    occupied_sum   <= (others => '0');
                    spanning_occupied_sum <= (others => '0');
                    run_occupied   <= (others => '0');
                    run_spanning_occupied <= (others => '0');
                    state          <= 0;
                    frontier_start_s <= '0';
                    hk_chunk_valid_s <= '0';
                    hk_chunk_open_s  <= (others => '0');
                else
                    cfg_init_rng   <= '0';
                    cfg_init_front <= '0';

                    -- Pipeline register: latch RNG output every cycle
                    rng_site_open_reg <= rng_site_open_s;

                    -- run enable logic: the core will start executing runs when either the master RunEn is high (continuous mode) or when there are pending runs.
                    if RunEn = '1' then
                        run_enable <= '1';
                    else
                        run_enable <= '0';
                    end if;

                    if StepAddValid = '1' then
                        pending <= pending + unsigned(StepAddCount);
                    end if;

                    frontier_start_s <= '0';
                    hk_chunk_valid_s <= '0';

                    case state is
                    when 0 => -- IDLE / READY STATE
                        -- A new test grid run starts only if:
                        -- 1. The RNG bank has completed initial AES warming and is streaming valid stochastic bits
                        -- 2. Master requests execution (RunEn or stepped limits)
                        -- 3. We haven't successfully hit the limit threshold runs_target
                        if (rng_busy_s = '0') and (rng_all_valid_s = '1') and
                           ((run_enable = '1') or (pending /= 0)) and
                           ((runs_target = 0) or (runs_done < runs_target)) then
                            run_occupied <= (others => '0');
                            run_spanning_occupied <= (others => '0');
                            frontier_start_s <= '1';
                            hk_chunk_valid_s <= '0';
                            hk_chunk_open_s <= (others => '0');
                            state        <= 1;
                        end if;

                    when 1 => -- RUNNING STATE: evaluate grid line-by-line
                        if frontier_done_s = '1' then
                            -- The BFS frontier has successfully digested GridSteps rows.
                            -- Finalize metrics and snapshot the statistics for UART, then transition to IDLE.
                            new_runs_done := runs_done + 1;

                            runs_done <= new_runs_done;

                            if frontier_spanning_s = '1' then
                                spanning_cnt <= spanning_cnt + 1;
                                -- Only accumulate spanning-occupied for runs that actually spanned.
                                spanning_occupied_sum <= spanning_occupied_sum + run_spanning_occupied;
                            end if;

                            -- Total occupied is accumulated for every run.
                            occupied_sum <= occupied_sum + run_occupied;

                            -- Report the results of the run for debugging and validation purposes. 
                                report "percolation_core run complete: grid_width=" & integer'image(N_ROWS_G) &
                                    " grid_steps=" & integer'image(to_integer(CfgStepsPerRun)) &
                                    " run_occupied=" & integer'image(to_integer(run_occupied)) &
                                    " run_spanning=" & integer'image(to_integer(run_spanning_occupied)) &
                                    " runs_done=" & integer'image(to_integer(new_runs_done)) &
                                    " frontier_busy=" & std_logic'image(frontier_busy_s) &
                                    " spanning=" & std_logic'image(frontier_spanning_s)
                                severity note;

                            -- Decrement pending runs if we're in stepped mode.
                            if (pending /= 0) then
                                pending <= pending - 1;
                            end if;

                            state <= 0;
                        elsif frontier_busy_s = '1' and row_pending = '1' then
                            -- Frontier accepted row: accumulate pipelined popcount
                            run_occupied <= run_occupied + row_popcount_pipe;
                            run_spanning_occupied <= run_spanning_occupied + frontier_reach_pop_s;
                            row_pending <= '0';
                        elsif (frontier_busy_s = '0') and (row_pending = '0') then
                            -- Frontier ready: send next row (use registered RNG output)
                            row_bits_v := flags_to_slv(rng_site_open_reg);
                            hk_chunk_open_s  <= row_bits_v;
                            hk_chunk_valid_s <= '1';
                            row_popcount_pipe <= count_ones(row_bits_v);
                            row_pending <= '1';
                        end if;

                    when others =>
                        state <= 0;
                end case;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
