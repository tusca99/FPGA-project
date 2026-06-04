library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- This module implements a UART message transmitter that sends a multi-byte message over UART.
entity uart_msg_tx is
    generic (
        N_BYTES   : positive := 8       -- number of bytes in the message to transmit
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic;                              -- active low
        baud_tick : in  std_logic;                              -- pulse from baud_gen to time the transmission of each bit
        msg_start : in  std_logic;                              -- pulse to start transmitting the message. The message data should be stable at msg_data when this pulse is asserted.
        msg_data  : in  std_logic_vector(N_BYTES*8-1 downto 0); -- the multi-byte message to transmit, with byte 0 in the least significant bits and byte N-1 in the most significant bits
        busy      : out std_logic;                              -- high when transmission is in progress (including start and stop bits) - used by state machines to know when they can load new data
        uart_tx_o : out std_logic                               -- UART transmit line (idle high)
    );
end uart_msg_tx;

architecture Behavioral of uart_msg_tx is
    constant MSG_BITS : natural := N_BYTES * 8;     -- total number of bits in the message (useful for indexing)

    -- Signals to interface with the uart_tx module
    signal tx_start_s  : std_logic := '0';
    signal tx_busy_s   : std_logic := '0';
    signal tx_data_s   : std_logic_vector(7 downto 0) := (others => '0');

    -- State machine states for controlling the transmission of the multi-byte message
    type state_t is (IDLE, LOAD, WAIT_TX, NEXT_BYTE);
    signal state : state_t := IDLE;
    signal byte_idx : integer range 0 to N_BYTES := 0;
    signal msg_reg  : std_logic_vector(MSG_BITS-1 downto 0) := (others => '0'); -- register to hold the message being transmitted
    signal start_prev : std_logic := '0';                                       -- signal to hold the previous value of msg_start for edge detection

begin

    -- Instantiate the uart_tx module to handle the actual transmission of bytes over UART.
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
    begin
        if rising_edge(Clk) then
            -- reset is active LOW, reset state machine and outputs to idle conditions
            if Rst = '0' then
                state <= IDLE;
                byte_idx <= 0;
                msg_reg <= (others => '0');
                tx_start_s <= '0';
                tx_data_s <= (others => '0');
                start_prev <= '0';
            else
                -- By default, deassert tx_start_s. It will be pulsed for one cycle when we load a new byte to transmit.
                tx_start_s <= '0';
                -- We will detect the rising edge of msg_start to know when to start transmitting a new message.
                start_prev <= msg_start;

                case state is
                    -- In IDLE state, we wait for a rising edge on msg_start to begin the transmission process.
                    when IDLE =>
                        byte_idx <= 0;
                        -- When we see a rising edge on msg_start, we will load the message into a register and start the transmission process.
                        if msg_start = '1' and start_prev = '0' then
                            msg_reg <= msg_data;
                            state <= LOAD;
                        end if;

                    -- In LOAD state, we will load the next byte to transmit into tx_data_s and pulse tx_start_s to start the transmission of that byte.
                    when LOAD =>
                        -- We load the most significant byte of the message register first (byte N-1),
                        -- and then shift the register to bring the next byte to the most significant position for the next transmission.
                        tx_data_s <= msg_reg(MSG_BITS-1 downto MSG_BITS-8); 
                        tx_start_s <= '1';
                        state <= WAIT_TX;
                    
                    -- In WAIT_TX state, we wait for the uart_tx module to assert tx_busy_s, which indicates that it has started transmitting the byte.
                    -- This ensures that we don't load the next byte until the current byte has actually started transmitting, which is important for timing and to avoid overwriting tx_data_s too early.
                    when WAIT_TX =>
                        if tx_busy_s = '1' then
                            state <= NEXT_BYTE;
                        end if;

                    -- In NEXT_BYTE state, we wait for the uart_tx module to deassert tx_busy_s, which indicates that it has finished transmitting the current byte (including the stop bit).
                    -- Once it's finished, if we have more bytes to transmit, we load the next byte and go back to LOAD state. If we have transmitted all bytes, we go back to IDLE
                    when NEXT_BYTE =>
                        if tx_busy_s = '0' then
                            if byte_idx = N_BYTES - 1 then
                                state <= IDLE;
                            else
                                byte_idx <= byte_idx + 1;
                                -- shift the message register to bring the next byte to the most significant position for transmission
                                -- it does so by taking the remaining bits (MSG_BITS-9 downto 0) and concatenating 8 zeros at the end. 
                                msg_reg <= msg_reg(MSG_BITS-9 downto 0) & x"00";
                                state <= LOAD;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- The busy output is high whenever we are in the process of transmitting a message, which includes being in any state other than IDLE.
    busy <= '1' when state /= IDLE else '0';

end Behavioral;
