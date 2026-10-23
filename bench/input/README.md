# Companion input regression

Run `make -C bench/input test`. Adapted from the stable IcePi mouse-gating regression in commit
`e9c4c732fef7a6880d19d31ebbc9b77d5c2672e5`.

The test uses the production virtual-top toggle-to-strobe adapter, stable mouse counters and CIA keyboard consumer.
It checks signed X/Y deltas, wheel packets, both counter banks, keyboard deliveries, all four arrival phases,
five-clock event bursts and reset with a pending event. A held Companion event must not repeat while idle.
Unrelated virtual-top peripherals are not elaborated by this focused runner.
