-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: rng_hybrid_64
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--   - rng_pkg.vhd
--   - aes_enc.vhd
--   - trivium_array.vhd
--
-- -------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rng_pkg.all;

-- entity for the hybrid RNG design that combines AES-based seeding with Trivium-based random number generation, designed to generate multiple random numbers in parallel for use in the percolation simulation
-- the name is legacy from when the design was based on a 64-grid version of Trivium, but it has been updated to use a generic input for the number of rows, so it can be used with different grid sizes
entity rng_hybrid_64 is
    generic (
        N_ROWS_G : positive := 32   -- number of parallel Trivium rows to generate random numbers from, determines how many AES blocks are needed for seeding
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;                         -- synchronous reset for the entire generator, active high, will reset both the AES module and the Trivium bank, and set the state machine back to IDLE
        master_key : in  std_logic_vector(127 downto 0);    -- the master key for AES-based seeding, can be set by the user to generate different random sequences
        run_tag    : in  std_logic_vector(31 downto 0);     -- the run tag for AES-based seeding, used when iterating over multiple runs to generate different random sequences
        threshold  : in  std_logic_vector(31 downto 0);     -- the threshold for determining if a site is open or closed based on the generated random number, represented as a fixed point number
        words_out  : out word_array_t(0 to N_ROWS_G - 1);   -- the output random numbers from the Trivium generator
        valid_mask : out flag_array_t(0 to N_ROWS_G - 1);   -- the validity mask for the output random numbers, indicating which rows have valid random numbers after the warm-up phase
        site_open  : out flag_array_t(0 to N_ROWS_G - 1);   -- the site open flags for the output random numbers, indicating which sites are open based on the threshold comparison
        all_valid  : out std_logic;                         -- the all valid flag, indicating if all rows have valid random numbers and the generator is ready for use
        busy       : out std_logic                          -- the busy flag, indicating if the generator is still in the process of seeding or warming up and not yet ready for use
    );
end entity rng_hybrid_64;

architecture rtl of rng_hybrid_64 is
    -- the state machine used to seed and warm up the Trivium generators
    type state_t is (IDLE, AES_LOAD, AES_RUN, TRIVIUM_LOAD, TRIVIUM_WARMUP, READY);

    signal state : state_t := IDLE;

    -- keys and IVs for seeding the Trivium generators, stored in arrays to handle multiple rows, initialized to zero
    signal seed_keys_s : key_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));
    signal seed_ivs_s  : iv_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));

    signal aes_rst_n : std_logic := '1';                -- active low reset for the AES module, mantained to 1 
    signal aes_plain_s : std_logic_vector(127 downto 0) := (others => '0');     -- the plaintext input for the AES module, used to generate different seeds by incrementing a counter, initialized to zero
    signal aes_cipher_s : std_logic_vector(127 downto 0) := (others => '0');    -- the ciphertext output from the AES module, used to extract the keys and IVs for seeding the Trivium generators, initialized to zero
    signal aes_done_s : std_logic := '0';               -- the done signal from the AES module, used to indicate when a new seed block is ready, initialized to zero

    signal load_rows_s : std_logic := '0';                  -- the load signal for the Trivium bank, used by the state machine to indicate when the seed keys and IVs are ready and can be loaded into the Trivium generators
    constant AES_SEED_BLOCKS_C : integer := 2 * N_ROWS_G;   -- the number of AES blocks needed to generate enough keys and IVs for seeding all the Trivium rows, calculated as twice the number of rows since each block provides one key and one IV
    signal seed_index : integer range 0 to AES_SEED_BLOCKS_C := 0;
    signal counter_reg : unsigned(127 downto 0) := (others => '0');             -- the counter register used to generate different plaintexts for the AES module, initialized to zero and incremented for each new block,
                                                                                -- allowing for a large number of unique seeds to be generated by combining the master key with the run tag and counter value
    signal master_key_reg : std_logic_vector(127 downto 0) := (others => '0');  -- the register to hold the master key for the AES module, loaded from the input at the start of the seeding process, initialized to zero

    -- signals for the outputs from the Trivium bank, including the generated random numbers, validity masks, and site open flags, initialized to zero
    signal words_s : word_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));
    signal valid_s : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal open_s : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal all_valid_s : std_logic := '0';

    -- function to convert the run tag input into a counter value for the AES plaintext, allowing for different random sequences to be generated for different runs by using the run tag as part of the seed generation process
    -- the function takes the 32-bit run tag and places it in the lower 32 bits of a 128-bit unsigned value, which is then used as the plaintext input for the AES module, combined with the master key to generate unique seeds for the Trivium generators
    function run_tag_to_counter(tag : std_logic_vector(31 downto 0)) return unsigned is
        variable result : unsigned(127 downto 0) := (others => '0');
    begin
        result(31 downto 0) := unsigned(tag);
        return result;
    end function;
begin
    -- a single instance of the AES encryption module is used to generate the seeds for all the Trivium generators
    aes_inst : entity work.aes_enc
        port map (
            clk        => clk,
            rst        => aes_rst_n,
            key        => master_key_reg,
            plaintext  => aes_plain_s,
            ciphertext => aes_cipher_s,
            done       => aes_done_s
        );

    -- the Trivium bank module generates multiple random numbers in parallel based on the seeded keys and IVs, the number of rows is determined by the generic input
    trivium_bank : entity work.trivium_array
        generic map (
            N_ROWS_G => N_ROWS_G
        )
        port map (
            clk        => clk,
            rst        => rst,
            load       => load_rows_s,
            threshold  => threshold,
            keys       => seed_keys_s,
            ivs        => seed_ivs_s,
            words_out  => words_s,
            valid_mask => valid_s,
            site_open  => open_s,
            all_valid  => all_valid_s
        );

    process (clk)
    begin
        if rising_edge(clk) then
            -- reset condition for the state machine, initializes all signals to their default values and sets the state back to IDLE
            if rst = '1' then
                state <= IDLE;
                aes_rst_n <= '1';
                aes_plain_s <= (others => '0');
                seed_index <= 0;
                counter_reg <= (others => '0');
                master_key_reg <= (others => '0');
                load_rows_s <= '0';
                busy <= '0';
            else
            -- the keys and IVs are loaded into the Trivium bank only when the state machine is in the TRIVIUM_LOAD state, which is triggered after all the necessary AES blocks have been generated and stored in the seed arrays
                load_rows_s <= '0';

                case state is
                    -- starting state: IDLE, initializes the seeding process by loading the master key and setting up the counter for the AES plaintext, then transitions to AES_LOAD to start generating the seed blocks
                    when IDLE =>
                        busy <= '1';
                        aes_rst_n <= '1';
                        master_key_reg <= master_key;
                        counter_reg <= run_tag_to_counter(run_tag);
                        seed_index <= 0;    -- start from the first seed block
                        state <= AES_LOAD;

                    -- AES_LOAD state: prepares the AES module to generate a new seed block by setting the plaintext input based on the counter value, then transitions to AES_RUN to wait for the AES encryption to complete
                    when AES_LOAD =>
                        busy <= '1';
                        aes_rst_n <= '0';
                        aes_plain_s <= std_logic_vector(counter_reg);
                        state <= AES_RUN;

                    -- AES_RUN state: waits for the AES module to signal that the encryption is done, then extracts the generated seed block from the AES output and stores it in the appropriate key or IV array based on the current seed index,
                    -- increments the seed index and counter for the next block, and transitions back to AES_LOAD until all necessary blocks have been generated, then transitions to TRIVIUM_LOAD to load the seeds into the Trivium bank
                    when AES_RUN =>
                        busy <= '1';
                        aes_rst_n <= '1';
                        if aes_done_s = '1' then
                            -- taking 80 bits from the AES output each run: even indexes correspond to keys, odd indexes correspond to IVs, stored separately
                            if (seed_index mod 2) = 0 then
                                seed_keys_s(seed_index / 2) <= aes_cipher_s(79 downto 0);
                            else
                                seed_ivs_s(seed_index / 2) <= aes_cipher_s(79 downto 0);
                            end if;

                            -- check if all seed blocks have been generated, if not continue generating the next block, if yes transition to loading the Trivium bank with the generated seeds
                            if seed_index = AES_SEED_BLOCKS_C - 1 then
                                state <= TRIVIUM_LOAD;
                            else
                                seed_index <= seed_index + 1;
                                counter_reg <= counter_reg + 1;
                                state <= AES_LOAD;
                            end if;
                        end if;

                    -- TRIVIUM_LOAD state: signals the Trivium bank to load the generated keys and IVs, then transitions to TRIVIUM_WARMUP to wait for the Trivium generators to warm up and produce valid random numbers
                    when TRIVIUM_LOAD =>
                        busy <= '1';
                        load_rows_s <= '1';
                        state <= TRIVIUM_WARMUP;

                    -- TRIVIUM_WARMUP state: waits for the Trivium generators to warm up and produce valid random numbers, then transitions to READY
                    when TRIVIUM_WARMUP =>
                        busy <= '1';
                        if all_valid_s = '1' then
                            state <= READY;
                        end if;

                    -- READY state: the generator is ready for use, the random numbers from the Trivium bank are valid and can be used for the percolation simulation, 
                    -- the busy signal is deasserted to indicate that the generator is ready, remains in this state until reset (each clock cycle new random numbers are generated and output from the Trivium bank, but the seeding process is complete and the generator is ready for use)
                    when READY =>
                        busy <= '0';
                end case;
            end if;
        end if;
    end process;

    -- the outputs from the Trivium bank are assigned to the entity outputs, allowing the generated random numbers, validity masks, and site open flags to be used by the percolation simulation
    -- valid_mask is propagated for debugging purposes, as is the all_valid signal
    words_out <= words_s;
    valid_mask <= valid_s;
    site_open <= open_s;
    all_valid <= all_valid_s;
end architecture rtl;