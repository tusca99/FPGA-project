library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rng_pkg.all;

entity rng_hybrid_64 is
    generic (
        N_ROWS_G : positive := 64
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        master_key : in  std_logic_vector(127 downto 0);
        run_tag    : in  std_logic_vector(31 downto 0);
        threshold  : in  std_logic_vector(31 downto 0);
        words_out  : out word_array_t(0 to N_ROWS_G - 1);
        valid_mask : out flag_array_t(0 to N_ROWS_G - 1);
        site_open  : out flag_array_t(0 to N_ROWS_G - 1);
        all_valid  : out std_logic;
        busy       : out std_logic
    );
end entity rng_hybrid_64;

architecture rtl of rng_hybrid_64 is
    type state_t is (IDLE, AES_LOAD, AES_RUN, TRIVIUM_LOAD, TRIVIUM_WARMUP, READY);

    signal state : state_t := IDLE;

    signal seed_keys_s : key_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));
    signal seed_ivs_s  : iv_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));

    signal aes_rst_n : std_logic := '1';
    signal aes_plain_s : std_logic_vector(127 downto 0) := (others => '0');
    signal aes_cipher_s : std_logic_vector(127 downto 0) := (others => '0');
    signal aes_done_s : std_logic := '0';

    signal load_rows_s : std_logic := '0';
    constant AES_SEED_BLOCKS_C : integer := 2 * N_ROWS_G;
    signal seed_index : integer range 0 to AES_SEED_BLOCKS_C := 0;
    signal counter_reg : unsigned(127 downto 0) := (others => '0');
    signal master_key_reg : std_logic_vector(127 downto 0) := (others => '0');

    signal words_s : word_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));
    signal valid_s : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal open_s : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal all_valid_s : std_logic := '0';

    function run_tag_to_counter(tag : std_logic_vector(31 downto 0)) return unsigned is
        variable result : unsigned(127 downto 0) := (others => '0');
    begin
        result(31 downto 0) := unsigned(tag);
        return result;
    end function;
begin
    aes_inst : entity work.aes_enc
        port map (
            clk        => clk,
            rst        => aes_rst_n,
            key        => master_key_reg,
            plaintext  => aes_plain_s,
            ciphertext => aes_cipher_s,
            done       => aes_done_s
        );

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
                load_rows_s <= '0';

                case state is
                    when IDLE =>
                        busy <= '1';
                        aes_rst_n <= '1';
                        master_key_reg <= master_key;
                        counter_reg <= run_tag_to_counter(run_tag);
                        seed_index <= 0;
                        state <= AES_LOAD;

                    when AES_LOAD =>
                        busy <= '1';
                        aes_rst_n <= '0';
                        aes_plain_s <= std_logic_vector(counter_reg);
                        state <= AES_RUN;

                    when AES_RUN =>
                        busy <= '1';
                        aes_rst_n <= '1';
                        if aes_done_s = '1' then
                            if (seed_index mod 2) = 0 then
                                seed_keys_s(seed_index / 2) <= aes_cipher_s(79 downto 0);
                            else
                                seed_ivs_s(seed_index / 2) <= aes_cipher_s(79 downto 0);
                            end if;

                            if seed_index = AES_SEED_BLOCKS_C - 1 then
                                state <= TRIVIUM_LOAD;
                            else
                                seed_index <= seed_index + 1;
                                counter_reg <= counter_reg + 1;
                                state <= AES_LOAD;
                            end if;
                        end if;

                    when TRIVIUM_LOAD =>
                        busy <= '1';
                        load_rows_s <= '1';
                        state <= TRIVIUM_WARMUP;

                    when TRIVIUM_WARMUP =>
                        busy <= '1';
                        if all_valid_s = '1' then
                            state <= READY;
                        end if;

                    when READY =>
                        busy <= '0';
                end case;
            end if;
        end if;
    end process;

    words_out <= words_s;
    valid_mask <= valid_s;
    site_open <= open_s;
    all_valid <= all_valid_s;
end architecture rtl;