library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_ctr_prng is
    generic (
        G_KEY : std_logic_vector(127 downto 0) := (others => '0')
    );
    port (
        clk       : in  std_logic;
        rng_valid : out std_logic;
        rng_data  : out std_logic_vector(127 downto 0)
    );
end entity aes_ctr_prng;

architecture rtl of aes_ctr_prng is
    type state_t is (LOAD, RUN);

    signal state : state_t := LOAD;
    signal aes_rst_n : std_logic := '0';
    signal aes_plain_s : std_logic_vector(127 downto 0) := (others => '0');
    signal aes_cipher_s : std_logic_vector(127 downto 0) := (others => '0');
    signal aes_done_s : std_logic := '0';
    signal counter_reg : unsigned(127 downto 0) := (others => '0');
begin
    aes_inst : entity work.aes_enc
        port map (
            clk        => clk,
            rst        => aes_rst_n,
            key        => G_KEY,
            plaintext  => aes_plain_s,
            ciphertext => aes_cipher_s,
            done       => aes_done_s
        );

    process (clk)
    begin
        if rising_edge(clk) then
            rng_valid <= '0';

            case state is
                when LOAD =>
                    aes_rst_n <= '0';
                    aes_plain_s <= std_logic_vector(counter_reg);
                    state <= RUN;

                when RUN =>
                    aes_rst_n <= '1';
                    if aes_done_s = '1' then
                        rng_data <= aes_cipher_s;
                        rng_valid <= '1';
                        counter_reg <= counter_reg + 1;
                        state <= LOAD;
                    end if;
            end case;
        end if;
    end process;
end architecture rtl;