"""
Remove white/near-white backgrounds from sprites, replacing with transparency.
Uses flood-fill from corners so interior white areas (eyes, teeth etc) are preserved.

Usage:
  python strip_bg.py assets/sprites/player/*.png
  python strip_bg.py path/to/sprite.png --threshold 240
"""

import sys
import argparse
import numpy as np
from PIL import Image
from pathlib import Path
from collections import deque


def flood_fill_alpha(img_array: np.ndarray, threshold: int) -> np.ndarray:
    h, w = img_array.shape[:2]
    result = img_array.copy()
    visited = np.zeros((h, w), dtype=bool)
    queue = deque()

    # Seed from all four edges
    for x in range(w):
        queue.append((0, x))
        queue.append((h - 1, x))
    for y in range(1, h - 1):
        queue.append((y, 0))
        queue.append((y, w - 1))

    while queue:
        y, x = queue.popleft()
        if visited[y, x]:
            continue
        visited[y, x] = True
        r, g, b = result[y, x, 0], result[y, x, 1], result[y, x, 2]
        if r >= threshold and g >= threshold and b >= threshold:
            result[y, x, 3] = 0
            for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                    queue.append((ny, nx))

    return result


def strip(path: Path, threshold: int) -> None:
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    arr = flood_fill_alpha(arr, threshold)
    result = Image.fromarray(arr)
    result.save(path)
    print(f"  stripped: {path.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", help="PNG files to process")
    parser.add_argument("--threshold", type=int, default=240)
    args = parser.parse_args()

    for f in args.files:
        strip(Path(f), args.threshold)
    print(f"Done. {len(args.files)} file(s) processed.")
