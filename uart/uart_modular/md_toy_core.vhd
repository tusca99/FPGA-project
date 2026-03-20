library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Minimal “MD toy” core (single-clock, 100 MHz friendly).
-- Purpose: provide a replaceable data-plane driven by the existing UART control-plane.
--
-- Semantics:
-- - When RunEn='1', performs 1 step per clock.
-- - StepAddValid adds StepAddCount to a pending counter; when pending>0 it also performs steps.
-- - If pending>0, each performed step decrements pending by 1.
--
-- State model (toy): two signed 16-bit positions updated by two signed 16-bit velocities.
-- Metric: squared distance (pos1-pos0)^2 (32-bit).

entity md_toy_core is
    port (
        Clk          : in  std_logic;
        Rst          : in  std_logic; -- active low

        RunEn        : in  std_logic;
        StepAddValid : in  std_logic;
        StepAddCount : in  std_logic_vector(31 downto 0);

        -- Config (from regfile)
        CfgVel0      : in  std_logic_vector(15 downto 0);
        CfgVel1      : in  std_logic_vector(15 downto 0);
        CfgInitPos0  : in  std_logic_vector(15 downto 0);
        CfgInitPos1  : in  std_logic_vector(15 downto 0);
        CfgInit      : in  std_logic; -- pulse to (re)initialize positions

        -- State/metrics
        StepCount    : out std_logic_vector(31 downto 0);
        PendingSteps : out std_logic_vector(31 downto 0);
        Pos0         : out std_logic_vector(15 downto 0);
        Pos1         : out std_logic_vector(15 downto 0);
        Dist2        : out std_logic_vector(31 downto 0)
    );
end md_toy_core;

architecture Behavioral of md_toy_core is

    signal step_count_u : unsigned(31 downto 0) := (others => '0');
    signal pending_u    : unsigned(31 downto 0) := (others => '0');

    signal pos0_s : signed(15 downto 0) := (others => '0');
    signal pos1_s : signed(15 downto 0) := (others => '0');

    signal vel0_s : signed(15 downto 0);
    signal vel1_s : signed(15 downto 0);

    signal diff_s : signed(15 downto 0);
    signal dist2_u : unsigned(31 downto 0) := (others => '0');

begin

    vel0_s <= signed(CfgVel0);
    vel1_s <= signed(CfgVel1);

    diff_s <= pos1_s - pos0_s;

    process(Clk)
        variable do_step       : std_logic;
        variable diff32        : signed(31 downto 0);
        variable mult          : signed(31 downto 0);
        variable next_pending  : unsigned(31 downto 0);
        variable next_step_cnt : unsigned(31 downto 0);
        variable next_pos0     : signed(15 downto 0);
        variable next_pos1     : signed(15 downto 0);
        variable next_dist2    : unsigned(31 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                step_count_u <= (others => '0');
                pending_u <= (others => '0');
                pos0_s <= (others => '0');
                pos1_s <= (others => '0');
                dist2_u <= (others => '0');
            else
                -- compute next-state defaults
                next_pending  := pending_u;
                next_step_cnt := step_count_u;
                next_pos0     := pos0_s;
                next_pos1     := pos1_s;
                next_dist2    := dist2_u;

                -- optional re-init of positions (has priority; no step on same cycle)
                if CfgInit = '1' then
                    next_pos0 := signed(CfgInitPos0);
                    next_pos1 := signed(CfgInitPos1);
                else
                    -- accumulate requested manual steps
                    if StepAddValid = '1' then
                        next_pending := next_pending + unsigned(StepAddCount);
                    end if;

                    do_step := '0';
                    if RunEn = '1' then
                        do_step := '1';
                    elsif next_pending /= 0 then
                        do_step := '1';
                    end if;

                    if do_step = '1' then
                        next_pos0 := next_pos0 + vel0_s;
                        next_pos1 := next_pos1 + vel1_s;

                        next_step_cnt := next_step_cnt + 1;
                        if next_pending /= 0 then
                            next_pending := next_pending - 1;
                        end if;

                        diff32 := resize(next_pos1 - next_pos0, 32);
                        mult := diff32 * diff32;
                        next_dist2 := unsigned(mult);
                    end if;
                end if;

                pending_u    <= next_pending;
                step_count_u <= next_step_cnt;
                pos0_s       <= next_pos0;
                pos1_s       <= next_pos1;
                dist2_u      <= next_dist2;
            end if;
        end if;
    end process;

    StepCount    <= std_logic_vector(step_count_u);
    PendingSteps <= std_logic_vector(pending_u);
    Pos0         <= std_logic_vector(pos0_s);
    Pos1         <= std_logic_vector(pos1_s);
    Dist2        <= std_logic_vector(dist2_u);

end Behavioral;
