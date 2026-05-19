library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rng_pkg.all;

entity tb_rng_hybrid is
end entity tb_rng_hybrid;

architecture behavioral of tb_rng_hybrid is
    constant CLK_PERIOD : time := 10 ns;
    constant MASTER_KEY_C : std_logic_vector(127 downto 0) := x"deadbeefcafebabe0123456789abcdef";
    constant RUN_TAG_C    : std_logic_vector(31 downto 0) := x"00000001";
    constant THRESHOLD_C  : std_logic_vector(31 downto 0) := x"97BB2FEC";

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal busy       : std_logic := '0';
    signal all_valid  : std_logic := '0';
    signal master_key_s : std_logic_vector(127 downto 0) := MASTER_KEY_C;
    signal run_tag_s    : std_logic_vector(31 downto 0) := RUN_TAG_C;
    signal threshold_s  : std_logic_vector(31 downto 0) := THRESHOLD_C;
    signal words_out  : word_array_t;
    signal valid_mask : flag_array_t;
    signal site_open  : flag_array_t;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.rng_hybrid_64
        port map (
            clk        => clk,
            rst        => rst,
            master_key => master_key_s,
            run_tag    => run_tag_s,
            threshold  => threshold_s,
            words_out  => words_out,
            valid_mask => valid_mask,
            site_open  => site_open,
            all_valid  => all_valid,
            busy       => busy
        );

    stimulus : process
        variable passed_count : integer := 0;
        variable tried_count : integer := 0;
    begin
        rst <= '1';
        wait for 50 ns;
        rst <= '0';
        wait for 50 ns;

        for timeout_cycles in 0 to 6000 loop
            wait until rising_edge(clk);
            exit when busy = '0' and all_valid = '1';
        end loop;

        assert busy = '0' and all_valid = '1'
            report "Hybrid RNG did not become ready" severity failure;

        for sample in 0 to 7 loop
            wait until rising_edge(clk);
            if all_valid = '1' then
                for row in 0 to N_ROWS - 1 loop
                    tried_count := tried_count + 1;
                    if site_open(row) = '1' then
                        passed_count := passed_count + 1;
                    end if;
                end loop;
            end if;
        end loop;

        assert tried_count > 0
            report "No valid RNG samples were observed" severity failure;

        assert passed_count > 0
            report "Comparator output never opened a site" severity failure;

        report "Hybrid RNG smoke test passed" severity note;
        report "Passed=" & integer'image(passed_count) severity note;
        report "Tried=" & integer'image(tried_count) severity note;
        wait;
    end process;
end architecture behavioral;