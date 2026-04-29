# BFS Frontier - Current RTL Contract

Questo documento descrive il backend frontier row-wise attualmente usato dal core. Non e` una BFS full-grid: il modulo lavora a due righe, tenendo in memoria solo la riga corrente da riempire e la riga precedente gia` processata.

Nel core attuale il parametro runtime `GridSteps` / `CfgStepsPerRun` non cambia la larghezza del problema: la larghezza resta fissata dal generic `N_ROWS_G`. Il valore runtime decide quante righe processare.

## Entity Target

Il blocco target e` un motore di reachability a frontiera, pensato per percolazione 2D e per eventuali varianti direzionate.

```vhdl
entity percolation_bfs_frontier is
    generic (
        MAX_GRID   : integer := 128;
        MAX_CELLS  : integer := 128 * 128;
        FRONT_BITS : integer := 64;
        VISIT_BITS  : integer := 16;
        IDX_BITS    : integer := 14
    );
    port (
        Clk           : in std_logic;
        Rst           : in std_logic; -- active low
        CfgInit       : in std_logic;
        GridSize      : in std_logic_vector(15 downto 0);
        Start         : in std_logic;
        ChunkOpen     : in std_logic_vector(N_ROWS - 1 downto 0);
        ChunkValid    : in std_logic;
        Busy          : out std_logic;
        Done          : out std_logic;
        Spanning      : out std_logic;
        ConnStepCount : out std_logic_vector(31 downto 0)
    );
end entity;
```

## Obiettivo

Verificare se esiste almeno un percorso continuo nella griglia, senza usare union-find e senza mantenere etichette di componente complete.

Il blocco lavora a frontiera row-wise:

- conserva solo la riga corrente e quella precedente
- riceve una riga di occupazione gia` campionata dal RNG bank
- prima riempie la riga, poi la processa nel ciclo successivo
- si ferma quando la riga finale e` stata processata e non restano dati pendenti

## Perche wavefront

Wavefront e` la forma piu` naturale per questo progetto perche:

- resta esatta
- evita una queue globale molto fine e costosa
- si presta bene al bank RNG 64-wide gia` presente nel core
- puo` coprire sia percolazione 2D classica sia casi direzionati con la stessa struttura

## Contratto minimo con il core

Il modulo di connettivita` deve ricevere:

- `Start`: avvio di una nuova analisi sulla batch corrente
- `GridSize`: altezza richiesta della run, runtime-configurabile
- `ChunkOpen`: occupazione della riga corrente, 128 bit nel build attuale
- `ChunkValid`: indica quando `ChunkOpen` contiene una riga valida

E deve produrre:

- `Busy`: elaborazione in corso o capture in corso
- `Done`: analisi conclusa per tutta la griglia
- `Spanning`: esiste un cammino tra sorgente e target
- `ConnStepCount`: metrica di lavoro del modulo di connettivita`

## Stato interno minimo

Il blocco puo` essere implementato con questi elementi:

- `current_open_row`: buffer della riga corrente ancora in riempimento
- `previous_reach_row`: buffer della riga precedente gia` processata
- `seed_row`: riga di seed per la propagazione verticale
- `conn_steps_total`: metrica cumulativa di lavoro
- `p_spanning`: flag finale di spanning

## Regola di espansione

Per ogni ciclo di clock utile:

1. se `ChunkValid = '1'`, latci la riga corrente dal RNG bank
2. prepara il seed verticale dalla riga precedente
3. nel ciclo successivo, processa la riga latcheata con la dilatazione bitmask a 7 stage
4. aggiorna `previous_reach_row`
5. incrementa `ConnStepCount`

Per il caso 2D classico i vicini sono tipicamente quattro.
Per il caso direzionato i vicini sono solo quelli in avanti nel grafo del problema.

## Chiusura di una run

Alla fine della ricerca:

- se la frontiera ha raggiunto il bordo obiettivo, `Spanning = 1`
- altrimenti `Spanning = 0`
- `ConnStepCount` conta gli step di espansione o i cicli di frontiera consumati

## Sequenza operativa

1. reset o `CfgInit`
2. `Start` porta il blocco in capture della prima riga
3. al ciclo successivo la riga viene processata
4. la riga seguente viene acquisita mentre quella precedente viene processata
5. il blocco mantiene memoria solo di due righe, non dell'intera griglia
6. completamento quando l'ultima riga e` stata processata e non resta nulla da espandere

## Interfaccia con il resto del progetto

Il core applicativo deve:

- presentare la griglia occupata al backend
- avviare il motore di reachability
- attendere `Done`
- accumulare statistiche di run come occupazione e spanning

Questo backend e` piu` adatto quando interessa la reachability esatta e il throughput pratico, non le etichette complete delle componenti.

## Obiettivo di sintesi

Il modulo deve essere scritto per una sintesi regolare:

- niente union-find globale
- niente ricerca root lunga
- niente recursion
- stato esplicito e frontiera bit-parallel

La metrica finale da preservare e` la correttezza funzionale con un costo di controllo piu` prevedibile dell'approccio HK completo.

## Variante piu` sintetizzabile

La chiusura orizzontale della riga non va pensata come un loop da 128 celle dentro un unico processo combinatorio. L'implementazione attuale usa 7 stage espliciti di dilatazione bitmask, uno per ciascuna potenza di due fino a `64`, coerenti con `MAX_GRID = 128`.

Regola per uno stage:

$$
reach \leftarrow reach \lor ((reach \ll d) \lor (reach \gg d)) \land open
$$

con `d = 1, 2, 4, 8, 16, 32, 64`.

Questo approccio e` semanticamente equivalente alla chiusura della riga, ma non e` il loop naïve:

- stesso risultato della scansione lineare, ma con pochi stage fissi
- profondita` combinatoria molto piu` bassa
- timing piu` facile da chiudere rispetto al blob cella-per-cella
- area in genere piu` controllata, con un piccolo costo extra per la logica di stage rispetto a una riga sequenziale pura

Per il target FPGA di questo progetto, il compromesso migliore e`:

- evitare la catena cella-per-cella completamente combinatoria
- usare un network bitmask a stage fissi
- tenere la frontiera come mask bit-parallel, non come queue fine-grained

In pratica: stesso risultato logico, costo di clock molto piu` prevedibile, area spesso migliore del blob combinatorio attuale, ma non identica in termini di risorse rispetto a una versione sequenziale a 1 cella per clock.

## Nota su `N_ROWS`

`N_ROWS` e` una larghezza di lane a compile time, non un parametro UART runtime. Se vuoi cambiare il numero di lane RNG via UART, serve un refactor architetturale: package parametrici o generics propagati a tutto il bank RNG, ai tipi array e ai moduli di connettivita`.

Il backend corrente usa `GridSteps` come altezza della striscia: la larghezza resta fissa, la profondita` cresce con il parametro runtime.

Il network bitmask attuale ha 7 stage espliciti con shift 1, 2, 4, 8, 16, 32 e 64: questo copre correttamente larghezze fino a circa 128 colonne. Se vuoi andare in migliaia di colonne, il frontend va rifatto con piu` stage o con un'altra architettura di propagazione.
