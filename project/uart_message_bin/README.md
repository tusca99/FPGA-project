# UART message binary minimal scaffold

Obiettivo: gestire messaggi binari a lunghezza fissa in byte, senza ASCII parser.

## Convenzione

- `N_BYTES` e` un generic.
- I dati sono impacchettati in `std_logic_vector(N_BYTES*8-1 downto 0)`.
- Byte 0 e` il primo byte trasmesso/ricevuto.
- RX alza `msg_valid` quando ha raccolto esattamente `N_BYTES` byte.
- TX parte con `msg_start` e alza `busy` fino a fine trasmissione.

## Blocchi

- `baud_gen.vhd`: generatore di tick riusabile condiviso tra TX e RX.
- `uart_msg_rx.vhd`: riceve un messaggio fisso e lo presenta su bus parallelo.
- `uart_msg_tx.vhd`: trasmette un messaggio fisso da bus parallelo.
- `uart_msg_loopback_top.vhd`: top di benchmark per loopback e misura della latenza applicativa.

## Dipendenze

Questi wrapper riusano i blocchi gia` esistenti nel ramo modulare:

- `baud_gen.vhd`
- `uart_rx.vhd`
- `uart_tx.vhd`

## Nota

`uart_msg_loopback_top.vhd` instanzia un solo `baud_gen.vhd` e lo condivide tra RX e TX.

Questa cartella e` pensata come base binaria minimale. La modalita` ASCII puo` essere aggiunta dopo, come strato separato.
