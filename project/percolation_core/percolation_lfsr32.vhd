library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_lfsr32 is
    port (
        Clk      : in  std_logic;
        Rst      : in  std_logic; -- active low
        Load     : in  std_logic;
        StepEn   : in  std_logic;
        SeedIn   : in  std_logic_vector(31 downto 0);
        StateOut : out std_logic_vector(31 downto 0)
    );
end percolation_lfsr32;

architecture Behavioral of percolation_lfsr32 is
    signal state_reg : std_logic_vector(31 downto 0) := (others => '1');
    constant ZERO_SEED : std_logic_vector(31 downto 0) := (others => '0');

    function lfsr_next(x : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable y      : std_logic_vector(31 downto 0);
        variable newbit : std_logic;
    begin
        newbit := x(31) xor x(21) xor x(1) xor x(0);
        y := x(30 downto 0) & newbit;
        return y;
    end function;

begin
    process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state_reg <= (others => '1');
            elsif Load = '1' then
                if SeedIn = ZERO_SEED then
                    state_reg <= (others => '1');
                else
                    state_reg <= SeedIn;
                end if;
            elsif StepEn = '1' then
                state_reg <= lfsr_next(state_reg);
            end if;
        end if;
    end process;

    StateOut <= state_reg;

end Behavioral;