-- UART Receiver (modular)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
    Port (
        Clk        : in  std_logic;
        Rst        : in  std_logic; -- active low
        uart_rx_i  : in  std_logic;
        baud_tick  : in  std_logic; -- single cycle
        half_tick  : in  std_logic; -- single cycle at mid-bit
        rx_data    : out std_logic_vector(7 downto 0);
        rx_valid   : out std_logic
    );
end uart_rx;

architecture Behavioral of uart_rx is
    type state_type is (IDLE, START, DATA, STOP);
    signal state      : state_type := IDLE;
    signal rx_sync_0  : std_logic := '1';
    signal rx_sync_1  : std_logic := '1';
    signal rx_prev    : std_logic := '1';
    signal shift_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_index  : integer range 0 to 7 := 0;
    signal rx_valid_s : std_logic := '0';
    signal rx_data_s  : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Synchronize RX to local clock domain
    sync_proc : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                rx_sync_0 <= '1';
                rx_sync_1 <= '1';
                rx_prev   <= '1';
            else
                rx_sync_0 <= uart_rx_i;
                rx_sync_1 <= rx_sync_0;
                rx_prev   <= rx_sync_1;
            end if;
        end if;
    end process;

    uart_rx_proc : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state <= IDLE;
                rx_valid_s <= '0';
                shift_reg <= (others => '0');
                bit_index <= 0;
                rx_data_s <= (others => '0');
            else
                rx_valid_s <= '0'; -- default
                case state is
                    when IDLE =>
                        -- detect falling edge (= start bit)
                        if rx_prev = '1' and rx_sync_1 = '0' then
                            state <= START;
                        end if;

                    when START =>
                        -- wait for half_tick to center sampling
                        if half_tick = '1' then
                            if rx_sync_1 = '0' then
                                bit_index <= 0;
                                state <= DATA;
                            else
                                state <= IDLE;
                            end if;
                        end if;

                    when DATA =>
                        if baud_tick = '1' then
                            shift_reg(bit_index) <= rx_sync_1;
                            if bit_index = 7 then
                                state <= STOP;
                            else
                                bit_index <= bit_index + 1;
                            end if;
                        end if;

                    when STOP =>
                        if baud_tick = '1' then
                            -- sample stop bit
                            if rx_sync_1 = '1' then
                                rx_data_s <= shift_reg;
                                rx_valid_s <= '1'; -- one-cycle pulse
                            end if;
                            state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

    rx_data <= rx_data_s;
    rx_valid <= rx_valid_s;

end Behavioral;