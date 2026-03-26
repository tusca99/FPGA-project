library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_msg_tx is
    generic (
        N_BYTES   : positive := 8
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic; -- active low
        baud_tick : in  std_logic;
        msg_start : in  std_logic;
        msg_data  : in  std_logic_vector(N_BYTES*8-1 downto 0);
        busy      : out std_logic;
        uart_tx_o : out std_logic
    );
end uart_msg_tx;

architecture Behavioral of uart_msg_tx is
    signal tx_start_s  : std_logic := '0';
    signal tx_busy_s   : std_logic := '0';
    signal tx_data_s   : std_logic_vector(7 downto 0) := (others => '0');

    type state_t is (IDLE, LOAD, WAIT_TX, NEXT_BYTE);
    signal state : state_t := IDLE;
    signal byte_idx : integer range 0 to N_BYTES := 0;
    signal msg_reg  : std_logic_vector(N_BYTES*8-1 downto 0) := (others => '0');
    signal start_prev : std_logic := '0';

begin

    tx_inst : entity work.uart_tx
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick,
            tx_start  => tx_start_s,
            tx_data   => tx_data_s,
            tx_busy   => tx_busy_s,
            uart_tx_o => uart_tx_o
        );

    process(Clk)
        variable byte_lo : integer;
        variable byte_hi : integer;
        variable packed_byte : integer;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state <= IDLE;
                byte_idx <= 0;
                msg_reg <= (others => '0');
                tx_start_s <= '0';
                tx_data_s <= (others => '0');
                start_prev <= '0';
            else
                tx_start_s <= '0';
                start_prev <= msg_start;

                case state is
                    when IDLE =>
                        byte_idx <= 0;
                        if msg_start = '1' and start_prev = '0' then
                            msg_reg <= msg_data;
                            state <= LOAD;
                        end if;

                    when LOAD =>
                        packed_byte := (N_BYTES - 1) - byte_idx;
                        byte_lo := packed_byte * 8;
                        byte_hi := byte_lo + 7;
                        tx_data_s <= msg_reg(byte_hi downto byte_lo);
                        tx_start_s <= '1';
                        state <= WAIT_TX;

                    when WAIT_TX =>
                        if tx_busy_s = '1' then
                            state <= NEXT_BYTE;
                        end if;

                    when NEXT_BYTE =>
                        if tx_busy_s = '0' then
                            if byte_idx = N_BYTES - 1 then
                                state <= IDLE;
                            else
                                byte_idx <= byte_idx + 1;
                                state <= LOAD;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    busy <= '1' when state /= IDLE else '0';

end Behavioral;
