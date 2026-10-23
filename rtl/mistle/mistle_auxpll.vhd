library ieee;
use ieee.std_logic_1164.all;

-- Fixed wrapper keeps real-valued ECP5 PLL calculations within VHDL.
-- Frequencies match the stable IcePi top: RTG 66 MHz / 330 MHz, USB 60 MHz.
entity mistle_auxpll is
  port (
    clk_i : in std_logic;
    clk_o : out std_logic_vector(3 downto 0);
    locked : out std_logic
  );
end entity;
architecture rtl of mistle_auxpll is
begin
  pll : entity work.ecp5pll
    generic map (
      in_hz => 50000000,
      out0_hz => 330000000, out0_tol_hz => 10000,
      out1_hz => 66000000, out1_tol_hz => 10000,
      out2_hz => 60000000, out2_tol_hz => 10000
    )
    port map (clk_i => clk_i, clk_o => clk_o, locked => locked);
end architecture;
-- vim: ts=2 sw=2 tw=120 et
