# Percolation Core - Schema Concettuale

Questo file spiega, in modo semplice, cosa fa il core di percolazione in [percolation_core.vhd](percolation_core.vhd).

## Idea generale

Il core esegue molte volte la stessa prova:

1. costruisce una griglia quadrata di celle
2. decide in modo pseudo-casuale quali celle sono occupate tramite un bank RNG separato 64-wide
3. controlla se esiste un percorso connesso dall'alto al basso
4. aggiorna alcune statistiche
5. ripete per il numero di run richiesto

In pratica risponde a questa domanda:

"Con una certa probabilità di occupazione `p`, quante volte una griglia casuale percola?"

## Interfaccia in parole povere

- `Rst` azzera tutto
- `CfgInit` carica i parametri e resetta lo stato interno
- `RunEn` dice al core di partire
- `StepAddValid` e `StepAddCount` aggiungono run in coda
- `CfgP` imposta la probabilità di occupazione
- `CfgGridSize` imposta la dimensione della griglia
- `CfgSeed` imposta il seed del bank RNG
- `CfgRuns` imposta quanti run fare al massimo

Le uscite sono solo statistiche:

- `StepCount` = quanti run sono stati completati
- `PendingSteps` = quanti run restano in coda
- `SpanningCount` = quanti run hanno avuto percolazione
- `TotalOccupied` = somma delle celle occupate su tutti i run
- `MeanOccupied` = media delle celle occupate per run

## Contratto tra RNG e connettività

La generazione casuale e la connettività devono restare separabili. Il contratto minimo tra i blocchi e` questo:

- `rng_hybrid_64`
    - `rst`: re-inizializza il bank RNG e riparte dal seed configurato
    - `master_key` / `run_tag`: diversificazione iniziale della sequenza
    - `threshold`: soglia di occupazione `p`
    - `site_open(63 downto 0)`: 64 bit di occupazione per colonna
    - `busy`: vale `1` mentre il bank si inizializza
- blocco di connettivita` / BFS
    - consuma `site_open` come sample casuale già confrontato con `p`
    - non conosce taps, seed o dettagli del RNG
    - decide solo se il cluster attraversa la griglia e aggiorna lo spanning

Questo contratto permette di sostituire il PRNG con un bank RNG diverso senza toccare la logica di spanning.

## Top applicativo sottile

Il passo successivo e` un wrapper di integrazione che parla con UART e non contiene logica algoritmica. Il suo compito e`:

- ricevere configurazione, seed e comandi start/stop/step
- trasferire i parametri al core
- leggere le statistiche a fine run o su richiesta
- esporre una superficie stabile per Python e benchmark

Questo top non deve duplicare il lavoro del core: non costruisce la griglia, non fa BFS e non genera numeri casuali.

### Frame binari del wrapper

Il top applicativo usa messaggi binari a lunghezza fissa:

- request: 24 byte totali, organizzati in 6 word da 32 bit
    - word 0: `CfgP`
    - word 1: `CfgGridSize` nei 16 bit meno significativi
    - word 2: `CfgSeed`
    - word 3: `CfgRuns`
    - word 4: `ctrl` con i bit di start/init/step
    - word 5: `StepAddCount`
- response: 20 byte totali, organizzati in 5 word da 32 bit
    - word 0: `StepCount`
    - word 1: `PendingSteps`
    - word 2: `SpanningCount`
    - word 3: `TotalOccupied`
    - word 4: `MeanOccupied`

Questo layout mantiene il wrapper molto semplice e permette di fare un controllo Python diretto senza parsing testuale.

## Cosa fa davvero il codice

Il core non fa una simulazione continua nel tempo.
Fa sempre questo ciclo:

- prepara una griglia casuale
- prepara la griglia prendendo una colonna alla volta dal bank RNG 64-wide
- cerca un cluster connesso partendo dal bordo alto con una BFS flood fill
- se il cluster arriva al bordo basso, conta un evento di spanning
- aggiorna i contatori
- decide se rifare tutto da capo

La parte casuale e` isolata nel bank `rng_hybrid_64`, quindi il core puo` essere letto come due passi distinti: campionamento random e verifica della connettivita`.

## Pseudocodice

```text
on reset:
    azzera stati e contatori

on CfgInit:
    carica grid size, p, seed e numero massimo di run
    azzera le statistiche

if RunEn = 1 or ci sono step in coda:
    se non ho già finito tutti i run richiesti:
        while non ho riempito tutta la griglia:
            prendi 64 bit di occupazione dal bank RNG
            scrivili nella colonna corrente della griglia
            conta le celle occupate

        prendi tutte le celle occupate della prima riga
        mettile in una coda BFS

        while la coda non è vuota:
            estrai una cella
            controlla i 4 vicini
            se un vicino è occupato e non visitato:
                marcialo come visitato
                mettilo in coda
            se arrivo all'ultima riga:
                segna spanning = vero

        incrementa StepCount
        se spanning = vero:
            incrementa SpanningCount
        aggiorna TotalOccupied e MeanOccupied

        se servono altri run:
            riparti con una nuova griglia
        altrimenti:
            torna in IDLE
```

## Flowchart

```mermaid
flowchart TD
    A[Reset or start] --> B[Load config with CfgInit]
    B --> C[Wait in IDLE]
    C -->|RunEn or pending steps| D[Generate grid cell by cell]
    D --> E[Use RNG bank to decide occupied or empty]
    E --> F[Seed BFS from top row occupied cells]
    F --> G[Pop one cell from queue]
    G --> H[Check 4 neighbors]
    H --> I[Mark visited and enqueue occupied neighbors]
    I --> J{Reached bottom row?}
    J -->|Yes| K[Set spanning flag]
    J -->|No| L[Continue BFS]
    K --> L
    L --> M{Queue empty?}
    M -->|No| G
    M -->|Yes| N[Update counters]
    N --> O[StepCount + 1]
    N --> P[SpanningCount if spanning]
    N --> Q[TotalOccupied and MeanOccupied]
    O --> R{More runs needed?}
    P --> R
    Q --> R
    R -->|Yes| D
    R -->|No| C
```

## Esempio mentale

Immagina una griglia piccola, per esempio 4x4.

- alcune celle sono accese
- il core parte dalle celle accese della riga superiore
- esplora tutte quelle collegate
- se trova una cella della riga inferiore, vuol dire che c'è un cammino completo dall'alto al basso

Quindi il core non cerca "la strada migliore": cerca solo se **esiste almeno un collegamento continuo**.

## Cosa significa per il benchmark

Questo core è interessante perché separa bene due tempi diversi:

- tempo UART: mandare i parametri dentro e riportare fuori le statistiche
- tempo del core: generare la griglia, fare la BFS e aggiornare i contatori

Per il benchmark conviene tenere fisso il messaggio UART e sottrarre il suo costo, così misuri meglio il lavoro vero del core.

## Nota importante

Il codice attuale usa una **BFS flood fill**, non un Hoshen-Kopelman classico. La logica è più semplice da capire, ma il principio fisico resta lo stesso: verificare se esiste un cluster che attraversa la griglia.

La generazione casuale è già separata nel bank `rng_hybrid_64`, così in futuro si può migliorare o sostituire il PRNG senza toccare la parte di connettività.
