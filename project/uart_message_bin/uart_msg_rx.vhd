library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_msg_rx is
    generic (
        CLK_FREQ  : integer := 100_000_000;
        BAUD_RATE : integer := 115200;
        N_BYTES   : positive := 8
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic; -- active low
        uart_rx_i : in  std_logic;
        msg_data  : out std_logic_vector(N_BYTES*8-1 downto 0);
        msg_valid : out std_logic;
        busy      : out std_logic
    );
end uart_msg_rx;

architecture Behavioral of uart_msg_rx is
    signal rx_data_s   : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid_s  : std_logic := '0';
    signal rx_valid_prev_s : std_logic := '0';

    signal msg_reg     : std_logic_vector(N_BYTES*8-1 downto 0) := (others => '0');
    signal byte_idx    : integer range 0 to N_BYTES-1 := 0;
    signal msg_valid_s : std_logic := '0';
    signal receiving_s : std_logic := '0';

begin

    rx_inst : entity work.uart_rx
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            uart_rx_i => uart_rx_i,
            rx_data   => rx_data_s,
            rx_valid  => rx_valid_s
        );

    process(Clk)
        variable byte_lo : integer;
        variable byte_hi : integer;
        variable packed_byte : integer;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                msg_reg <= (others => '0');
                byte_idx <= 0;
                msg_valid_s <= '0';
                receiving_s <= '0';
                rx_valid_prev_s <= '0';
            else
                msg_valid_s <= '0';

                if rx_valid_s = '1' and rx_valid_prev_s = '0' then
                    receiving_s <= '1';
                    packed_byte := (N_BYTES - 1) - byte_idx;
                    byte_lo := packed_byte * 8;
                    byte_hi := byte_lo + 7;
                    msg_reg(byte_hi downto byte_lo) <= rx_data_s;

                    if byte_idx = N_BYTES - 1 then
                        msg_valid_s <= '1';
                        byte_idx <= 0;
                        receiving_s <= '0';
                    else
                        byte_idx <= byte_idx + 1;
                    end if;
                end if;

                rx_valid_prev_s <= rx_valid_s;
            end if;
        end if;
    end process;

    msg_data <= msg_reg;
    msg_valid <= msg_valid_s;
    busy <= receiving_s;

end Behavioral;
