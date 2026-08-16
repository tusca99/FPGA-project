import matplotlib.pyplot as plt
import numpy as np
import random

def generate_percolation_grid(size=8, p=0.6, directed=False):
    # Generate grid
    grid = np.random.choice([0, 1], size=(size, size), p=[1-p, p])
    
    # Simple BFS to find a spanning path
    # For directed, we only move down, left, right
    def get_neighbors(pos):
        x, y = pos
        neighbors = []
        # Always allow horizontal
        for dx in [-1, 1]:
            nx, ny = x + dx, y
            if 0 <= nx < size and 0 <= ny < size:
                neighbors.append((nx, ny))
        # Allow down (for directed) or both (for isotropic)
        if directed:
            # In Directed Percolation, flow is primarily downward
            # We allow moving down (y-1)
            nx, ny = x, y - 1
            if 0 <= nx < size and 0 <= ny < size:
                neighbors.append((nx, ny))
        else:
            for dy in [-1, 1]:
                nx, ny = x, y + dy
                if 0 <= nx < size and 0 <= ny < size:
                    neighbors.append((nx, ny))
        return neighbors

    # Find any spanning path from top row to bottom row
    # Use a simple BFS/DFS to find a path
    start_nodes = [(x, size-1) for x in range(size) if grid[size-1, x] == 1]
    if not start_nodes:
        return generate_percolation_grid(size, p, directed) # Retry

    queue = [(node, [node]) for node in start_nodes]
    visited = set(start_nodes)
    
    while queue:
        (curr, path) = queue.pop(0)
        if curr[1] == 0:
            return grid, path
        
        for neighbor in get_neighbors(curr):
            if neighbor not in visited and grid[neighbor[1], neighbor[0]] == 1:
                visited.add(neighbor)
                queue.append((neighbor, path + [neighbor]))
                
    return generate_percolation_grid(size, p, directed) # Retry if no path found

def plot_grid(grid, path, filename, title, directed=False):
    size = grid.shape[0]
    fig, ax = plt.subplots(figsize=(4, 4))
    
    # Plot sites
    for x in range(size):
        for y in range(size):
            color = 'lightblue' if grid[y, x] == 1 else 'lightgray'
            edge = 'blue' if grid[y, x] == 1 else 'gray'
            rect = plt.Rectangle((x-0.5, y-0.5), 1, 1, facecolor=color, edgecolor=edge, linewidth=1)
            ax.add_patch(rect)
            
    # Plot path
    px = [p[0] for p in path]
    py = [p[1] for p in path]
    
    if directed:
        # Draw as segments with arrows
        for i in range(len(path)-1):
            p1 = path[i]
            p2 = path[i+1]
            ax.annotate('', xy=(p2[0], p2[1]), xytext=(p1[0], p1[1]),
                        arrowprops=dict(arrowstyle='->', color='red', lw=3))
    else:
        ax.plot(px, py, color='red', linewidth=3, marker='o', markersize=4)
    
    ax.set_xlim(-0.5, size-0.5)
    ax.set_ylim(-0.5, size-0.5)
    ax.set_aspect('equal')
    ax.axis('off')
    plt.title(title)
    plt.savefig(filename, bbox_inches='tight', pad_inches=0, dpi=300)
    plt.close()

if __name__ == "__main__":
    # Isotropic
    grid_iso, path_iso = generate_percolation_grid(8, 0.6, directed=False)
    plot_grid(grid_iso, path_iso, "percolation_isotropic.png", "Isotropic Percolation", directed=False)
    
    # Directed
    grid_dir, path_dir = generate_percolation_grid(8, 0.6, directed=True)
    plot_grid(grid_dir, path_dir, "percolation_directed.png", "Directed Percolation", directed=True)
    print("Images generated: percolation_isotropic.png, percolation_directed.png")
