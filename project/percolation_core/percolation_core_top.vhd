library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity percolation_core_top is
    generic (
        N_ROWS_G : positive := 64;
        CFG_STEPS_BITS_G : positive := 32
    );
    port (
        Clk            : in std_logic;
        Rst            : in std_logic; -- active low

        RunEn          : in std_logic;
        StepAddValid   : in std_logic;
        StepAddCount   : in std_logic_vector(31 downto 0);

        CfgP           : in std_logic_vector(31 downto 0);
        CfgStepsPerRun : in unsigned(CFG_STEPS_BITS_G - 1 downto 0);
        CfgSeed        : in std_logic_vector(31 downto 0);
        CfgRuns        : in std_logic_vector(31 downto 0);
        CfgInit        : in std_logic;

        StepCount     : out std_logic_vector(31 downto 0);
        PendingSteps  : out std_logic_vector(31 downto 0);
        SpanningCount : out std_logic_vector(31 downto 0);
        TotalOccupied : out std_logic_vector(31 downto 0);
        RngBusy       : out std_logic;
        RngAllValid   : out std_logic;
        Done          : out std_logic
    );
end percolation_core_top;

architecture Behavioral of percolation_core_top is
begin
    core_inst : entity work.percolation_core
        generic map (
            N_ROWS_G => N_ROWS_G,
            CFG_STEPS_BITS_G => CFG_STEPS_BITS_G
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            RunEn         => RunEn,
            StepAddValid  => StepAddValid,
            StepAddCount  => StepAddCount,
            CfgP          => CfgP,
            CfgStepsPerRun => CfgStepsPerRun,
            CfgSeed       => CfgSeed,
            CfgRuns       => CfgRuns,
            CfgInit       => CfgInit,
            StepCount     => StepCount,
            PendingSteps  => PendingSteps,
            SpanningCount => SpanningCount,
            TotalOccupied => TotalOccupied,
            RngBusy       => RngBusy,
            RngAllValid   => RngAllValid,
            Done          => Done
        );
end Behavioral;