----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/08/2026 11:37:04 AM
-- Design Name: 
-- Module Name: tb_rng_double - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity tb_rng_double is
--  Port ( );
end tb_rng_double;

architecture Behavioral of tb_rng_double is

signal CLK100MHZ    : std_logic := '0';
signal rng_data     : std_logic_vector(127 downto 0);
signal rng_valid    : std_logic := '0';
-- signal site_occup   : std_logic_vector(15 downto 0) := (others => '0');
signal passed       : integer range 0 to 256 := 0;
signal tryed        : integer range 0 to 256  := 0;
-- constant p_threshold_byte : integer range 0 to 256  := 152;
constant p_threshold_byte : std_logic_vector := x"97BB2FEC"; -- hexadecimal 32 bit threshold

signal rst          : std_logic := '0'; -- reset, active high
signal reseed       : std_logic := '0'; -- reset, active high
signal new_key      : std_logic_vector(79 downto 0);
signal new_iv       : std_logic_vector(79 downto 0);
signal request      : std_logic := '0'; -- high while generating

signal out_valid    : std_logic := '0'; -- high when usable
signal t_rng_data   : std_logic_vector(31 downto 0);

signal done_key     : std_logic := '0';
signal done_iv      : std_logic := '0';
signal request_seed : std_logic := '0';


signal burned       : std_logic := '0';

constant clk_period : time := 10 ns;

begin

CLK100MHZ <= not CLK100MHZ after clk_period/2;

prng : entity work.aes_ctr_prng
    generic map (G_KEY => x"deadbeefcafebabe0123456789abcdef")
    port map (
                clk => CLK100MHZ,
                rng_valid => rng_valid, 
                rng_data => rng_data);

rng : entity work.rng_trivium
    generic map (
        -- Number of output bits per clock cycle.
        -- Must be a power of two: either 1, 2, 4, 8, 16, 32 or 64.
        num_bits => 32,

        -- Default key.
        init_key => x"abcdefabcdefabcdefab",

        -- Default initialization vector.
        init_iv => x"efabcdefabcdefabcdef" )

    port map (

        -- Clock, rising edge active.
        clk => CLK100MHZ, 

        -- Synchronous reset, active high.
        rst => rst,

        -- High to request re-seeding of the generator.
        reseed => reseed,

        -- New key value (must be valid when reseed = '1').
        newkey => new_key,

        -- New initialization vector (must be valid when reseed = '1').
        newiv => new_iv,

        -- High when the user accepts the current random data word
        -- and requests new random data for the next clock cycle.
        out_ready => request, 

        -- High when valid random data is available on the output.
        -- This signal is low during the first (1152/num_bits) clock cycles
        -- after reset and after re-seeding, and high in all other cases.
        out_valid => out_valid,

        -- Random output data (valid when out_valid = '1').
        -- A new random word appears after every rising clock edge
        -- where out_ready = '1'.
        out_data => t_rng_data );

process(CLK100MHZ)
begin
if request_seed = '1' then 
    if rising_edge(CLK100MHZ) and rng_valid = '1' then
        if done_key = '0' then
            new_key <= rng_data(127 downto 48);
            done_key <= '1';
            done_iv <= '0';
        else
            new_iv <= rng_data(127 downto 48);
            done_key <= '0';
            done_iv <= '1';
        end if;
    end if;
end if;

if rising_edge(CLK100MHZ) and out_valid = '1' then
--if rising_edge(CLK100MHZ) and out_valid = '1' and burned = '1' then
   tryed <= tryed + 1;
   if ( unsigned(t_rng_data) < unsigned(p_threshold_byte) ) then
        passed <= passed + 1;
   end if;
end if;

end process;

simulation : process
begin
    request_seed <= '1';
    wait until (done_iv = '1');
    request_seed <= '0';
    reseed <= '1';
    wait for 20 ns;
    reseed <= '0';
    request <= '1';
    wait;
end process;



end Behavioral;
