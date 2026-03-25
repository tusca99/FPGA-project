library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_msg_loopback_top is
    generic (
        CLK_FREQ          : integer := 100_000_000;
        BAUD_RATE         : integer := 115200;
        N_BYTES           : positive := 8;
        APP_LATENCY_CYCLES : natural := 0
    );
    port (
        Clk        : in  std_logic;
        Rst        : in  std_logic; -- active low
        uart_rx_i  : in  std_logic;
        uart_tx_o  : out std_logic;

        bench_req_data   : out std_logic_vector(N_BYTES*8-1 downto 0);
        bench_req_valid  : out std_logic;
        bench_rsp_data   : out std_logic_vector(N_BYTES*8-1 downto 0);
        bench_rsp_valid  : out std_logic;
        bench_app_cycles : out std_logic_vector(31 downto 0)
    );
end uart_msg_loopback_top;

architecture Behavioral of uart_msg_loopback_top is
    signal baud_tick_s : std_logic := '0';
    signal half_tick_s : std_logic := '0';

    signal rx_msg_s   : std_logic_vector(N_BYTES*8-1 downto 0) := (others => '0');
    signal rx_valid_s : std_logic := '0';
    signal rx_busy_s  : std_logic := '0';

    signal tx_start_s : std_logic := '0';
    signal tx_busy_s  : std_logic := '0';
    signal tx_msg_s   : std_logic_vector(N_BYTES*8-1 downto 0) := (others => '0');

    type state_t is (IDLE, APP_RUN, TX_WAIT);
    signal state : state_t := IDLE;
    signal app_count : natural range 0 to APP_LATENCY_CYCLES := 0;
    signal app_cycles_s : unsigned(31 downto 0) := (others => '0');

begin

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

    rx_inst : entity work.uart_msg_rx
        generic map (
            N_BYTES => N_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s,
            half_tick => half_tick_s,
            uart_rx_i => uart_rx_i,
            msg_data  => rx_msg_s,
            msg_valid => rx_valid_s,
            busy      => rx_busy_s
        );

    tx_inst : entity work.uart_msg_tx
        generic map (
            N_BYTES => N_BYTES
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            baud_tick => baud_tick_s,
            msg_start => tx_start_s,
            msg_data  => tx_msg_s,
            busy      => tx_busy_s,
            uart_tx_o => uart_tx_o
        );

    process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                state <= IDLE;
                app_count <= 0;
                app_cycles_s <= (others => '0');
                tx_start_s <= '0';
                tx_msg_s <= (others => '0');
                bench_req_valid <= '0';
                bench_rsp_valid <= '0';
            else
                tx_start_s <= '0';
                bench_req_valid <= '0';
                bench_rsp_valid <= '0';

                case state is
                    when IDLE =>
                        if rx_valid_s = '1' then
                            bench_req_data <= rx_msg_s;
                            bench_req_valid <= '1';
                            tx_msg_s <= rx_msg_s;
                            app_count <= 0;
                            state <= APP_RUN;
                        end if;

                    when APP_RUN =>
                        if app_count = APP_LATENCY_CYCLES then
                            app_cycles_s <= to_unsigned(app_count, 32);
                            bench_rsp_data <= tx_msg_s;
                            bench_rsp_valid <= '1';
                            tx_start_s <= '1';
                            state <= TX_WAIT;
                        else
                            app_count <= app_count + 1;
                        end if;

                    when TX_WAIT =>
                        if tx_busy_s = '0' then
                            state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    bench_app_cycles <= std_logic_vector(app_cycles_s);

end Behavioral;