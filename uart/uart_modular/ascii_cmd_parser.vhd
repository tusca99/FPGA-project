library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ascii_cmd_parser is
    generic (
        LINE_MAX : integer := 80
    );
    port (
        Clk : in std_logic;
        Rst : in std_logic; -- active low

        -- RX FIFO interface
        RxEmpty : in  std_logic;
        RxDout  : in  std_logic_vector(7 downto 0);
        RxRdEn  : out std_logic;

        -- Decoded command (1-cycle pulse)
        CmdValid : out std_logic;
        CmdErr   : out std_logic;
        CmdCode  : out std_logic_vector(3 downto 0);
        Arg0     : out std_logic_vector(31 downto 0);
        Arg1     : out std_logic_vector(31 downto 0)
    );
end ascii_cmd_parser;

architecture Behavioral of ascii_cmd_parser is

    -- CmdCode values
    constant CMD_NOP     : std_logic_vector(3 downto 0) := "0000";
    constant CMD_PING    : std_logic_vector(3 downto 0) := "0001";
    constant CMD_HELP    : std_logic_vector(3 downto 0) := "0010";
    constant CMD_RD      : std_logic_vector(3 downto 0) := "0011";
    constant CMD_WR      : std_logic_vector(3 downto 0) := "0100";
    constant CMD_START   : std_logic_vector(3 downto 0) := "0101";
    constant CMD_STOP    : std_logic_vector(3 downto 0) := "0110";
    constant CMD_STEP    : std_logic_vector(3 downto 0) := "0111";
    constant CMD_METRICS : std_logic_vector(3 downto 0) := "1000";

    type line_t is array (0 to LINE_MAX-1) of std_logic_vector(7 downto 0);
    signal line_buf : line_t := (others => (others => '0'));
    signal line_len : integer range 0 to LINE_MAX := 0;
    signal line_ready : std_logic := '0';

    signal rx_rd_en_s : std_logic := '0';

    function to_char(b : std_logic_vector(7 downto 0)) return character is
    begin
        return character'val(to_integer(unsigned(b)));
    end function;

    function upper(c : character) return character is
    begin
        if c >= 'a' and c <= 'z' then
            return character'val(character'pos(c) - character'pos('a') + character'pos('A'));
        end if;
        return c;
    end function;

    function is_space(c : character) return boolean is
    begin
        return (c = ' ') or (c = '\t');
    end function;

    -- Returns index of first non-space >= i; if none, returns line_len
    function skip_spaces(buf : line_t; len : integer; i : integer) return integer is
        variable k : integer := i;
    begin
        while k < len loop
            if not is_space(to_char(buf(k))) then
                exit;
            end if;
            k := k + 1;
        end loop;
        return k;
    end function;

    -- Extract token: start index and length
    procedure next_token(
        signal buf : in line_t;
        constant len : in integer;
        variable i : inout integer;
        variable tok_start : out integer;
        variable tok_len : out integer
    ) is
        variable k : integer;
    begin
        k := skip_spaces(buf, len, i);
        tok_start := k;
        tok_len := 0;
        while k < len loop
            if is_space(to_char(buf(k))) then
                exit;
            end if;
            tok_len := tok_len + 1;
            k := k + 1;
        end loop;
        i := k;
    end procedure;

    function match_token(buf : line_t; tok_start : integer; tok_len : integer; kw : string) return boolean is
        variable ok : boolean := true;
    begin
        if tok_len /= kw'length then
            return false;
        end if;
        for j in 0 to kw'length-1 loop
            if upper(to_char(buf(tok_start + j))) /= upper(kw(kw'low + j)) then
                ok := false;
            end if;
        end loop;
        return ok;
    end function;

    function hex_val(c : character) return integer is
    begin
        if c >= '0' and c <= '9' then
            return character'pos(c) - character'pos('0');
        elsif c >= 'a' and c <= 'f' then
            return 10 + character'pos(c) - character'pos('a');
        elsif c >= 'A' and c <= 'F' then
            return 10 + character'pos(c) - character'pos('A');
        else
            return -1;
        end if;
    end function;

    function parse_u32(buf : line_t; tok_start : integer; tok_len : integer; ok : out std_logic) return std_logic_vector is
        variable base : integer := 10;
        variable idx  : integer := tok_start;
        variable rem  : integer := tok_len;
        variable acc  : unsigned(31 downto 0) := (others => '0');
        variable hv   : integer;
        variable c    : character;
    begin
        ok := '0';
        if tok_len <= 0 then
            return std_logic_vector(acc);
        end if;

        -- optional 0x prefix
        if tok_len >= 2 then
            if (to_char(buf(tok_start)) = '0') and (upper(to_char(buf(tok_start+1))) = 'X') then
                base := 16;
                idx := tok_start + 2;
                rem := tok_len - 2;
            end if;
        end if;

        if rem <= 0 then
            return std_logic_vector(acc);
        end if;

        for k in 0 to rem-1 loop
            c := to_char(buf(idx + k));
            if base = 10 then
                if c < '0' or c > '9' then
                    return std_logic_vector(acc);
                end if;
                acc := acc * 10 + to_unsigned(character'pos(c) - character'pos('0'), 32);
            else
                hv := hex_val(c);
                if hv < 0 then
                    return std_logic_vector(acc);
                end if;
                acc := shift_left(acc, 4) + to_unsigned(hv, 32);
            end if;
        end loop;

        ok := '1';
        return std_logic_vector(acc);
    end function;

    signal cmd_valid_s : std_logic := '0';
    signal cmd_err_s   : std_logic := '0';
    signal cmd_code_s  : std_logic_vector(3 downto 0) := CMD_NOP;
    signal arg0_s      : std_logic_vector(31 downto 0) := (others => '0');
    signal arg1_s      : std_logic_vector(31 downto 0) := (others => '0');

begin

    RxRdEn <= rx_rd_en_s;
    CmdValid <= cmd_valid_s;
    CmdErr <= cmd_err_s;
    CmdCode <= cmd_code_s;
    Arg0 <= arg0_s;
    Arg1 <= arg1_s;

    process(Clk)
        variable i : integer;
        variable t1s, t1l : integer;
        variable t2s, t2l : integer;
        variable t3s, t3l : integer;
        variable ok0, ok1 : std_logic;
        variable v0, v1   : std_logic_vector(31 downto 0);
        variable c        : character;
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                line_len <= 0;
                line_ready <= '0';
                rx_rd_en_s <= '0';
                cmd_valid_s <= '0';
                cmd_err_s <= '0';
                cmd_code_s <= CMD_NOP;
                arg0_s <= (others => '0');
                arg1_s <= (others => '0');
            else
                cmd_valid_s <= '0';
                cmd_err_s <= '0';
                cmd_code_s <= CMD_NOP;
                rx_rd_en_s <= '0';

                -- Consume RX FIFO until we have a full line
                if line_ready = '0' and RxEmpty = '0' then
                    rx_rd_en_s <= '1';
                    c := to_char(RxDout);

                    if c = '\r' then
                        null;
                    elsif c = '\n' then
                        line_ready <= '1';
                    else
                        if line_len < LINE_MAX then
                            line_buf(line_len) <= RxDout;
                            line_len <= line_len + 1;
                        else
                            -- line overflow -> drop line
                            line_len <= 0;
                            line_ready <= '0';
                        end if;
                    end if;
                end if;

                -- Parse line when ready
                if line_ready = '1' then
                    i := 0;
                    next_token(line_buf, line_len, i, t1s, t1l);
                    next_token(line_buf, line_len, i, t2s, t2l);
                    next_token(line_buf, line_len, i, t3s, t3l);

                    if t1l = 0 then
                        cmd_valid_s <= '1';
                        cmd_code_s <= CMD_NOP;
                    elsif match_token(line_buf, t1s, t1l, "PING") then
                        cmd_valid_s <= '1';
                        cmd_code_s <= CMD_PING;
                    elsif match_token(line_buf, t1s, t1l, "HELP") then
                        cmd_valid_s <= '1';
                        cmd_code_s <= CMD_HELP;
                    elsif match_token(line_buf, t1s, t1l, "RD") then
                        v0 := parse_u32(line_buf, t2s, t2l, ok0);
                        if ok0 = '1' then
                            cmd_valid_s <= '1';
                            cmd_code_s <= CMD_RD;
                            arg0_s <= v0;
                        else
                            cmd_valid_s <= '1';
                            cmd_err_s <= '1';
                        end if;
                    elsif match_token(line_buf, t1s, t1l, "WR") then
                        v0 := parse_u32(line_buf, t2s, t2l, ok0);
                        v1 := parse_u32(line_buf, t3s, t3l, ok1);
                        if ok0 = '1' and ok1 = '1' then
                            cmd_valid_s <= '1';
                            cmd_code_s <= CMD_WR;
                            arg0_s <= v0;
                            arg1_s <= v1;
                        else
                            cmd_valid_s <= '1';
                            cmd_err_s <= '1';
                        end if;
                    elsif match_token(line_buf, t1s, t1l, "START") then
                        cmd_valid_s <= '1';
                        cmd_code_s <= CMD_START;
                    elsif match_token(line_buf, t1s, t1l, "STOP") then
                        cmd_valid_s <= '1';
                        cmd_code_s <= CMD_STOP;
                    elsif match_token(line_buf, t1s, t1l, "STEP") then
                        v0 := parse_u32(line_buf, t2s, t2l, ok0);
                        if ok0 = '1' then
                            cmd_valid_s <= '1';
                            cmd_code_s <= CMD_STEP;
                            arg0_s <= v0;
                        else
                            cmd_valid_s <= '1';
                            cmd_err_s <= '1';
                        end if;
                    elsif match_token(line_buf, t1s, t1l, "METRICS") then
                        cmd_valid_s <= '1';
                        cmd_code_s <= CMD_METRICS;
                    else
                        cmd_valid_s <= '1';
                        cmd_err_s <= '1';
                    end if;

                    line_len <= 0;
                    line_ready <= '0';
                end if;

            end if;
        end if;
    end process;

end Behavioral;
