library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rng_pkg.all;

-- entity for the Trivium bank that generates random numbers for multiple rows in parallel, with shared control signals for loading and resetting groups of rows, and outputs for the generated random numbers, validity masks, and site open flags
entity trivium_array is
    generic (
        N_ROWS_G     : positive := 32;  -- number of parallel rows (Trivium generators) in the bank
        GROUP_SIZE_C : positive := 4    -- number of rows per group for shared control signals, should divide N_ROWS_G evenly for proper grouping and control
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;           -- synchronous reset for the entire bank, active high, will be broadcast to all groups of rows (active high)
        load       : in  std_logic;
        threshold  : in  std_logic_vector(31 downto 0);     -- the threshold for determining if a site is open or closed based on the generated random number, represented as a fixed point number
        keys       : in  key_array_t(0 to N_ROWS_G - 1);    -- array of keys for seeding each Trivium generator, loaded in parallel with the load signal, each key is 80 bits wide
        ivs        : in  iv_array_t(0 to N_ROWS_G - 1);     -- array of IVs for seeding each Trivium generator, loaded in parallel with the load signal, each IV is 80 bits wide
        words_out  : out word_array_t(0 to N_ROWS_G - 1);   -- array of output random numbers from each Trivium generator, each number is represented as a fixed point value with 32 bits for the fractional part
        valid_mask : out flag_array_t(0 to N_ROWS_G - 1);   -- array of validity flags for each row, indicating whether the generated random number is valid (after warm-up cycles) and can be used for the percolation simulation
        site_open  : out flag_array_t(0 to N_ROWS_G - 1);   -- array of site open flags for each row, indicating whether the generated random number is below the threshold and the corresponding site is considered open in the percolation simulation
        all_valid  : out std_logic                          -- signal indicating whether all rows have valid random numbers, used to determine when the generator is ready for use after seeding and warm-up
    );
end entity trivium_array;

architecture rtl of trivium_array is
    constant NUM_GROUPS_C : integer := (N_ROWS_G + GROUP_SIZE_C - 1) / GROUP_SIZE_C;    -- calculate the number of groups based on the total number of rows and the group size, rounding up to ensure all rows are covered

    signal row_words_s : word_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));
    signal row_valid_s : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal row_open_s  : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');

    -- signals for controlling the reset and load of each group of rows, as well as a duplicated threshold signal for comparison in the row processes, since the threshold input is shared but needs to be used in each row process
    signal rst_group  : std_logic_vector(NUM_GROUPS_C - 1 downto 0) := (others => '0');
    signal load_group : std_logic_vector(NUM_GROUPS_C - 1 downto 0) := (others => '0');
    signal threshold_dup : std_logic_vector(31 downto 0) := (others => '0');

begin
    -- broadcast the reset and load signals to the groups of rows, each group receives the same control signal, and duplicate the threshold input for use in the row processes
    rst_group   <= (others => rst);
    load_group  <= (others => load);
    threshold_dup <= threshold;

    -- generate process: for each row in the bank, instantiate a Trivium generator and connect it to the appropriate signals, using the group index to determine which control signals to use for resetting and loading the row,
    -- and comparing the generated random number to the threshold to determine if the site is open
    gen_rows : for index in 0 to N_ROWS_G - 1 generate
        constant GROUP_IDX_C : integer := index / GROUP_SIZE_C;
    begin
        row_rng : entity work.rng_trivium
            generic map (
                num_bits  => WORD_WIDTH,
                init_key  => (others => '0'),
                init_iv   => (others => '0')
            )
            port map (
                clk       => clk,
                rst       => rst_group(GROUP_IDX_C),
                reseed    => load_group(GROUP_IDX_C),
                newkey    => keys(index),
                newiv     => ivs(index),
                out_ready => '1',               -- set to always be ready to recive new random data and requesting for the next clock cycle, so the Trivium generators are always running and generating new random numbers every clock cycle
                out_valid => row_valid_s(index),
                out_data  => row_words_s(index)
            );

        -- determine if the generated random number for this row is below the threshold, indicating that the corresponding site is open in the percolation simulation, only if the random number is valid (after warm-up cycles)
        row_open_s(index) <= '1'
            when row_valid_s(index) = '1' and unsigned(row_words_s(index)) < unsigned(threshold_dup)
            else '0';
    end generate;

    -- the outputs from the Trivium collection are assigned to the entity outputs, allowing the generated random numbers, validity masks, and site open flags to be used by the percolation simulation
    -- valid_mask is propagated for debugging purposes, as is the all_valid signal, which is calculated using the and_reduce function from the package to determine if all rows have valid random numbers and the generator is ready for use
    words_out <= row_words_s;
    valid_mask <= row_valid_s;
    site_open <= row_open_s;
    all_valid <= and_reduce(row_valid_s);
end architecture rtl;