"""Allow `python -m percolation_uart.analysis` to work as before."""

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())
