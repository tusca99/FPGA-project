# BFS Frontier - Skeleton RTL

Questo documento definisce il contratto RTL target per il backend di connettivita` basato su BFS migliorato / frontier wavefront.

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
        GridData      : in std_logic_vector(MAX_CELLS - 1 downto 0);
        Busy          : out std_logic;
        Done          : out std_logic;
        Spanning      : out std_logic;
        ConnStepCount : out std_logic_vector(31 downto 0)
    );
end entity;
```

## Obiettivo

Verificare se esiste almeno un percorso continuo nella griglia, senza usare union-find e senza mantenere etichette di componente complete.

Il blocco lavora a frontiera:

- conserva il fronte attivo della ricerca
- marca le celle visitate
- espande i vicini validi al ciclo successivo
- si ferma quando la frontiera si svuota o quando raggiunge il bordo obiettivo

## Perche wavefront

Wavefront e` la forma piu` naturale per questo progetto perche:

- resta esatta
- evita una queue globale molto fine e costosa
- si presta bene al bank RNG 64-wide gia` presente nel core
- puo` coprire sia percolazione 2D classica sia casi direzionati con la stessa struttura

## Contratto minimo con il core

Il modulo di connettivita` deve ricevere:

- `Start`: avvio di una nuova analisi sulla batch corrente
- `GridSize`: lato della griglia quadrata
- `GridData`: occupazione della griglia gia` campionata

E deve produrre:

- `Busy`: elaborazione in corso
- `Done`: analisi conclusa per tutta la griglia
- `Spanning`: esiste un cammino tra sorgente e target
- `ConnStepCount`: metrica di lavoro del modulo di connettivita`

## Stato interno minimo

Il blocco puo` essere implementato con questi elementi:

- `frontier_curr`: bitmask della frontiera attiva corrente
- `frontier_next`: bitmask della frontiera del passo successivo
- `visited`: bitmap delle celle gia` esplorate
- `work_row`: buffer della riga o tile corrente
- `dir_mask`: maschera dei vicini ammessi, diversa tra 2D e caso direzionato

## Regola di espansione

Per ogni ciclo di espansione:

1. prendi la frontiera corrente
2. calcola i vicini ammessi in base alla direzione del problema
3. filtra solo le celle occupate e non ancora visitate
4. aggiorna la frontiera successiva
5. marca come visitate le nuove celle raggiunte

Per il caso 2D classico i vicini sono tipicamente quattro.
Per il caso direzionato i vicini sono solo quelli in avanti nel grafo del problema.

## Chiusura di una run

Alla fine della ricerca:

- se la frontiera ha raggiunto il bordo obiettivo, `Spanning = 1`
- altrimenti `Spanning = 0`
- `ConnStepCount` conta gli step di espansione o i cicli di frontiera consumati

## Sequenza operativa

1. reset o `CfgInit`
2. inizializzazione della frontiera iniziale
3. avvio batch con `Start`
4. espansione iterativa della frontiera
5. aggiornamento visited e del bordo raggiunto
6. completamento quando non resta piu` nulla da espandere

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
