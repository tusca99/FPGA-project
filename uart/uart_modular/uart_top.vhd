-- Top-level UART integrating baud gen, TX and RX
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_top is
    generic (
        CLK_FREQ  : integer := 100_000_000;  -- Hz
        BAUD_RATE : integer := 115200        -- Default BAUD rate
    );
    Port (
        Clk          : in  std_logic;
        Rst          : in  std_logic; -- active low
        btn          : in  std_logic;
        uart_rxd_out : out std_logic; -- FPGA TX -> PC RX
        uart_txd_in  : in  std_logic; -- FPGA RX <- PC TX
        led          : out std_logic
    );
end uart_top;

architecture Behavioral of uart_top is

    -- Baud generator signals
    signal baud_tick_s : std_logic;
    signal half_tick_s : std_logic;

    -- Button sync and edge detection
    signal btn_sync_0 : std_logic := '0';
    signal btn_sync_1 : std_logic := '0';
    signal btn_prev   : std_logic := '0';
    signal btn_pulse  : std_logic := '0';

    -- TX signals
    signal tx_start_s : std_logic := '0';
    signal tx_busy_s  : std_logic := '0';
    signal tx_data_s  : std_logic_vector(7 downto 0) := (others => '0');
    -- TX request queue (1-deep) to avoid lost button presses
    signal tx_req      : std_logic := '0';
    signal tx_req_data : std_logic_vector(7 downto 0) := (others => '0');

    -- RX signals
    signal rx_data_s  : std_logic_vector(7 downto 0);
    signal rx_valid_s : std_logic := '0';

    -- LED timer
    constant LED_PERIOD : integer := CLK_FREQ; -- 1 second
    signal led_counter  : integer range 0 to LED_PERIOD := 0;
    signal led_reg      : std_logic := '0';

begin

    ------------------------------------------------------------------
    -- Baud generator instantiation
    ------------------------------------------------------------------
    baud_inst : entity work.baud_gen
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s,
            half_tick => half_tick_s
        );

    ------------------------------------------------------------------
    -- UART TX instantiation
    ------------------------------------------------------------------
    tx_inst : entity work.uart_tx
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s,
            tx_start  => tx_start_s,
            tx_data   => tx_data_s,
            tx_busy   => tx_busy_s,
            uart_tx_o => uart_rxd_out
        );

    ------------------------------------------------------------------
    -- UART RX instantiation
    ------------------------------------------------------------------
    rx_inst : entity work.uart_rx
        port map (
            Clk       => Clk,
            Rst       => Rst,
            uart_rx_i => uart_txd_in,
            baud_tick => baud_tick_s,
            half_tick => half_tick_s,
            rx_data   => rx_data_s,
            rx_valid  => rx_valid_s
        );

    ------------------------------------------------------------------
    -- Button sync + edge detector
    ------------------------------------------------------------------
    button_edge : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                btn_sync_0 <= '0';
                btn_sync_1 <= '0';
                btn_prev   <= '0';
                btn_pulse  <= '0';
            else
                btn_sync_0 <= btn;
                btn_sync_1 <= btn_sync_0;

                if (btn_sync_1 = '1') and (btn_prev = '0') then
                    btn_pulse <= '1';
                else
                    btn_pulse <= '0';
                end if;
                btn_prev <= btn_sync_1;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Trigger TX on button press (send character 'a' (0x61))
    ------------------------------------------------------------------
    -- Capture button presses into a 1-deep request latch so quick presses
    -- are not lost while the transmitter is busy.
    tx_trigger : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                tx_req <= '0';
                tx_req_data <= (others => '0');
            else
                -- latch request when button edge occurs
                if btn_pulse = '1' then
                    tx_req <= '1';
                    tx_req_data <= x"61"; -- 'a'
                end if;
            end if;
        end if;
    end process;

    -- Start transmitter when a request is pending and transmitter is free
    tx_start_ctrl : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                tx_start_s <= '0';
                tx_data_s <= (others => '0');
            else
                if tx_req = '1' and tx_busy_s = '0' then
                    tx_start_s <= '1';
                    tx_data_s <= tx_req_data;
                    tx_req <= '0'; -- consume request
                else
                    tx_start_s <= '0';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- LED control: on rx_valid 'a' set LED on for 1 second
    ------------------------------------------------------------------
    led_ctrl : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                led_counter <= 0;
                led_reg <= '0';
            else
                -- If character 'a' received, set counter
                if rx_valid_s = '1' and rx_data_s = x"61" then
                    led_counter <= LED_PERIOD - 1;
                    led_reg <= '1';
                else
                    if led_counter > 0 then
                        led_counter <= led_counter - 1;
                        led_reg <= '1';
                    else
                        led_reg <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    led <= led_reg;

end Behavioral;
