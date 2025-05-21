#!/usr/bin/env python3

from PIL import Image
import json
import sys

def png_to_grid(path, grid_size_px):
    img = Image.open(path).convert("RGB")
    width, height = img.size
    cells_x = width // grid_size_px
    cells_y = height // grid_size_px

    grid = []
    for i in range(cells_y):
        row = []
        for j in range(cells_x):
            x = j * grid_size_px
            y = i * grid_size_px
            r, g, b = img.getpixel((x, y))
            # dark = alive, threshold RGB sum < 384 (i.e. avg < 128)
            row.append(1 if r + g + b < 384 else 0)
        grid.append(row)

    return grid

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: png2grid.py <image.png> <grid_size_px>")
        sys.exit(1)

    path = sys.argv[1]
    grid_size_px = int(sys.argv[2])
    grid = png_to_grid(path, grid_size_px)

#    for row in grid:
#        print(row)

    print(json.dumps(grid))
