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
    signal BfsStepCount : std_logic_vector(31 downto 0);
    signal Done         : std_logic;

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
            BfsStepCount => BfsStepCount,
            Done => Done
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
        CfgP <= x"970A3D70"; -- p ~= 0.59 in UQ32
        CfgSeed <= x"12345678";
        CfgRuns <= x"00000010"; -- 16 runs
        CfgInit <= '1';
        wait for 10 ns;
        CfgInit <= '0';

        RunEn <= '1';
        for cycle_index in 0 to 1_000_000 loop
            wait until rising_edge(Clk);
            exit when Done = '1';
        end loop;
        RunEn <= '0';

        assert Done = '1'
            report "Percolation core did not assert Done" severity failure;

        assert to_integer(unsigned(StepCount)) = 16
            report "Percolation core did not complete the requested 16 runs" severity failure;

        assert to_integer(unsigned(TotalOccupied)) > 0
            report "Percolation core reported zero occupied sites across the batch" severity failure;

        report "StepCount=" & integer'image(to_integer(unsigned(StepCount))) severity note;
        report "SpanningCount=" & integer'image(to_integer(unsigned(SpanningCount))) severity note;
        report "TotalOccupied=" & integer'image(to_integer(unsigned(TotalOccupied))) severity note;
        report "BfsStepCount=" & integer'image(to_integer(unsigned(BfsStepCount))) severity note;

        wait;
    end process;

end architecture;
