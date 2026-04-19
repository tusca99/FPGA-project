# HK Row-Wise - Documento di Implementazione

Questo documento descrive il modulo di connettivita` target per il core di percolation: un Hoshen-Kopelman / Union-Find row-wise pensato per sintesi su FPGA.

## Obiettivo

Verificare se esiste un cluster che collega il bordo alto al bordo basso della griglia, senza usare una BFS globale con coda su tutta la matrice.

L'idea e` processare la griglia una riga alla volta, mantenendo solo lo stato minimo necessario:

- etichette della riga precedente
- etichette della riga corrente
- tabella delle equivalenze tra etichette
- flag di contatto con bordo alto e bordo basso per ogni componente attiva

## Perche row-wise

Il target e` una griglia grande, fino a 128x128, su Arty A7-100T.

Row-wise e` la scelta naturale perche:

- riduce la memoria viva a due righe di etichette invece di una BFS su tutta la griglia
- sfrutta bene il bank RNG 64-wide gia` presente nel progetto
- evita code e visite globali difficili da sintetizzare e costose in tempo di simulazione
- permette di chiudere una run con logica locale e prevedibile

## Contratto minimo con il core

Il modulo di connettivita` deve ricevere:

- `Start`: avvio di una nuova analisi su una griglia completa
- `GridSize`: lato della griglia quadrata
- `RowOpen`: occupazione della riga corrente, in forma binaria compatta
- `RowValid`: validita` della riga corrente

E deve produrre:

- `Busy`: analisi in corso
- `Done`: analisi conclusa
- `Spanning`: cluster aperto sia in alto sia in basso
- `ConnStepCount`: metrica di lavoro del modulo di connettivita`

Per una griglia 128x128, il core puo` alimentare il modulo una riga alla volta, usando due burst da 64 bit per riga se la sorgente resta il bank RNG 64-wide.

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
3. acquisizione della prima riga di occupazione
4. scansione da sinistra a destra con assegnazione label
5. passaggio alla riga successiva mantenendo solo la memoria necessaria
6. completamento, compressione finale e decisione di spanning

## Pseudocodice

```text
on Start:
    clear labels and equivalence table
    next_label := 1

for each row in grid:
    for each cell in row:
        if cell is empty:
            curr_labels[x] := 0
        else:
            left := curr_labels[x - 1] if x > 0 else 0
            up   := prev_labels[x]

            if left = 0 and up = 0:
                curr_labels[x] := new_label()
            elsif left /= 0 and up = 0:
                curr_labels[x] := root(left)
            elsif left = 0 and up /= 0:
                curr_labels[x] := root(up)
            else:
                curr_labels[x] := union(left, up)

            update boundary flags on the root

    prev_labels := curr_labels

at the last row:
    spanning := any root with touch_top and touch_bottom
    Done := 1
```

## Interfaccia con il resto del progetto

Il core applicativo deve:

- generare la riga occupata via RNG
- passare la riga al blocco HK
- avanzare solo quando il blocco segnala che la riga e` stata consumata
- accumulare statistiche di run come occupazione e spanning

Questo evita di costruire una BFS globale, che nel progetto attuale e` utile come riferimento funzionale ma non e` la forma finale da portare in RTL.

## Obiettivo di sintesi

Il modulo deve essere scritto per una sintesi regolare:

- niente coda BFS sull'intera griglia
- niente ricerca ricorsiva
- niente traversali globali non deterministiche
- stato locale e memoria esplicita, preferibilmente row-buffered

La metrica finale da preservare e` la correttezza funzionale con un costo di controllo molto piu` prevedibile della BFS.