----------------------------------------------------------------------------------
-- UART Transmitter (Arty A7 - sends 'F' once per button press)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx_top is
    Port (
        Clk          : in  STD_LOGIC;          -- 100 MHz clock
        Rst          : in  STD_LOGIC;          -- Reset active LOW
        btn          : in  STD_LOGIC;  -- Button
        uart_rxd_out : out STD_LOGIC;          -- TX toward PC
        uart_txd_in  : in  STD_LOGIC           -- RX from PC (unused)
    );
end uart_tx_top;

architecture Behavioral of uart_tx_top is

    -------------------------------------------------------------------------
    -- UART config
    -------------------------------------------------------------------------
    constant CLK_FREQ  : integer := 100_000_000;
    constant BAUD_RATE : integer := 921600;
    constant BAUD_TICK_COUNT : integer := CLK_FREQ / BAUD_RATE;

    signal baud_counter : integer range 0 to BAUD_TICK_COUNT := 0;
    signal baud_tick    : std_logic := '0';

    -------------------------------------------------------------------------
    -- Button sync
    -------------------------------------------------------------------------
    signal btn_sync_0 : std_logic := '0';
    signal btn_sync_1 : std_logic := '0';
    signal btn_prev   : std_logic := '0';
    signal btn_pulse  : std_logic := '0';
    -------------------------------------------------------------------------
    -- UART Tx control
    -------------------------------------------------------------------------
    signal tx_start : std_logic := '0';
    signal tx_busy  : std_logic := '0';
    signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
    
    -------------------------------------------------------------------------
    -- FSM control
    -------------------------------------------------------------------------
    type state_type is (IDLE, START, DATA, STOP);
    signal state     : state_type := IDLE;                   -- state as signal
    signal bit_index : integer range 0 to 7 := 0;            -- bit counter as signal
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');  -- shift reg as signal


begin

    -------------------------------------------------------------------------
    -- Baud generator
    -------------------------------------------------------------------------
    process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                baud_counter <= 0;
                baud_tick <= '0';
            elsif baud_counter = BAUD_TICK_COUNT - 1 then
                baud_counter <= 0;
                baud_tick <= '1';
            else
                baud_counter <= baud_counter + 1;
                baud_tick <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------
    -- Simple + explicit button sync
    ---------------------------------------------------------------------
    edge_d : process(Clk)
    begin
        if rising_edge(Clk) then
            -- 2-stage sync per evitare metastabilità
            btn_sync_0 <= btn;
            btn_sync_1 <= btn_sync_0;
    
            -- salva valore precedente
           
    
            -- rising edge detect
            if (btn_sync_1 = '1') and (btn_prev = '0') then
            btn_pulse <= '1';
            else
                btn_pulse <= '0';
            end if;
            btn_prev   <= btn_sync_1;
        end if;
    end process;
    
    -------------------------------------------------------------------------
    -- Trigger TX once per pulse
    -------------------------------------------------------------------------
    process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                tx_start <= '0';
                tx_data  <= (others => '0');
            else
                if btn_pulse = '1' and tx_busy = '0' then
                    tx_start <= '1';
                    tx_data  <= x"46"; -- 'F'
                else
                    tx_start <= '0';
                end if;
            end if;
        end if;
    end process;

    -------------------------------------------------------------------------
    -- UART transmitter FSM
    -------------------------------------------------------------------------
    uart_tx_proc: process(Clk)
    begin
        if rising_edge(Clk) then
    
            -- reset attivo basso
            if Rst = '0' then
                uart_rxd_out <= '1';
                tx_busy      <= '0';
                state        <= IDLE;
                bit_index    <= 0;
                shift_reg    <= (others => '0');
    
            else
                case state is
                    when IDLE =>
                        uart_rxd_out <= '1';
                        tx_busy <= '0';
                        if tx_start = '1' then
                            shift_reg <= tx_data;
                            tx_busy   <= '1';
                            bit_index <= 0;
                            state     <= START;
                        end if;
    
                    when START =>
                        if baud_tick = '1' then
                            uart_rxd_out <= '0'; -- start bit
                            state        <= DATA;
                        end if;
    
                    when DATA =>
                        if baud_tick = '1' then
                            uart_rxd_out <= shift_reg(bit_index);
                            if bit_index = 7 then
                                state <= STOP;
                            else
                                bit_index <= bit_index + 1;
                            end if;
                        end if;
    
                    when STOP =>
                        if baud_tick = '1' then
                            uart_rxd_out <= '1'; -- stop bit
                            tx_busy      <= '0';
                            state        <= IDLE;
                        end if;
                end case;
            end if;
    
        end if;
    end process;


end Behavioral;
