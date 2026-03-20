-- UART Transmitter
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    Port (
        Clk       : in  std_logic;
        Rst       : in  std_logic; -- active low
        baud_tick : in  std_logic;
        tx_start  : in  std_logic; -- pulse to start
        tx_data   : in  std_logic_vector(7 downto 0);
        tx_busy   : out std_logic;
        uart_tx_o : out std_logic
    );
end uart_tx;

architecture Behavioral of uart_tx is
    type state_type is (IDLE, START, DATA, STOP);
    signal state     : state_type := IDLE;
    signal bit_index : integer range 0 to 7 := 0;
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal busy_s    : std_logic := '0';
    signal tx_o_s     : std_logic := '1';
begin

    uart_proc: process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state     <= IDLE;
                bit_index <= 0;
                shift_reg <= (others => '0');
                busy_s    <= '0';
                tx_o_s    <= '1';
            else
                case state is
                    when IDLE =>
                        tx_o_s <= '1';
                        busy_s <= '0';
                        if tx_start = '1' then
                            shift_reg <= tx_data;
                            busy_s    <= '1';
                            bit_index <= 0;
                            state     <= START;
                        end if;

                    when START =>
                        if baud_tick = '1' then
                            tx_o_s <= '0'; -- start bit
                            state  <= DATA;
                        end if;

                    when DATA =>
                        if baud_tick = '1' then
                            tx_o_s <= shift_reg(bit_index);
                            if bit_index = 7 then
                                state <= STOP;
                            else
                                bit_index <= bit_index + 1;
                            end if;
                        end if;

                    when STOP =>
                        if baud_tick = '1' then
                            tx_o_s <= '1'; -- stop bit
                            busy_s  <= '0';
                            state   <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

    tx_busy   <= busy_s;
    uart_tx_o <= tx_o_s;

end Behavioral;
