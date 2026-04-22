library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rng_pkg.all;

entity trivium_array is
    generic (
        N_ROWS_G : positive := 64
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
    signal row_words_s : word_array_t(0 to N_ROWS_G - 1) := (others => (others => '0'));
    signal row_valid_s : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
    signal row_open_s  : flag_array_t(0 to N_ROWS_G - 1) := (others => '0');
begin
    gen_rows : for index in 0 to N_ROWS_G - 1 generate
        row_rng : entity work.rng_trivium
            generic map (
                num_bits => WORD_WIDTH,
                init_key  => (others => '0'),
                init_iv   => (others => '0')
            )
            port map (
                clk       => clk,
                rst       => rst,
                reseed    => load,
                newkey    => keys(index),
                newiv     => ivs(index),
                out_ready => '1',
                out_valid => row_valid_s(index),
                out_data  => row_words_s(index)
            );

        row_open_s(index) <= '1'
            when row_valid_s(index) = '1' and unsigned(row_words_s(index)) < unsigned(threshold)
            else '0';
    end generate;

    words_out <= row_words_s;
    valid_mask <= row_valid_s;
    site_open <= row_open_s;
    all_valid <= and_reduce(row_valid_s);
end architecture rtl;