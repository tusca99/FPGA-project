-- -------------------------------------------------------------------------------------------
-- Students Names: Leonardo Pieripolli, Alessio Tuscano 
-- Module Name: uart_rx
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

-- This module implements a UART receiver that receives 8 data bits, 1 start bit, and 1 stop bit.
-- It samples the uart_rx_i line at the specified baud rate to reconstruct received bytes.
entity uart_rx is
    generic (
        CLK_FREQ  : integer := 100_000_000;             -- machine clock frequency (Hz)
        BAUD_RATE : integer := 115200                   -- default baud rate (bits per second)
    );
    Port (
        Clk        : in  std_logic;
        Rst        : in  std_logic;                     -- active low
        uart_rx_i  : in  std_logic;                     -- UART receive line (idle high)
        rx_data    : out std_logic_vector(7 downto 0);  -- 8-bit data output for received byte
        rx_valid   : out std_logic                      -- high for one cycle when a new byte is received and valid on rx_data
    );
end uart_rx;

architecture Behavioral of uart_rx is
    -- To avoid metastability issues, we will synchronize the asynchronous uart_rx_i signal to the local clock domain using a two-stage synchronizer.
    -- Using an external baudrate generator (baud_gen) to create a baud_tick signal may disalign the phase of the baud tick with the actual transitions on uart_rx_i.
    constant BIT_CLKS      : integer := CLK_FREQ / BAUD_RATE;   -- number of clock cycles per bit period
    constant HALF_BIT_CLKS : integer := BIT_CLKS / 2;           -- number of clock cycles for half a bit period (used for sampling in the middle of the bit)

    -- State machine states for UART reception
    type state_type is (IDLE, START, DATA, STOP);
    signal state      : state_type := IDLE;
    signal rx_sync_0  : std_logic := '1';                                   -- first stage of synchronizer for uart_rx_i, hold the previous value to detect edges
    signal rx_sync_1  : std_logic := '1';                                   -- second stage of synchronizer for uart_rx_i, used for actual processing
    signal rx_prev    : std_logic := '1';                                   -- previous value of uart_rx_i, used to detect edges
    signal shift_reg  : std_logic_vector(7 downto 0) := (others => '0');    -- shift register to hold incoming bits during reception
    signal bit_index  : integer range 0 to 7 := 0;                          -- index for bits being received
    signal rx_valid_s : std_logic := '0';                                   -- signal to indicate when a new byte has been received and is valid on rx_data
    signal rx_data_s  : std_logic_vector(7 downto 0) := (others => '0');    -- signal to hold the final received byte when it's ready to be output
    signal sample_count : integer range 0 to BIT_CLKS := 0;                 -- counter to track when to sample the uart_rx_i line based on the baud rate timing

begin

    -- Synchronize RX to local clock domain
    sync_proc : process(Clk)
    begin
        if rising_edge(Clk) then
            -- reset is active LOW, initialize synchronizer outputs to idle state (high for UART)
            if Rst = '0' then
                rx_sync_0 <= '1';
                rx_sync_1 <= '1';
                rx_prev   <= '1';
            else
            -- continuously sample the uart_rx_i line and shift it through the synchronizer stages to avoid metastability.
                rx_sync_0 <= uart_rx_i;
                rx_sync_1 <= rx_sync_0;
                rx_prev   <= rx_sync_1;
            end if;
        end if;
    end process;

    -- UART reception state machine
    uart_rx_proc : process(Clk)
    begin
        if rising_edge(Clk) then
            -- reset is active LOW, reset state machine to IDLE and outputs to initial conditions
            if Rst = '0' then
                state <= IDLE;
                rx_valid_s <= '0';
                shift_reg <= (others => '0');
                bit_index <= 0;
                rx_data_s <= (others => '0');
                sample_count <= 0;
            else
                rx_valid_s <= '0';      -- active high, one-cycle pulse when a new byte is received and valid on rx_data
                case state is
                    -- In IDLE state, wait for a falling edge on the synchronized RX line (start bit). 
                    -- When detected, start counting to sample in the middle of the start bit.
                    when IDLE =>
                        -- detect falling edge (= start bit)
                        if rx_prev = '1' and rx_sync_1 = '0' then
                            sample_count <= HALF_BIT_CLKS;
                            state <= START;
                        end if;

                    when START =>
                        -- wait half a bit and re-check the start bit in the middle
                        if sample_count = 0 then
                            -- if the line is still low, we have a valid start bit, so we can proceed to receive data bits.
                            if rx_sync_1 = '0' then
                                bit_index <= 0;
                                sample_count <= BIT_CLKS - 1; -- set up to sample the first data bit after one full bit period
                                state <= DATA;
                            else
                            -- if the line is not low, this was a false start bit (noise), so we return to IDLE and wait for the next falling edge.
                                state <= IDLE;
                            end if;
                        else
                            -- count down to the middle of the start bit
                            sample_count <= sample_count - 1;
                        end if;
                    
                    -- In DATA state, we will sample the RX line at the baud rate timing to reconstruct the received byte.
                    when DATA =>
                        -- wait for the next sample point to sample each data bit.
                        if sample_count = 0 then
                            shift_reg(bit_index) <= rx_sync_1;
                            -- if received all 8 bits, move to STOP state to wait for the stop bit. 
                            -- Otherwise, set up to sample the next data bit after one full bit period.
                            if bit_index = 7 then
                                sample_count <= BIT_CLKS - 1;   -- set up to sample the stop bit after one full bit period
                                state <= STOP;
                            else
                                bit_index <= bit_index + 1;
                                sample_count <= BIT_CLKS - 1;  -- set up to sample the next data bit after one full bit period
                            end if;
                        else
                            -- count down to the next data bit sample point
                            sample_count <= sample_count - 1;
                        end if;

                    -- In STOP state, we will sample the RX line at the baud rate timing to check for a valid stop bit (should be high).
                    when STOP =>
                        if sample_count = 0 then
                            -- sample stop bit
                            if rx_sync_1 = '0' then
                                null;   -- if the stop bit is not high, we don't output the received data nor generate a valid pulse.
                            else
                                rx_data_s <= shift_reg; -- pass the received byte to the output register
                                rx_valid_s <= '1';      -- one-cycle pulse
                            end if;
                            state <= IDLE;
                        else
                            -- count down to sample stop bit
                            sample_count <= sample_count - 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

    rx_data <= rx_data_s;
    rx_valid <= rx_valid_s;

end Behavioral;