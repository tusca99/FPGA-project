-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: uart_tx
-- Project Name: Percolation on FPGA
-- Target Devices: xc7a100tcsg324-1
-- Description: Exam project for Programmable Hardware Devices course at University of Padova.
-- 
-- Depenedencies:
--
-- -------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- This module implements a UART transmitter that sends 8 data bits, 1 start bit, and 1 stop bit.
-- It uses the baud_tick signal from the baud_gen module to time the transmission of each bit.
entity uart_tx is
    Port (
        Clk       : in  std_logic;
        Rst       : in  std_logic;                      -- active low
        baud_tick : in  std_logic;
        tx_start  : in  std_logic;                      -- pulse to start
        tx_data   : in  std_logic_vector(7 downto 0);   -- 8-bit data to transmit
        tx_busy   : out std_logic;                      -- high when transmission is in progress (including start and stop bits) - used by state machines to know when they can load new data
        uart_tx_o : out std_logic                       -- UART transmit line (idle high)
    );
end uart_tx;

architecture Behavioral of uart_tx is
    -- State machine states for UART transmission
    type state_type is (IDLE, START, DATA, STOP);
    signal state     : state_type := IDLE;
    signal bit_index : integer range 0 to 7 := 0;                       -- index for data bits being transmitted
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0'); -- shift register to hold data bits during transmission
    signal busy_s    : std_logic := '0';                                -- signal to indicate when transmission is in progress
    signal tx_o_s     : std_logic := '1';                               -- signal to control the UART transmit line
begin

    uart_proc: process(Clk)
    begin
        if rising_edge(Clk) then
            -- reset is active LOW, reset state machine and outputs to idle conditions
            if Rst = '0' then
                state     <= IDLE;
                bit_index <= 0;
                shift_reg <= (others => '0');
                busy_s    <= '0';
                tx_o_s    <= '1';
            else
                case state is
                    -- In IDLE state, wait for tx_start signal to begin transmission, keeping the transmit line high.
                    -- When tx_start is asserted, load the shift register with the data to transmit and move to START state.
                    when IDLE =>
                        tx_o_s <= '1';
                        busy_s <= '0';
                        if tx_start = '1' then
                            shift_reg <= tx_data;
                            busy_s    <= '1';
                            bit_index <= 0;
                            state     <= START;
                        end if;
                    -- In START state, wait for the baud_tick to assert, then send the start bit (0) and move to DATA state.
                    when START =>
                        if baud_tick = '1' then
                            tx_o_s <= '0';  -- start bit
                            state  <= DATA;
                        end if;
                    -- In DATA state, on each baud_tick, send the next data bit from the shift register. 
                    -- After sending all 8 bits, move to STOP state.
                    when DATA =>
                        if baud_tick = '1' then
                            tx_o_s <= shift_reg(bit_index);
                            if bit_index = 7 then
                                state <= STOP;
                            else
                                bit_index <= bit_index + 1;
                            end if;
                        end if;
                    -- In STOP state, wait for the baud_tick to assert, then send the stop bit (1), 
                    -- clear the busy signal, and return to IDLE state.
                    when STOP =>
                        if baud_tick = '1' then
                            tx_o_s <= '1';  -- stop bit
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