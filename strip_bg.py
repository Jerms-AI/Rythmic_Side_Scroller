"""
Remove white/near-white backgrounds from sprites, replacing with transparency.
Uses flood-fill from corners so interior white areas (eyes, teeth etc) are preserved,
then feathers the edges to eliminate white pixel fringe.

Usage:
  python strip_bg.py assets/sprites/player/*.png
  python strip_bg.py path/to/sprite.png --threshold 240 --feather 210
"""

import argparse
import numpy as np
from PIL import Image
from pathlib import Path
from collections import deque


def flood_fill_alpha(arr: np.ndarray, threshold: int) -> np.ndarray:
    h, w = arr.shape[:2]
    result = arr.copy()
    visited = np.zeros((h, w), dtype=bool)
    queue = deque()

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
            for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                    queue.append((ny, nx))

    return result


def feather_edges(arr: np.ndarray, feather_threshold: int, passes: int = 2) -> np.ndarray:
    """
    Fade near-white pixels at the border between opaque and transparent.
    Runs multiple passes to smooth out multi-pixel fringe.
    """
    result = arr.copy()

    for _ in range(passes):
        transparent = (result[:, :, 3] == 0)

        # Find opaque pixels directly adjacent to transparent ones
        edge = np.zeros(transparent.shape, dtype=bool)
        edge[1:]  |= transparent[:-1]
        edge[:-1] |= transparent[1:]
        edge[:, 1:]  |= transparent[:, :-1]
        edge[:, :-1] |= transparent[:, 1:]
        edge &= ~transparent

        # Brightness of every pixel
        brightness = (
            result[:, :, 0].astype(np.float32) +
            result[:, :, 1].astype(np.float32) +
            result[:, :, 2].astype(np.float32)
        ) / 3.0

        # Edge pixels brighter than feather_threshold get faded
        fade_mask = edge & (brightness > feather_threshold)
        fade_amount = np.clip(
            (brightness - feather_threshold) / (255.0 - feather_threshold), 0.0, 1.0
        )
        new_alpha = np.clip(255.0 * (1.0 - fade_amount), 0, 255).astype(np.uint8)
        result[:, :, 3] = np.where(fade_mask, new_alpha, result[:, :, 3])

    return result


def strip(path: Path, threshold: int, feather_threshold: int) -> None:
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    arr = flood_fill_alpha(arr, threshold)
    arr = feather_edges(arr, feather_threshold)
    Image.fromarray(arr).save(path)
    print(f"  stripped: {path.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", help="PNG files to process")
    parser.add_argument("--threshold", type=int, default=230,
                        help="Flood fill threshold (pixels above this become transparent)")
    parser.add_argument("--feather", type=int, default=200,
                        help="Edge feather threshold (bright edge pixels fade in below this)")
    args = parser.parse_args()

    for f in args.files:
        strip(Path(f), args.threshold, args.feather)
    print(f"Done. {len(args.files)} file(s) processed.")
