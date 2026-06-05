-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: rng_pkg (package)
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--
-- -------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- package to handle AES and Trivium related types and constants for the RNG design
package rng_pkg is
    constant KEY_WIDTH : integer := 80;                 -- Trivium key width
    constant IV_WIDTH : integer := 80;                  -- Trivium initialization vector width
    constant WORD_WIDTH : integer := 32;                -- Word width (size of fixed point numbers)
    constant AES_BLOCK_WIDTH : integer := 128;          -- AES block width
    constant TRIVIUM_WARMUP_CYCLES : integer := 1152;   -- Trivium warm-up cycles

    subtype aes_block_t is std_logic_vector(AES_BLOCK_WIDTH - 1 downto 0);  -- AES output block type
    subtype key_t is std_logic_vector(KEY_WIDTH - 1 downto 0);              -- Trivium key type
    subtype iv_t is std_logic_vector(IV_WIDTH - 1 downto 0);                -- Trivium IV type
    subtype word_t is std_logic_vector(WORD_WIDTH - 1 downto 0);            -- Word type for fixed point numbers (Trivium output): 
                                                                            -- the number is intrepreted as 32 bits for the fractional part, so the probability value is between 0 and 1

    type key_array_t is array (natural range <>) of key_t;      -- array type for storing multiple Trivium keys (used for seeding multiple rows)
    type iv_array_t is array (natural range <>) of iv_t;        -- array type for storing multiple Trivium IVs (used for seeding multiple rows)
    type word_array_t is array (natural range <>) of word_t;    -- array type for storing multiple output words (used for outputting multiple random numbers)
    type flag_array_t is array (natural range <>) of std_logic; -- array type for storing validity and site open flags for multiple rows, used to define and reduce function for checking if all rows are valid or open

    function and_reduce(flags : flag_array_t) return std_logic; -- function to perform AND reduction on an array of flags, used to determine if all rows are valid or open
end package rng_pkg;

-- package body to implement the and_reduce function for checking if all rows are valid or open
package body rng_pkg is
    function and_reduce(flags : flag_array_t) return std_logic is
        variable result : std_logic := '1';
    begin
        for index in flags'range loop
            result := result and flags(index); -- perform AND reduction across all flags in the array
        end loop;
        return result;
    end function;
end package body rng_pkg;