library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rng_pkg.all;

entity percolation_core is
    generic (
        N_ROWS_G : positive := 32
    );
    port (
        Clk            : in std_logic;
        Rst            : in std_logic; -- active low

        RunEn          : in std_logic;
        StepAddValid   : in std_logic;
        StepAddCount   : in std_logic_vector(31 downto 0);

        -- configuration
        CfgP           : in std_logic_vector(31 downto 0); -- threshold fixed point [0,1) as 32-bit UQ32
        CfgStepsPerRun : in unsigned(31 downto 0); -- rows / temporal steps per run
        CfgSeed        : in std_logic_vector(31 downto 0); -- seeds the RNG bank
        CfgRuns        : in std_logic_vector(31 downto 0);
        CfgInit        : in std_logic; -- reload config + reset state

        -- status/metrics
        StepCount      : out std_logic_vector(31 downto 0); -- how many runs it has done
        PendingSteps   : out std_logic_vector(31 downto 0);
        SpanningCount  : out std_logic_vector(31 downto 0);
        TotalOccupied  : out std_logic_vector(31 downto 0);
        SpanningOccupied : out std_logic_vector(31 downto 0);
        RngBusy        : out std_logic;
        RngAllValid    : out std_logic;
        Done           : out std_logic
    );
end percolation_core;

architecture Behavioral of percolation_core is
    signal runs_target  : unsigned(31 downto 0) := (others => '0');

    signal run_enable   : std_logic := '0';
    signal pending      : unsigned(31 downto 0) := (others => '0');
    signal runs_done    : unsigned(31 downto 0) := (others => '0');
    signal spanning_cnt : unsigned(31 downto 0) := (others => '0');
    signal occupied_sum : unsigned(31 downto 0) := (others => '0');
    signal spanning_occupied_sum : unsigned(31 downto 0) := (others => '0');
    subtype occupied_count_t is unsigned(15 downto 0);
    signal run_occupied : occupied_count_t := (others => '0');
    signal run_spanning_occupied : occupied_count_t := (others => '0');

    signal state        : integer range 0 to 2 := 0;
    signal row_pending  : std_logic := '0';
    signal row_bits_reg   : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal row_popcount_pipe : occupied_count_t := (others => '0');
    attribute KEEP : string;
    attribute KEEP of row_bits_reg : signal is "true";
    attribute KEEP of row_popcount_pipe : signal is "true";
    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of row_bits_reg : signal is "true";
    attribute DONT_TOUCH of row_popcount_pipe : signal is "true";
    signal frontier_start_s   : std_logic := '0';
    signal hk_chunk_valid_s : std_logic := '0';
    signal hk_chunk_open_s  : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    signal frontier_busy_s    : std_logic := '0';
    signal frontier_done_s    : std_logic := '0';
    signal frontier_spanning_s : std_logic := '0';
    signal frontier_reach_pop_s : unsigned(15 downto 0) := (others => '0');
    
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

    signal cfg_init_core  : std_logic := '0';
    signal cfg_init_rng   : std_logic := '0';
    signal cfg_init_front : std_logic := '0';

    attribute KEEP of cfg_init_core  : signal is "true";
    attribute KEEP of cfg_init_rng   : signal is "true";
    attribute KEEP of cfg_init_front : signal is "true";

    attribute MAX_FANOUT : integer;
    attribute MAX_FANOUT of cfg_init_core  : signal is 16;
    attribute MAX_FANOUT of cfg_init_rng   : signal is 16;
    attribute MAX_FANOUT of cfg_init_front : signal is 16;
    signal rng_site_open_s   : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal rng_site_open_reg : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    attribute KEEP of rng_site_open_reg : signal is "true";
    signal rng_all_valid_s   : std_logic := '0';
    signal rng_busy_s        : std_logic := '1';
    signal rng_rst_s         : std_logic := '1';
    signal rng_master_key_s  : std_logic_vector(127 downto 0) := (others => '0');
    signal rng_run_tag_s     : std_logic_vector(31 downto 0) := (others => '0');

    constant C_GOLDEN1 : unsigned(31 downto 0) := x"9E3779B9";
    constant C_GOLDEN2 : unsigned(31 downto 0) := x"243F6A88";

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

    function flags_to_slv(flags : flag_array_t) return std_logic_vector is
        variable bits : std_logic_vector(N_ROWS_G - 1 downto 0) := (others => '0');
    begin
        for index in flags'range loop
            bits(index) := flags(index);
        end loop;

        return bits;
    end function;

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
    rng_rst_s <= (not Rst) or CfgInit;
    rng_master_key_s <= seed_to_master_key(CfgSeed);
    rng_run_tag_s <= CfgSeed;

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
            words_out  => open,
            valid_mask => open,
            site_open  => rng_site_open_s,
            all_valid  => rng_all_valid_s,
            busy       => rng_busy_s
        );

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

    StepCount     <= std_logic_vector(runs_done);
    PendingSteps  <= std_logic_vector(pending);
    SpanningCount <= std_logic_vector(spanning_cnt);
    TotalOccupied <= std_logic_vector(occupied_sum);
    SpanningOccupied <= std_logic_vector(spanning_occupied_sum);
    RngBusy       <= rng_busy_s;
    RngAllValid   <= rng_all_valid_s;
    Done          <= '1' when (runs_target /= 0) and (runs_done >= runs_target) else '0';

    process(Clk)
        variable new_runs_done   : unsigned(31 downto 0);
        variable row_bits_v      : std_logic_vector(N_ROWS_G - 1 downto 0);
    begin
        if rising_edge(Clk) then
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
                if CfgInit = '1' then
                    cfg_init_core  <= '1';
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
                    cfg_init_core  <= '0';
                    cfg_init_rng   <= '0';
                    cfg_init_front <= '0';

                    -- Pipeline register: latch RNG output every cycle
                    rng_site_open_reg <= rng_site_open_s;

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
                    when 0 =>
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

                    when 1 =>
                        if frontier_done_s = '1' then
                            new_runs_done := runs_done + 1;

                            runs_done <= new_runs_done;

                            if frontier_spanning_s = '1' then
                                spanning_cnt <= spanning_cnt + 1;
                            end if;

                            occupied_sum <= occupied_sum + run_occupied;
                            spanning_occupied_sum <= spanning_occupied_sum + run_spanning_occupied;

                                          report "percolation_core run complete: grid_width=" & integer'image(N_ROWS_G) &
                                              " grid_steps=" & integer'image(to_integer(CfgStepsPerRun)) &
                                   " run_occupied=" & integer'image(to_integer(run_occupied)) &
                                   " run_spanning=" & integer'image(to_integer(run_spanning_occupied)) &
                                   " runs_done=" & integer'image(to_integer(new_runs_done)) &
                                              " frontier_busy=" & std_logic'image(frontier_busy_s) &
                                              " spanning=" & std_logic'image(frontier_spanning_s)
                                severity note;

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
                            row_bits_reg <= row_bits_v;
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
