# VHDL Interface for a Trivium Array

> Nota: l'esempio usa 64 componenti, ma nel build attuale del progetto il bank RNG e` parametrizzato con `N_ROWS = 128`.

In VHDL you can use an **array of component instances** generated with a `for...generate` statement. This is the canonical way to instantiate parametric arrays of the same component.

---

## Core Concepts

### 1. Define Array Types for Ports

Since each Trivium has multi-bit ports, you need to define custom array types, typically in a **package**:

```vhdl
package trivium_pkg is

    constant N_ROWS     : integer := 64;
    constant KEY_WIDTH  : integer := 80;
    constant IV_WIDTH   : integer := 80;
    constant OUT_WIDTH  : integer := 32;

    type key_array_t    is array (0 to N_ROWS-1) of std_logic_vector(KEY_WIDTH-1 downto 0);
    type iv_array_t     is array (0 to N_ROWS-1) of std_logic_vector(IV_WIDTH-1 downto 0);
    type word_array_t   is array (0 to N_ROWS-1) of std_logic_vector(OUT_WIDTH-1 downto 0);
    type flag_array_t   is array (0 to N_ROWS-1) of std_logic;

end package trivium_pkg;
```

---

### 2. Trivium Component Declaration

```vhdl
component trivium is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        key        : in  std_logic_vector(79 downto 0);
        iv         : in  std_logic_vector(79 downto 0);
        load       : in  std_logic;       -- pulse to load key+IV
        warm_done  : out std_logic;       -- high after 1152 cycles
        data_out   : out std_logic_vector(31 downto 0);
        valid      : out std_logic        -- data_out is valid (post warmup)
    );
end component;
```

---

### 3. Top-Level Entity Using the Array Types

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use work.trivium_pkg.all;

entity trivium_array is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        -- AES-derived seeds (loaded at init/reseed)
        keys       : in  key_array_t;           -- 64 × 80-bit keys
        ivs        : in  iv_array_t;            -- 64 × 80-bit IVs
        load       : in  std_logic;             -- broadcast load pulse
        -- Outputs
        words_out  : out word_array_t;          -- 64 × 32-bit words/cycle
        valid_mask : out flag_array_t;          -- per-instance valid flags
        all_valid  : out std_logic              -- AND of all valid flags
    );
end entity trivium_array;
```

---

### 4. Generate Statement — The Key Construct

```vhdl
architecture rtl of trivium_array is

    signal valid_vec : flag_array_t;

begin

    -- Instantiate 64 Trivium cores with a single generate statement
    GEN_TRIVIUM : for i in 0 to N_ROWS-1 generate
        u_trivium : trivium
            port map (
                clk       => clk,
                rst       => rst,
                key       => keys(i),
                iv        => ivs(i),
                load      => load,
                warm_done => valid_vec(i),
                data_out  => words_out(i),
                valid     => valid_vec(i)
            );
    end generate GEN_TRIVIUM;

    -- Aggregate valid flags
    valid_mask <= valid_vec;

    PROC_ALL_VALID : process(valid_vec)
        variable v : std_logic := '1';
    begin
        v := '1';
        for i in 0 to N_ROWS-1 loop
            v := v and valid_vec(i);
        end loop;
        all_valid <= v;
    end process;

end architecture rtl;
```

---

### 5. Connecting to the Threshold Comparator Layer

You can extend the top-level to include the comparison logic in the same generate block:

```vhdl
architecture rtl of trivium_array is

    signal words_internal : word_array_t;
    signal valid_vec      : flag_array_t;

begin

    GEN_TRIVIUM : for i in 0 to N_ROWS-1 generate

        -- RNG instance
        u_trivium : trivium
            port map (
                clk      => clk,
                rst      => rst,
                key      => keys(i),
                iv       => ivs(i),
                load     => load,
                data_out => words_internal(i),
                valid    => valid_vec(i)
            );

        -- Inline comparator: site open if word < threshold
        site_open(i) <= '1' when (valid_vec(i) = '1' and
                                  unsigned(words_internal(i)) < unsigned(threshold))
                        else '0';

    end generate GEN_TRIVIUM;

end architecture rtl;
```

Where `site_open` is a `flag_array_t` output representing the percolation state of all 64 sites in the current column.

---

## VHDL-2008 Shorthand

If your toolchain supports it (Vivado does — enable under **Project Settings → General → VHDL standard**), you can declare array types inline without a package and use `all` sensitivity lists:

```vhdl
-- Inline type declaration (VHDL-2008 only)
signal words_out : array (0 to 63) of std_logic_vector(31 downto 0);

-- Process with all sensitivity list
process(all) is
begin
    ...
end process;
```

---

## Summary of the Pattern

| Construct | Purpose |
|---|---|
| `package` with array types | Clean port interfaces for multi-instance designs |
| `for...generate` | Synthesises N identical component instances |
| Per-instance indexing `keys(i)`, `ivs(i)` | Routes distinct seeds to each Trivium |
| Inline logic inside `generate` | Collocates comparator with each RNG instance |
| `all_valid` aggregation | Single ready signal for the percolation controller FSM |

This is the standard VHDL idiom for regular parallel structures. Vivado's synthesiser handles it efficiently — the 64 instances will be inferred as independent logic trees with no resource sharing unless explicitly requested.