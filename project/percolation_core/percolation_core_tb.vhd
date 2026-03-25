library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_core_tb is
end entity;

architecture Behavioral of percolation_core_tb is
    signal Clk          : std_logic := '0';
    signal Rst          : std_logic := '0';

    signal RunEn        : std_logic := '0';
    signal StepAddValid : std_logic := '0';
    signal StepAddCount : std_logic_vector(31 downto 0) := (others => '0');

    signal CfgP         : std_logic_vector(31 downto 0) := (others => '0');
    signal CfgGridSize  : std_logic_vector(15 downto 0) := (others => '0');
    signal CfgSeed      : std_logic_vector(31 downto 0) := (others => '0');
    signal CfgRuns      : std_logic_vector(31 downto 0) := (others => '0');
    signal CfgInit      : std_logic := '0';

    signal StepCount    : std_logic_vector(31 downto 0);
    signal PendingSteps : std_logic_vector(31 downto 0);
    signal SpanningCount: std_logic_vector(31 downto 0);
    signal TotalOccupied: std_logic_vector(31 downto 0);
    signal MeanOccupied : std_logic_vector(31 downto 0);

begin
    dut: entity work.percolation_core
        port map (
            Clk => Clk,
            Rst => Rst,
            RunEn => RunEn,
            StepAddValid => StepAddValid,
            StepAddCount => StepAddCount,
            CfgP => CfgP,
            CfgGridSize => CfgGridSize,
            CfgSeed => CfgSeed,
            CfgRuns => CfgRuns,
            CfgInit => CfgInit,
            StepCount => StepCount,
            PendingSteps => PendingSteps,
            SpanningCount => SpanningCount,
            TotalOccupied => TotalOccupied,
            MeanOccupied => MeanOccupied
        );

    clk_proc : process
    begin
        while true loop
            Clk <= '0';
            wait for 5 ns;
            Clk <= '1';
            wait for 5 ns;
        end loop;
    end process;

    stim_proc: process
    begin
        Rst <= '0';
        wait for 20 ns;
        Rst <= '1';

        CfgGridSize <= x"0008"; -- 8x8
        CfgP <= x"9999999A"; -- approx 0.6
        CfgSeed <= x"12345678";
        CfgRuns <= x"00000010"; -- 16 runs
        CfgInit <= '1';
        wait for 10 ns;
        CfgInit <= '0';

        RunEn <= '1';
        wait for 25000 ns;
        RunEn <= '0';

        assert to_integer(unsigned(StepCount)) > 0
            report "Percolation core failed to run any step" severity failure;

        report "StepCount=" & integer'image(to_integer(unsigned(StepCount))) severity note;
        report "SpanningCount=" & integer'image(to_integer(unsigned(SpanningCount))) severity note;
        report "TotalOccupied=" & integer'image(to_integer(unsigned(TotalOccupied))) severity note;

        wait;
    end process;

end architecture;
