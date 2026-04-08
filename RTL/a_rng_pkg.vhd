library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rng_pkg is
    constant N_ROWS : integer := 64;
    constant KEY_WIDTH : integer := 80;
    constant IV_WIDTH : integer := 80;
    constant WORD_WIDTH : integer := 32;
    constant AES_BLOCK_WIDTH : integer := 128;
    constant AES_SEED_BLOCKS : integer := 128;
    constant TRIVIUM_WARMUP_CYCLES : integer := 1152;

    subtype aes_block_t is std_logic_vector(AES_BLOCK_WIDTH - 1 downto 0);
    subtype key_t is std_logic_vector(KEY_WIDTH - 1 downto 0);
    subtype iv_t is std_logic_vector(IV_WIDTH - 1 downto 0);
    subtype word_t is std_logic_vector(WORD_WIDTH - 1 downto 0);

    type key_array_t is array (0 to N_ROWS - 1) of key_t;
    type iv_array_t is array (0 to N_ROWS - 1) of iv_t;
    type word_array_t is array (0 to N_ROWS - 1) of word_t;
    type flag_array_t is array (0 to N_ROWS - 1) of std_logic;

    function and_reduce(flags : flag_array_t) return std_logic;
end package rng_pkg;

package body rng_pkg is
    function and_reduce(flags : flag_array_t) return std_logic is
        variable result : std_logic := '1';
    begin
        for index in flags'range loop
            result := result and flags(index);
        end loop;
        return result;
    end function;
end package body rng_pkg;