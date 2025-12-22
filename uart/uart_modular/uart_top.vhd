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
    -- TX FIFO for responses (prevents lost bytes while tx_busy='1')
    signal txf_wr_en  : std_logic := '0';
    signal txf_din    : std_logic_vector(7 downto 0) := (others => '0');
    signal txf_full   : std_logic := '0';
    signal txf_rd_en  : std_logic := '0';
    signal txf_dout   : std_logic_vector(7 downto 0) := (others => '0');
    signal txf_empty  : std_logic := '1';

    -- RX signals
    signal rx_data_s  : std_logic_vector(7 downto 0);
    signal rx_valid_s : std_logic := '0';

    -- RX FIFO for command bytes (prevents lost bytes if parser stalls)
    signal rxf_wr_en  : std_logic := '0';
    signal rxf_din    : std_logic_vector(7 downto 0) := (others => '0');
    signal rxf_full   : std_logic := '0';
    signal rxf_rd_en  : std_logic := '0';
    signal rxf_dout   : std_logic_vector(7 downto 0) := (others => '0');
    signal rxf_empty  : std_logic := '1';
    signal rx_valid_d : std_logic := '0';
    signal rx_pulse   : std_logic := '0';

    -- ASCII command parser outputs
    signal cmd_valid_s : std_logic := '0';
    signal cmd_err_s   : std_logic := '0';
    signal cmd_code_s  : std_logic_vector(3 downto 0) := (others => '0');
    signal cmd_arg0_s  : std_logic_vector(31 downto 0) := (others => '0');
    signal cmd_arg1_s  : std_logic_vector(31 downto 0) := (others => '0');

    -- Simple regfile + metrics (app core control/state)
    type regfile_t is array (0 to 31) of std_logic_vector(31 downto 0);
    signal regs : regfile_t := (others => (others => '0'));
    signal run_flag   : std_logic := '0';
    signal rx_overrun : unsigned(31 downto 0) := (others => '0');
    signal tx_overrun : unsigned(31 downto 0) := (others => '0');

    -- MD toy core interface
    signal core_step_add_valid : std_logic := '0';
    signal core_step_add_count : std_logic_vector(31 downto 0) := (others => '0');
    signal core_cfg_init_pulse : std_logic := '0';

    signal core_step_count     : std_logic_vector(31 downto 0) := (others => '0');
    signal core_pending_steps  : std_logic_vector(31 downto 0) := (others => '0');
    signal core_pos0           : std_logic_vector(15 downto 0) := (others => '0');
    signal core_pos1           : std_logic_vector(15 downto 0) := (others => '0');
    signal core_dist2          : std_logic_vector(31 downto 0) := (others => '0');

    -- Response builder
    type resp_t is array (0 to 127) of std_logic_vector(7 downto 0);
    signal resp_buf : resp_t := (others => (others => '0'));
    signal resp_len : integer range 0 to 128 := 0;
    signal resp_idx : integer range 0 to 128 := 0;
    signal resp_active : std_logic := '0';

    function hex_nibble(n : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable c : std_logic_vector(7 downto 0);
    begin
        if unsigned(n) < 10 then
            c := std_logic_vector(to_unsigned(character'pos('0') + to_integer(unsigned(n)), 8));
        else
            c := std_logic_vector(to_unsigned(character'pos('A') + (to_integer(unsigned(n)) - 10), 8));
        end if;
        return c;
    end function;

    procedure put_str(
        signal buf : inout resp_t;
        variable idx : inout integer;
        constant s : in string
    ) is
    begin
        for k in s'range loop
            if idx < 128 then
                buf(idx) <= std_logic_vector(to_unsigned(character'pos(s(k)), 8));
                idx := idx + 1;
            end if;
        end loop;
    end procedure;

    procedure put_hex32(
        signal buf : inout resp_t;
        variable idx : inout integer;
        constant v : in std_logic_vector(31 downto 0)
    ) is
        variable u : unsigned(31 downto 0);
        variable nib : std_logic_vector(3 downto 0);
    begin
        u := unsigned(v);
        if idx < 128 then
            buf(idx) <= std_logic_vector(to_unsigned(character'pos('0'), 8)); idx := idx + 1;
        end if;
        if idx < 128 then
            buf(idx) <= std_logic_vector(to_unsigned(character'pos('x'), 8)); idx := idx + 1;
        end if;
        for shift in 7 downto 0 loop
            nib := std_logic_vector(u(shift*4+3 downto shift*4));
            if idx < 128 then
                buf(idx) <= hex_nibble(nib);
                idx := idx + 1;
            end if;
        end loop;
    end procedure;

    -- LED timer
    constant LED_PERIOD : integer := CLK_FREQ; -- 1 second
    signal led_counter  : integer range 0 to LED_PERIOD := 0;
    signal led_reg      : std_logic := '0';

begin

    ------------------------------------------------------------------
    -- MD toy core (single-clock data-plane)
    --
    -- Register map (subset):
    -- 10: vel0 (signed16 in [15:0])
    -- 11: vel1 (signed16 in [15:0])
    -- 13: init_pos0 (signed16 in [15:0])
    -- 14: init_pos1 (signed16 in [15:0])
    --
    -- Status (read via RD):
    --  2: step_count
    --  5: pending_steps
    --  6: pos0 (sign-extended)
    --  7: pos1 (sign-extended)
    --  8: dist2
    ------------------------------------------------------------------
    md_core_inst : entity work.md_toy_core
        port map (
            Clk          => Clk,
            Rst          => Rst,
            RunEn        => run_flag,
            StepAddValid => core_step_add_valid,
            StepAddCount => core_step_add_count,
            CfgVel0      => regs(10)(15 downto 0),
            CfgVel1      => regs(11)(15 downto 0),
            CfgInitPos0  => regs(13)(15 downto 0),
            CfgInitPos1  => regs(14)(15 downto 0),
            CfgInit      => core_cfg_init_pulse,
            StepCount    => core_step_count,
            PendingSteps => core_pending_steps,
            Pos0         => core_pos0,
            Pos1         => core_pos1,
            Dist2        => core_dist2
        );

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
    -- RX FIFO: capture bytes on rx_valid rising edge (rx_valid is stretched)
    ------------------------------------------------------------------
    rx_pulse <= rx_valid_s and (not rx_valid_d);

    rx_fifo_inst : entity work.byte_fifo
        generic map (
            DEPTH_LOG2 => 7
        )
        port map (
            Clk   => Clk,
            Rst   => Rst,
            WrEn  => rxf_wr_en,
            Din   => rxf_din,
            Full  => rxf_full,
            RdEn  => rxf_rd_en,
            Dout  => rxf_dout,
            Empty => rxf_empty
        );

    ------------------------------------------------------------------
    -- TX FIFO: store response bytes and feed uart_tx when free
    ------------------------------------------------------------------
    tx_fifo_inst : entity work.byte_fifo
        generic map (
            DEPTH_LOG2 => 7
        )
        port map (
            Clk   => Clk,
            Rst   => Rst,
            WrEn  => txf_wr_en,
            Din   => txf_din,
            Full  => txf_full,
            RdEn  => txf_rd_en,
            Dout  => txf_dout,
            Empty => txf_empty
        );

    ------------------------------------------------------------------
    -- ASCII command parser: consumes bytes from RX FIFO
    ------------------------------------------------------------------
    parser_inst : entity work.ascii_cmd_parser
        generic map (
            LINE_MAX => 80
        )
        port map (
            Clk => Clk,
            Rst => Rst,
            RxEmpty => rxf_empty,
            RxDout  => rxf_dout,
            RxRdEn  => rxf_rd_en,
            CmdValid => cmd_valid_s,
            CmdErr   => cmd_err_s,
            CmdCode  => cmd_code_s,
            Arg0     => cmd_arg0_s,
            Arg1     => cmd_arg1_s
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
    -- Drive UART TX from TX FIFO
    ------------------------------------------------------------------
    tx_drive : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                tx_start_s <= '0';
                tx_data_s  <= (others => '0');
                txf_rd_en  <= '0';
            else
                tx_start_s <= '0';
                txf_rd_en  <= '0';
                if tx_busy_s = '0' and txf_empty = '0' then
                    -- Pop one byte and start tx
                    txf_rd_en <= '1';
                    tx_data_s <= txf_dout;
                    tx_start_s <= '1';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- RX capture + command handling + response enqueue
    ------------------------------------------------------------------
    main_ctrl : process(Clk)
        variable idx : integer;
        variable reg_i : integer;
        variable tmp32 : std_logic_vector(31 downto 0);
        variable addr_u : unsigned(31 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                rx_valid_d <= '0';
                rxf_wr_en <= '0';
                rxf_din <= (others => '0');
                txf_wr_en <= '0';
                txf_din <= (others => '0');
                resp_len <= 0;
                resp_idx <= 0;
                resp_active <= '0';
                run_flag <= '0';
                rx_overrun <= (others => '0');
                tx_overrun <= (others => '0');
                regs(0) <= x"00010001"; -- VERSION 1.1
                -- MD toy defaults
                regs(10) <= x"00000001"; -- vel0 = +1
                regs(11) <= x"0000FFFF"; -- vel1 = -1
                regs(13) <= x"00000000"; -- init_pos0
                regs(14) <= x"00000064"; -- init_pos1 = 100
                core_step_add_valid <= '0';
                core_step_add_count <= (others => '0');
                core_cfg_init_pulse <= '0';
            else
                rx_valid_d <= rx_valid_s;
                rxf_wr_en <= '0';
                txf_wr_en <= '0';
                core_step_add_valid <= '0';
                core_cfg_init_pulse <= '0';

                -- capture incoming byte into RX FIFO (edge detect on rx_valid)
                if rx_pulse = '1' then
                    if rxf_full = '0' then
                        rxf_wr_en <= '1';
                        rxf_din <= rx_data_s;
                    else
                        rx_overrun <= rx_overrun + 1;
                    end if;
                end if;

                -- continuously mirror core state into regfile for RD
                regs(1) <= (31 downto 2 => '0') & run_flag & '0';
                regs(2) <= core_step_count;
                regs(5) <= core_pending_steps;
                regs(6) <= (31 downto 16 => core_pos0(15)) & core_pos0;
                regs(7) <= (31 downto 16 => core_pos1(15)) & core_pos1;
                regs(8) <= core_dist2;

                -- on new decoded command, build a response buffer
                if cmd_valid_s = '1' then
                    idx := 0;

                    if cmd_err_s = '1' then
                        put_str(resp_buf, idx, "ERR\n");
                    else
                        case cmd_code_s is
                            when "0001" => -- PING
                                put_str(resp_buf, idx, "PONG\n");

                            when "0010" => -- HELP
                                put_str(resp_buf, idx, "CMDS: PING, HELP, RD <addr>, WR <addr> <val>, START, STOP, STEP <n>, METRICS\n");

                            when "0011" => -- RD
                                addr_u := unsigned(cmd_arg0_s);
                                reg_i := to_integer(addr_u(4 downto 0));
                                tmp32 := regs(reg_i);
                                put_str(resp_buf, idx, "RD ");
                                put_hex32(resp_buf, idx, std_logic_vector(addr_u));
                                put_str(resp_buf, idx, " ");
                                put_hex32(resp_buf, idx, tmp32);
                                put_str(resp_buf, idx, "\n");

                            when "0100" => -- WR
                                addr_u := unsigned(cmd_arg0_s);
                                reg_i := to_integer(addr_u(4 downto 0));
                                regs(reg_i) <= cmd_arg1_s;
                                if reg_i = 13 or reg_i = 14 then
                                    -- allow reinitialization after writing init positions
                                    core_cfg_init_pulse <= '1';
                                end if;
                                put_str(resp_buf, idx, "OK\n");

                            when "0101" => -- START
                                run_flag <= '1';
                                put_str(resp_buf, idx, "OK\n");

                            when "0110" => -- STOP
                                run_flag <= '0';
                                put_str(resp_buf, idx, "OK\n");

                            when "0111" => -- STEP
                                core_step_add_valid <= '1';
                                core_step_add_count <= cmd_arg0_s;
                                put_str(resp_buf, idx, "OK\n");

                            when "1000" => -- METRICS
                                regs(3) <= std_logic_vector(rx_overrun);
                                regs(4) <= std_logic_vector(tx_overrun);
                                put_str(resp_buf, idx, "STEP ");
                                put_hex32(resp_buf, idx, core_step_count);
                                put_str(resp_buf, idx, " RX_OVR ");
                                put_hex32(resp_buf, idx, std_logic_vector(rx_overrun));
                                put_str(resp_buf, idx, " TX_OVR ");
                                put_hex32(resp_buf, idx, std_logic_vector(tx_overrun));
                                put_str(resp_buf, idx, "\n");

                            when others =>
                                put_str(resp_buf, idx, "ERR\n");
                        end case;
                    end if;

                    resp_len <= idx;
                    resp_idx <= 0;
                    resp_active <= '1';
                end if;

                -- stream response bytes into TX FIFO
                if resp_active = '1' then
                    if resp_idx < resp_len then
                        if txf_full = '0' then
                            txf_wr_en <= '1';
                            txf_din <= resp_buf(resp_idx);
                            resp_idx <= resp_idx + 1;
                        else
                            tx_overrun <= tx_overrun + 1;
                        end if;
                    else
                        resp_active <= '0';
                    end if;
                end if;

            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- LED control: blink on each successfully decoded command
    ------------------------------------------------------------------
    led_ctrl : process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                led_counter <= 0;
                led_reg <= '0';
            else
                if cmd_valid_s = '1' and cmd_err_s = '0' then
                    led_counter <= LED_PERIOD/10; -- ~100ms pulse
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
