library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- This module implements a UART message receiver that collects bytes received from the uart_rx module until it has received a full message of N_BYTES.
entity uart_msg_rx is
    generic (
        CLK_FREQ  : integer := 100_000_000;     -- machine clock frequency (Hz)
        BAUD_RATE : integer := 115200;          -- default baud rate (bits per second)
        N_BYTES   : positive := 8               -- number of bytes in a complete message
    );
    port (
        Clk       : in  std_logic;
        Rst       : in  std_logic;                              -- active low
        uart_rx_i : in  std_logic;                              -- UART receive line (idle high)
        msg_data  : out std_logic_vector(N_BYTES*8-1 downto 0); -- output for the complete received message, valid when msg_valid is high
        msg_valid : out std_logic;                              -- high for one cycle when a complete message of N_BYTES has been received and is valid on msg_data
        busy      : out std_logic                               -- high when we are in the process of receiving a message
    );
end uart_msg_rx;

architecture Behavioral of uart_msg_rx is
    constant MSG_BITS : natural := N_BYTES * 8;         -- total number of bits in a complete message (N_BYTES * 8 bits per byte)

    -- Signals to interface with the uart_rx module
    signal rx_data_s        : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid_s       : std_logic := '0';
    signal rx_valid_prev_s  : std_logic := '0';         -- signal to hold the previous value of rx_valid_s for edge detection to know when a new byte has been received

    signal msg_reg     : std_logic_vector(MSG_BITS-1 downto 0) := (others => '0');  -- register to hold the incoming message bits as they are received.
    signal byte_idx    : integer range 0 to N_BYTES-1 := 0;                         -- index to keep track of how many bytes have been received so far for the current message
    signal msg_valid_s : std_logic := '0';
    signal receiving_s : std_logic := '0';                                          -- signal to indicate that we are currently in the process of receiving a message (busy signal).

begin

    -- Instantiate the uart_rx module to handle the actual reception of bytes over UART.
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
    begin
        if rising_edge(Clk) then
            -- reset is active LOW, reset state machine and outputs to idle conditions
            if Rst = '0' then
                msg_reg <= (others => '0');
                byte_idx <= 0;
                msg_valid_s <= '0';
                receiving_s <= '0';
                rx_valid_prev_s <= '0';
            else
                msg_valid_s <= '0';     -- by default, we will deassert msg_valid_s. It will be pulsed for one cycle when we have received a complete message of N_BYTES.

                -- We detect the rising edge of rx_valid_s to know when a new byte has been received from the uart_rx module. 
                -- On that rising edge, we shift the new byte into the msg_reg register and update the byte index.
                if rx_valid_s = '1' and rx_valid_prev_s = '0' then
                    receiving_s <= '1';
                    -- We shift the existing bits in msg_reg to the left by 8 positions (MSG_BITS-9 downto 0) 
                    -- and concatenate the new byte (rx_data_s) at the least significant position.
                    msg_reg <= msg_reg(MSG_BITS-9 downto 0) & rx_data_s;

                    -- When we have received N_BYTES, we will assert msg_valid_s for one cycle to indicate that a complete message is ready on msg_data,
                    -- and then reset the byte index and receiving state for the next message.
                    if byte_idx = N_BYTES - 1 then
                        msg_valid_s <= '1';
                        byte_idx <= 0;
                        receiving_s <= '0';
                    else
                        byte_idx <= byte_idx + 1;
                    end if;
                end if;

                -- Update the previous value of rx_valid_s for edge detection in the next cycle.
                rx_valid_prev_s <= rx_valid_s;
            end if;
        end if;
    end process;

    msg_data <= msg_reg;
    msg_valid <= msg_valid_s;
    busy <= receiving_s;

end Behavioral;
