# HK Row-Wise - Skeleton RTL

Questo documento definisce il contratto RTL target per il modulo di connettivita` del core di percolation: un Hoshen-Kopelman / Union-Find row-wise pensato per sintesi su FPGA.

## Entity Target

Il blocco target e` `percolation_hk_row_wise`.

```vhdl
entity percolation_hk_row_wise is
    generic (
        MAX_GRID   : integer := 128;
        MAX_CELLS  : integer := 128 * 128;
        LABEL_BITS : integer := 16
    );
    port (
        Clk           : in std_logic;
        Rst           : in std_logic; -- active low
        CfgInit       : in std_logic;
        GridSize      : in std_logic_vector(15 downto 0);
        Start         : in std_logic;
        RowOpen       : in std_logic_vector(MAX_GRID - 1 downto 0);
        RowValid      : in std_logic;
        Busy          : out std_logic;
        Done          : out std_logic;
        Spanning      : out std_logic;
        ConnStepCount : out std_logic_vector(31 downto 0)
    );
end entity;
```

## Obiettivo

Verificare se esiste un cluster che collega il bordo alto al bordo basso della griglia, senza usare un approccio globale con coda su tutta la matrice.

L'idea e` processare la griglia una riga alla volta, mantenendo solo lo stato minimo necessario:

- etichette della riga precedente
- etichette della riga corrente
- tabella delle equivalenze tra etichette
- flag di contatto con bordo alto e bordo basso per ogni componente attiva

## Perche row-wise

Il target e` una griglia grande, fino a 128x128, su Arty A7-100T.

Row-wise e` la scelta naturale perche:

- riduce la memoria viva a due righe di etichette invece di una scansione globale su tutta la griglia
- sfrutta bene il bank RNG 64-wide gia` presente nel progetto
- evita code e visite globali difficili da sintetizzare e costose in tempo di simulazione
- permette di chiudere una run con logica locale e prevedibile

## Contratto minimo con il core

Il modulo di connettivita` deve ricevere:

- `Start`: avvio di una nuova analisi sulla batch corrente
- `GridSize`: lato della griglia quadrata
- `RowOpen`: occupazione della riga corrente, in forma binaria compatta
- `RowValid`: strobe che presenta una nuova riga al blocco

E deve produrre:

- `Busy`: analisi della riga corrente in corso
- `Done`: analisi conclusa per tutta la griglia
- `Spanning`: cluster aperto sia in alto sia in basso
- `ConnStepCount`: metrica di lavoro del modulo di connettivita`

Per una griglia 128x128, il core puo` alimentare il modulo una riga alla volta, usando due burst da 64 bit per riga se la sorgente resta il bank RNG 64-wide.

## Skeleton di controllo

```text
IDLE:
    attende Start

WAIT_ROW:
    attende RowValid
    lancia la scansione della riga corrente

SCAN_ROW:
    processa una cella per ciclo
    aggiorna etichette, equivalenze e flag di bordo
    quando la riga termina:
        se ci sono altre righe -> WAIT_ROW
        altrimenti -> COMPLETE

COMPLETE:
    alza Done
    attende Start basso o CfgInit per ripartire
```

## Stato interno minimo

Il blocco puo` essere implementato con questi elementi:

- `prev_labels[x]`: label assegnata alla cella di colonna `x` nella riga precedente
- `curr_labels[x]`: label della riga corrente
- `parent[label]`: struttura union-find per risolvere equivalenze
- `touch_top[label]`: il componente tocca il bordo superiore
- `touch_bottom[label]`: il componente tocca il bordo inferiore
- `next_label`: prossimo identificatore libero

Per il minimo funzionale, la label table puo` essere dimensionata sul numero massimo di celle della griglia o su un bound equivalente conservativo.

## Regola di visita

Per ogni cella occupata della riga corrente:

1. leggi la label a sinistra nella riga corrente
2. leggi la label sopra nella riga precedente
3. se nessuno dei due esiste, crea una nuova label
4. se ne esiste uno solo, riusa quella label
5. se esistono entrambi e sono diversi, fai union delle due label
6. aggiorna i flag di bordo alto/basso della root risultante

Per ogni cella vuota:

- la label corrente resta zero
- nessuna union viene emessa

## Chiusura di una run

Alla fine dell'ultima riga:

- il modulo risolve le equivalenze residue
- verifica se esiste almeno una root con `touch_top = 1` e `touch_bottom = 1`
- alza `Spanning` se il cluster attraversa la griglia
- aggiorna `ConnStepCount` con il lavoro svolto

## Sequenza operativa

1. reset o `CfgInit`
2. inizializzazione della struttura union-find
3. avvio batch con `Start`
4. acquisizione di una riga alla volta con `RowValid`
5. scansione da sinistra a destra con assegnazione label
6. passaggio alla riga successiva mantenendo solo la memoria necessaria
7. completamento, compressione finale e decisione di spanning

## Interfaccia con il resto del progetto

Il core applicativo deve:

- generare la riga occupata via RNG
- passare la riga al blocco HK
- avanzare solo quando il blocco segnala che la riga e` stata consumata
- accumulare statistiche di run come occupazione e spanning

Questo evita di costruire un flusso globale, che nel progetto attuale e` utile come riferimento funzionale ma non e` la forma finale da portare in RTL.

## Obiettivo di sintesi

Il modulo deve essere scritto per una sintesi regolare:

- niente coda globale sull'intera griglia
- niente ricerca ricorsiva
- niente traversali globali non deterministiche
- stato locale e memoria esplicita, preferibilmente row-buffered

La metrica finale da preservare e` la correttezza funzionale con un costo di controllo molto piu` prevedibile dell'approccio globale.