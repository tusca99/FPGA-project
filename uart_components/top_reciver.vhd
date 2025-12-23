----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 18.10.2023 12:45:27
-- Design Name: 
-- Module Name: tb_counter - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity top_reciver is
    port ( 
        CLK100MHZ       : in std_logic; --clock port
        ck_rst          : in std_logic; --Reset port
--        btn             : in std_logic_vector(3 downto 0); --button port
--        sw              : in std_logic_vector(3 downto 0); --switch port
--        uart_rxd_out    : out std_logic --uart reciver output
        uart_txd_in     : in std_logic; --uart transmitter output
        led0_b          : out std_logic; --output blue led
        led0_r          : out std_logic --output red led
--        Busy            : out std_logic  --Busy state port
      );
end top_reciver;

architecture Behavioral of top_reciver is

signal recived_data : std_logic_vector( 7 downto 0);
signal register_data: std_logic_vector( 7 downto 0);
signal data_eq      : std_logic_vector( 7 downto 0 ) := "00111101";
signal data_po      : std_logic_vector( 7 downto 0 ) := "00101110";
signal data_valid   : std_logic := '0';
signal sample_data  : std_logic := '0';
constant led_on     : POSITIVE := 2**25;
signal counter      : POSITIVE range 0 to led_on := 0; 


component Reciver is
    generic (
            Period: POSITIVE := 868
                );
        port ( 
            Rst     : in std_logic; --Reset port
            Clk     : in std_logic; --clock port
            -- DVal    : in std_logic; --Data Valid port
            Data    : in std_logic; --Data port
            Dout    : out std_logic_vector(7 downto 0);  --Data out port
            DVal    : out std_logic --Data Valid port
            -- Busy    : out std_logic  --Busy state port
          );
end component;

begin

Rec : Reciver
    generic map(
            Period => 868
            )
     port map (
            Clk     => CLK100MHZ,
            Rst     => ck_rst,
            Data    => uart_txd_in,
            Dout    => recived_data,
            DVal    => data_valid
     );

--extend the led_on pulse
edge_d: process(CLK100MHZ)
begin
    if rising_edge(CLK100MHZ) then
         if ck_rst = '0' then 
            counter <= 0;
            led0_b <= '0';
            led0_r <= '0';
            register_data <= (others => '0');
         end if;
         if data_valid = '1' then
            sample_data <= '1';
         end if;
         if sample_data = '1' then
            register_data <= recived_data;
            sample_data <= '0';
        end if;
        if register_data = data_eq then
            counter <= 1;
            led0_b <= '1';
        elsif register_data = data_po then
            counter <= 1;
            led0_r <= '1';
        end if;
        if (counter > 0) and (counter < led_on)then
            counter <= counter + 1;
        elsif counter = led_on then 
            counter <= 0;
            led0_b <= '0';
            led0_r <= '0';
            register_data <= (others => '0');
        end if;
    end if;
end process;

end Behavioral;
