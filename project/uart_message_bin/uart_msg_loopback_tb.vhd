library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_msg_loopback_tb is
end uart_msg_loopback_tb;

architecture tb of uart_msg_loopback_tb is

    constant CLK_FREQ  : integer := 100_000_000;
    constant BAUD_RATE : integer := 115200;
    constant N_BYTES   : positive := 4;
    constant APP_LATENCY_CYCLES : natural := 12;

    constant CLK_PERIOD : time := 10 ns;
    constant BIT_CLKS   : integer := CLK_FREQ / BAUD_RATE;
    constant BIT_TIME   : time := BIT_CLKS * CLK_PERIOD;

    signal Clk       : std_logic := '0';
    signal Rst       : std_logic := '1';
    signal uart_rx_i : std_logic := '1';
    signal uart_tx_o : std_logic;

    signal bench_req_data   : std_logic_vector(N_BYTES*8-1 downto 0);
    signal bench_req_valid  : std_logic;
    signal bench_rsp_data   : std_logic_vector(N_BYTES*8-1 downto 0);
    signal bench_rsp_valid  : std_logic;
    signal bench_app_cycles : std_logic_vector(31 downto 0);

    signal seen_req_pulse : std_logic := '0';
    signal seen_rsp_pulse : std_logic := '0';
    signal seen_tx_start  : std_logic := '0';
    signal tx_prev        : std_logic := '1';

    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant TX_BYTES : byte_array_t(0 to N_BYTES-1) := (x"11", x"22", x"33", x"44");

    procedure send_uart_byte(signal line : out std_logic; constant data_byte : in std_logic_vector(7 downto 0)) is
    begin
        line <= '0';
        wait for BIT_TIME;

        for i in 0 to 7 loop
            line <= data_byte(i);
            wait for BIT_TIME;
        end loop;

        line <= '1';
        wait for BIT_TIME;
    end procedure;

    function u32_to_nat(v : std_logic_vector(31 downto 0)) return natural is
    begin
        return to_integer(unsigned(v));
    end function;

begin

    Clk <= not Clk after CLK_PERIOD/2;

    dut : entity work.uart_msg_loopback_top
        generic map (
            CLK_FREQ           => CLK_FREQ,
            BAUD_RATE          => BAUD_RATE,
            N_BYTES            => N_BYTES,
            APP_LATENCY_CYCLES  => APP_LATENCY_CYCLES
        )
        port map (
            Clk              => Clk,
            Rst              => Rst,
            uart_rx_i        => uart_rx_i,
            uart_tx_o        => uart_tx_o,
            bench_req_data   => bench_req_data,
            bench_req_valid  => bench_req_valid,
            bench_rsp_data   => bench_rsp_data,
            bench_rsp_valid  => bench_rsp_valid,
            bench_app_cycles => bench_app_cycles
        );

    monitor : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                seen_req_pulse <= '0';
                seen_rsp_pulse <= '0';
                seen_tx_start  <= '0';
                tx_prev <= '1';
            else
                if bench_req_valid = '1' then
                    seen_req_pulse <= '1';
                end if;

                if bench_rsp_valid = '1' then
                    seen_rsp_pulse <= '1';
                end if;

                if (tx_prev = '1') and (uart_tx_o = '0') then
                    seen_tx_start <= '1';
                end if;

                tx_prev <= uart_tx_o;
            end if;
        end if;
    end process;

    stimulus : process
    begin
        Rst <= '0';
        wait for 200 ns;
        Rst <= '1';
        wait for 200 ns;

        for k in TX_BYTES'range loop
            send_uart_byte(uart_rx_i, TX_BYTES(k));
        end loop;

        wait for 200 * BIT_TIME;

        assert seen_req_pulse = '1'
            report "bench_req_valid was not pulsed" severity error;

        assert seen_rsp_pulse = '1'
            report "bench_rsp_valid was not pulsed" severity error;

        assert seen_tx_start = '1'
            report "uart_tx_o never started a frame" severity error;

        assert bench_req_data = x"11223344"
            report "Received message mismatch" severity error;

        assert bench_rsp_data = x"11223344"
            report "Response message mismatch" severity error;

        assert u32_to_nat(bench_app_cycles) = APP_LATENCY_CYCLES
            report "Application latency counter mismatch" severity error;

        wait;
    end process;

end tb;