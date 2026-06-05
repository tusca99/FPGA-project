-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: percolation_core_tb
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--   - percolation_core.vhd
--
-- -------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_core_tb is
end entity;

-- Testbench for the percolation_core module. This testbench initializes the core with a specific configuration, starts a batch of runs, and waits for completion. 
-- It then checks that the core completed the expected number of runs and that it reported non-zero occupied sites, which are basic sanity checks to ensure the core is functioning. 
-- The testbench also reports the final statistics from the core for manual inspection.
architecture Behavioral of percolation_core_tb is
    constant N_ROWS_G    : positive := 64;
    signal Clk          : std_logic := '0';
    signal Rst          : std_logic := '0';

    signal RunEn        : std_logic := '0';
    signal StepAddValid : std_logic := '0';
    signal StepAddCount : std_logic_vector(31 downto 0) := (others => '0');

    signal CfgP          : std_logic_vector(31 downto 0) := (others => '0');
    signal CfgStepsPerRun: unsigned(31 downto 0) := (others => '0');
    signal CfgSeed       : std_logic_vector(31 downto 0) := (others => '0');
    signal CfgRuns       : std_logic_vector(31 downto 0) := (others => '0');
    signal CfgInit       : std_logic := '0';

    signal StepCount    : std_logic_vector(31 downto 0);
    signal SpanningCount: std_logic_vector(31 downto 0);
    signal TotalOccupied: std_logic_vector(31 downto 0);
    signal SpanningOccupied: std_logic_vector(31 downto 0);
    signal Done         : std_logic;

begin
    dut: entity work.percolation_core
        generic map (
            N_ROWS_G => N_ROWS_G
        )
        port map (
            Clk => Clk,
            Rst => Rst,
            RunEn => RunEn,
            StepAddValid => StepAddValid,
            StepAddCount => StepAddCount,
            CfgP => CfgP,
            CfgStepsPerRun => CfgStepsPerRun,
            CfgSeed => CfgSeed,
            CfgRuns => CfgRuns,
            CfgInit => CfgInit,
            StepCount => StepCount,
            SpanningCount => SpanningCount,
            TotalOccupied => TotalOccupied,
            SpanningOccupied => SpanningOccupied,
            Done => Done
        );

    clk_proc : process
    begin
        -- Generate a 100 MHz clock signal
        while true loop
            Clk <= '0';
            wait for 5 ns;
            Clk <= '1';
            wait for 5 ns;
        end loop;
    end process;

    stim_proc: process
    begin
        -- Apply reset and initial configuration
        Rst <= '0';
        wait for 20 ns;
        Rst <= '1';

        CfgStepsPerRun <= to_unsigned(64, 32);
        CfgP <= x"970A3D70";        -- p ~= 0.59 in UQ32
        CfgSeed <= x"12345678";     -- arbitrary seed value
        CfgRuns <= x"00000010";     -- 16 runs
        CfgInit <= '1';
        wait for 10 ns;
        CfgInit <= '0';

        -- RNG readiness signals are internal to the DUT; allow warmup delay
        wait for 100 ns;

        RunEn <= '1';
        for cycle_index in 0 to 1_000_000 loop
            wait until rising_edge(Clk);
            exit when Done = '1';
        end loop;
        RunEn <= '0';

        -- Check results after completion. We assert that Done is high, that we completed the expected number of runs, and that we had non-zero occupied sites across the batch. We also report the final statistics for manual inspection.
        assert Done = '1'
            report "Percolation core did not assert Done" severity failure;

        assert to_integer(unsigned(StepCount)) = 16
            report "Percolation core did not complete the requested 16 runs" severity failure;

        assert to_integer(unsigned(TotalOccupied)) > 0
            report "Percolation core reported zero occupied sites across the batch" severity failure;

        report "StepCount=" & integer'image(to_integer(unsigned(StepCount))) severity note;
        report "SpanningCount=" & integer'image(to_integer(unsigned(SpanningCount))) severity note;
        report "TotalOccupied=" & integer'image(to_integer(unsigned(TotalOccupied))) severity note;
        report "SpanningOccupied=" & integer'image(to_integer(unsigned(SpanningOccupied))) severity note;

        wait;
    end process;

end architecture;
