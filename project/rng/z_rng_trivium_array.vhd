library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rng_pkg.all;

entity trivium_array is
    generic (
        N_ROWS_G     : positive := 32;
        GROUP_SIZE_G : positive := 4
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        load       : in  std_logic;
        threshold  : in  std_logic_vector(31 downto 0);
        keys       : in  key_array_t(0 to N_ROWS_G - 1);
        ivs        : in  iv_array_t(0 to N_ROWS_G - 1);
        words_out  : out word_array_t(0 to N_ROWS_G - 1);
        valid_mask : out flag_array_t(0 to N_ROWS_G - 1);
        site_open  : out flag_array_t(0 to N_ROWS_G - 1);
        all_valid  : out std_logic
    );
end entity trivium_array;

architecture rtl of trivium_array is
    constant GROUP_SIZE_C : integer := GROUP_SIZE_G;
    constant NUM_GROUPS_C : integer := N_ROWS_G / GROUP_SIZE_C;

    signal row_words_s : word_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));
    signal row_valid_s : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal row_open_s  : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');

    signal rst_group  : std_logic_vector(NUM_GROUPS_C - 1 downto 0) := (others => '0');
    signal load_group : std_logic_vector(NUM_GROUPS_C - 1 downto 0) := (others => '0');
    signal threshold_dup : std_logic_vector(31 downto 0) := (others => '0');

    attribute KEEP : string;
    attribute KEEP of rst_group     : signal is "true";
    attribute KEEP of load_group    : signal is "true";
    attribute KEEP of threshold_dup : signal is "true";

    attribute MAX_FANOUT : integer;
    attribute MAX_FANOUT of rst_group     : signal is 32;
    attribute MAX_FANOUT of load_group    : signal is 32;
    attribute MAX_FANOUT of threshold_dup : signal is 16;
begin
    rst_group   <= (others => rst);
    load_group  <= (others => load);
    threshold_dup <= threshold;

    gen_rows : for index in 0 to N_ROWS_G - 1 generate
        constant GROUP_IDX_C : integer := index / GROUP_SIZE_C;
    begin
        row_rng : entity work.rng_trivium
            generic map (
                num_bits => WORD_WIDTH,
                init_key  => (others => '0'),
                init_iv   => (others => '0')
            )
            port map (
                clk       => clk,
                rst       => rst_group(GROUP_IDX_C),
                reseed    => load_group(GROUP_IDX_C),
                newkey    => keys(index),
                newiv     => ivs(index),
                out_ready => '1',
                out_valid => row_valid_s(index),
                out_data  => row_words_s(index)
            );

        row_open_s(index) <= '1'
            when row_valid_s(index) = '1' and unsigned(row_words_s(index)) < unsigned(threshold_dup)
            else '0';
    end generate;

    words_out <= row_words_s;
    valid_mask <= row_valid_s;
    site_open <= row_open_s;
    all_valid <= and_reduce(row_valid_s);
end architecture rtl;