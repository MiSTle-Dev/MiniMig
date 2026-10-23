-- A simple audio filter to provide a first-level emulation of the Amiga's audio filter.
-- Not intended to be accurate - just good enough for the special effects in 
-- Lotus Esprit Turbo Challenge when going through tunnels to be audible.

-- Implemented as a simple 1st order IIR filter

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audiofilter is
port(
	clk : in std_logic;
	filter_ena : in std_logic;
	audio_in_left : in signed(15 downto 0);
	audio_in_right : in signed(15 downto 0);
	audio_out_left : out signed(15 downto 0);
	audio_out_right : out signed(15 downto 0)	
);
end entity;

architecture behavioural of audiofilter is

signal clkdiv : unsigned (7 downto 0);

signal y_n_left : signed(18 downto 0);
signal y_n_right : signed(18 downto 0);

signal y_nminus1 : signed(18 downto 0);
signal y_nminus1_shifted : signed(18 downto 0);

signal x_n : signed(15 downto 0);
signal x_n_ext : signed(18 downto 0);

signal sum : signed(18 downto 0);

begin

-- Multiplex input based on high bit of clkdiv
x_n <= audio_in_left when clkdiv(1)='1' else audio_in_right;
-- Sign extend
x_n_ext <= x_n(15) & x_n(15) & x_n(15) & x_n;

-- Select which channel the previous value comes from...
y_nminus1 <= y_n_left when clkdiv(1)='1' else y_n_right;
-- Shift and sign-extend.
y_nminus1_shifted <= y_nminus1(18) & y_nminus1(18) & y_nminus1(18) & y_nminus1(18 downto 3);

-- Output multiplexers - bypass filter when filter_ena is low.
audio_out_left <= y_n_left(18 downto 3); -- when filter_ena='1' else audio_in_left;
audio_out_right <= y_n_right(18 downto 3); -- when filter_ena='1' else audio_in_right;

process(clk)
begin
	if rising_edge(clk) then
		clkdiv<=clkdiv+1;
		
		-- The IIR filter equation is very simple:
		-- y[n] = y[n-1] + ((x[n] - y[n-1])>>3)

		sum <= y_nminus1 + x_n_ext - y_nminus1_shifted;

		if (filter_ena='1' and clkdiv(7 downto 0)="00000001") or (filter_ena='0' and clkdiv(1 downto 0)="01") then
			y_n_right<=sum;
		elsif (filter_ena='1' and clkdiv(7 downto 0)="10000011") or (filter_ena='0' and clkdiv(1 downto 0)="11") then
			y_n_left<=sum;
		end if;
	end if;
end process;

end architecture;
