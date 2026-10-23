-- A dirty audio mixer which avoids attenuation by clipping extremities
--
-- Copyright 2020, 2024 by Alastair M. Robinson

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity AudioMix is
generic (
	signalwidth : integer := 16;
	volumewidth : integer := 8
);
port (
	clk : in std_logic;
	reset_n : in std_logic;
	swap_channels : in std_logic;

	audio_in_l1 : in signed(signalwidth-1 downto 0);
	audio_in_r1 : in signed(signalwidth-1 downto 0);
	audio_vol1 : in unsigned(volumewidth-1 downto 0);

	audio_in_l2 : in signed(signalwidth-1 downto 0);
	audio_in_r2 : in signed(signalwidth-1 downto 0);
	audio_vol2 : in unsigned(volumewidth-1 downto 0);

	audio_in_r3 : in signed(signalwidth-1 downto 0);
	audio_in_l3 : in signed(signalwidth-1 downto 0);
	audio_vol3 : in unsigned(volumewidth-1 downto 0);

	audio_in_l4 : in signed(signalwidth-1 downto 0);
	audio_in_r4 : in signed(signalwidth-1 downto 0);
	audio_vol4 : in unsigned(volumewidth-1 downto 0);

	audio_in_l5 : in signed(signalwidth-1 downto 0);
	audio_in_r5 : in signed(signalwidth-1 downto 0);
	audio_vol5 : in unsigned(volumewidth-1 downto 0);

	audio_l : out signed(signalwidth+volumewidth-1 downto 0);
	audio_r : out signed(signalwidth+volumewidth-1 downto 0);
	audio_overflow : out std_logic
);
end entity;

architecture rtl of AudioMix is
signal inmux_sel : unsigned(3 downto 0) := "0000";
signal inmux : signed(signalwidth downto 0);
signal volmux : signed(volumewidth+1 downto 0);
signal scaled_in : signed(signalwidth+volumewidth+2 downto 0);
signal accumulator : signed(signalwidth+volumewidth+2 downto 0);
signal headroom : signed(3 downto 0);
signal headroom_r : signed(3 downto 0);

signal overflow : std_logic;
signal clipped : signed(signalwidth+volumewidth-1 downto 0);
signal clamped : signed(signalwidth+volumewidth-1 downto 0);
begin

	process(clk) begin
		if rising_edge(clk) then
			inmux_sel<=inmux_sel+1;
		end if;
	end process;

	-- Select an input and sign extend by 1 bit
	with inmux_sel select inmux(signalwidth-1 downto 0) <=
		audio_in_l1 when "0000",
		audio_in_l2 when "0001",
		audio_in_l3 when "0010",
		audio_in_l4 when "0011",
		audio_in_l5 when "0100",
		audio_in_r1 when "1000",
		audio_in_r2 when "1001",
		audio_in_r3 when "1010",
		audio_in_r4 when "1011",
		audio_in_r5 when others;

	inmux(signalwidth) <= inmux(signalwidth-1);

	-- Select a volume input and shift one space left.
	with inmux_sel(2 downto 0) select volmux(volumewidth downto 1) <=
		signed(audio_vol1) when "000",
		signed(audio_vol2) when "001",
		signed(audio_vol3) when "010",
		signed(audio_vol4) when "011",
		signed(audio_vol5) when others;

	volmux(0)<='0';
	volmux(volmux'high)<='0';

	-- Scale the input signal and add to the accumulator.
	-- Clear the accumulator twice in the cycle, after processing the last input channel (once for left, once for right).
	
	process(clk) begin
		if rising_edge(clk) then
			scaled_in <= inmux * volmux;
			accumulator <= accumulator + scaled_in;

			if inmux_sel(2 downto 0)="000" then
				accumulator <= (others => '0');
			end if;

		end if;
	end process;
	
	-- Clip the summed audio

	headroom <= accumulator(signalwidth+volumewidth+2 downto signalwidth+volumewidth-1);
	overflow <=
		'0' when headroom = "0000" else
		'0' when headroom = "1111" else
		'1';
	clamped(signalwidth+volumewidth-1)<=accumulator(accumulator'high);
	clamped(signalwidth+volumewidth-2 downto 0) <= (others => not accumulator(accumulator'high));
	clipped <= accumulator(signalwidth+volumewidth-1 downto 0) when overflow='0' else clamped;

	-- Output summed and clipped audio immediately after the last channel has been added in.
	
	process(clk)
	begin
		if rising_edge(clk) then
		    audio_overflow<=overflow;

			if inmux_sel(3 downto 0) = (not swap_channels) & "110" then
				audio_l<=clipped(signalwidth+volumewidth-1 downto 0);
			end if;

			if inmux_sel(3 downto 0) = swap_channels&"110" then
				audio_r<=clipped(signalwidth+volumewidth-1 downto 0);
			end if;

		end if;
	end process;

end architecture;
