library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity byte_fifo is
    generic (
        DEPTH_LOG2 : integer := 7  -- depth = 2**DEPTH_LOG2 (default 128)
    );
    port (
        Clk   : in  std_logic;
        Rst   : in  std_logic; -- active low

        WrEn  : in  std_logic;
        Din   : in  std_logic_vector(7 downto 0);
        Full  : out std_logic;

        RdEn  : in  std_logic;
        Dout  : out std_logic_vector(7 downto 0);
        Empty : out std_logic
    );
end byte_fifo;

architecture Behavioral of byte_fifo is

    function pow2(n : integer) return integer is
        variable r : integer := 1;
    begin
        for i in 1 to n loop
            r := r * 2;
        end loop;
        return r;
    end function;

    constant DEPTH : integer := pow2(DEPTH_LOG2);

    type mem_t is array (0 to DEPTH-1) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    signal wr_ptr : unsigned(DEPTH_LOG2-1 downto 0) := (others => '0');
    signal rd_ptr : unsigned(DEPTH_LOG2-1 downto 0) := (others => '0');
    signal count  : unsigned(DEPTH_LOG2 downto 0) := (others => '0');

    signal dout_s : std_logic_vector(7 downto 0) := (others => '0');

begin

    process(Clk)
    begin
        if rising_edge(Clk) then
            if Rst = '0' then
                wr_ptr <= (others => '0');
                rd_ptr <= (others => '0');
                count  <= (others => '0');
                dout_s <= (others => '0');
            else
                -- write
                if WrEn = '1' and Full = '0' then
                    mem(to_integer(wr_ptr)) <= Din;
                    wr_ptr <= wr_ptr + 1;
                    count <= count + 1;
                end if;

                -- read
                if RdEn = '1' and Empty = '0' then
                    dout_s <= mem(to_integer(rd_ptr));
                    rd_ptr <= rd_ptr + 1;
                    count <= count - 1;
                end if;
            end if;
        end if;
    end process;

    Full  <= '1' when count = to_unsigned(DEPTH, count'length) else '0';
    Empty <= '1' when count = to_unsigned(0, count'length) else '0';
    Dout  <= dout_s;

end Behavioral;
