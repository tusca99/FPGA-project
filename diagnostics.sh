#!/bin/bash
# FPGA Project Diagnostics - Check for missing entity references

PROJECT_ROOT="/media/leonardo-pieripoli/Storage/Archivio/PhysicsOfData/ProgrammableHardware/FPGA-project"

echo "=== ENTITY INSTANTIATION ANALYSIS ==="
echo ""
echo "Scanning for 'entity work.XXX' instantiations..."
echo ""

# Find all entity instantiations
grep -rn "entity work\." "$PROJECT_ROOT/project/" "$PROJECT_ROOT/RTL/" | grep -v "^Binary" | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    linenum=$(echo "$line" | cut -d: -f2)
    content=$(echo "$line" | cut -d: -f3-)
    
    # Extract entity name
    entity=$(echo "$content" | sed 's/.*entity work\.\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/')
    
    echo "File: $(basename "$file") (Line $linenum)"
    echo "  Instantiates: $entity"
done

echo ""
echo "=== ENTITY DEFINITIONS FOUND ==="
echo ""

# Find all entity definitions
find "$PROJECT_ROOT" -name "*.vhd" | sort | while read file; do
    if grep -q "^entity" "$file"; then
        entities=$(grep "^entity" "$file" | sed 's/entity //' | sed 's/ is$//')
        echo "File: $(basename "$file")"
        echo "  Defines: $entities"
    fi
done | sort

echo ""
echo "=== COMPILATION ORDER RECOMMENDATION ==="
echo ""
echo "Tier 1 (Dependencies - RTL/):"
echo "  1. ieee.std_logic_1164, ieee.numeric_std (built-in)"
echo "  2. a_rng_pkg.vhd (package definition)"
echo "  3. AES modules: reg.vhd, sbox.vhd, sub_byte.vhd, etc."
echo "  4. aes_enc.vhd"
echo "  5. rng_trivium.vhd"
echo ""
echo "Tier 2 (Application RNG - project/rng/):"
echo "  6. z_rng_trivium_array.vhd (uses rng_trivium)"
echo "  7. zz_rng_hybrid_64.vhd (uses aes_enc, trivium_array)"
echo ""
echo "Tier 3 (Percolation - project/percolation_core/):"
echo "  8. percolation_core.vhd (uses rng_hybrid_64)"
echo ""
echo "Tier 4 (UART - project/uart_message_bin/):"
echo "  9. baud_gen.vhd"
echo "  10. uart_tx.vhd, uart_rx.vhd"
echo "  11. uart_msg_*.vhd, uart_msg_loopback_top.vhd"
