"""
Sprite generator — uses Gemini Imagen 4 API to generate game sprites.
Usage:
  python sprite_gen.py "uppercut move, side-scrolling beat-em-up"
  python sprite_gen.py "uppercut move" --ref path/to/character.png
  python sprite_gen.py "uppercut move" --ref path/to/character.png --count 4
  python sprite_gen.py "uppercut move" --ref path/to/character.png --fast
"""

import os
import sys
import argparse
from pathlib import Path
from datetime import datetime

from dotenv import load_dotenv
load_dotenv()

import google.genai as genai
from google.genai import types
from PIL import Image
import io

API_KEY = os.environ.get("GEMINI_API_KEY")
OUTPUT_DIR = Path(__file__).parent / "assets" / "sprites" / "generated"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
BUDGET_FILE = Path(__file__).parent / ".sprite_budget.json"
BUDGET_CAP  = 20.00

MODEL_STANDARD = "imagen-4.0-generate-001"
MODEL_FAST     = "imagen-4.0-fast-generate-001"
MODEL_ULTRA    = "imagen-4.0-ultra-generate-001"
MODEL_REF      = "gemini-2.5-flash-image"

# Billing estimates (USD) — https://ai.google.dev/pricing
COST_IMAGEN4_STD   = 0.04
COST_IMAGEN4_FAST  = 0.02
COST_IMAGEN4_ULTRA = 0.08
# Gemini Flash image: ~$0.10 per 1M input tokens, $0.40 per 1M output tokens
COST_GEMINI_IN_PER_TOK  = 0.10 / 1_000_000
COST_GEMINI_OUT_PER_TOK = 0.40 / 1_000_000

session_total_usd = 0.0


def load_budget() -> float:
    if BUDGET_FILE.exists():
        import json
        return json.loads(BUDGET_FILE.read_text()).get("spent", 0.0)
    return 0.0


def save_budget(spent: float):
    import json
    BUDGET_FILE.write_text(json.dumps({"spent": round(spent, 6)}))


def print_cost(label: str, usd: float):
    global session_total_usd
    session_total_usd += usd
    total_spent = load_budget() + usd
    save_budget(total_spent)
    remaining = BUDGET_CAP - total_spent
    pct = (total_spent / BUDGET_CAP) * 100
    bar = "█" * int(pct / 5) + "░" * (20 - int(pct / 5))
    print(f"  cost: ${usd:.4f}  |  session: ${session_total_usd:.4f}  ({label})")
    print(f"  budget: [{bar}] {pct:.1f}%  ${total_spent:.4f} / ${BUDGET_CAP:.2f}  (${remaining:.4f} left)")


def load_pil(path: str) -> Image.Image:
    return Image.open(path).convert("RGBA")


def pil_to_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def strip_white_bg(path: Path, threshold: int = 230, feather_threshold: int = 200) -> None:
    import numpy as np
    from collections import deque
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]

    # Flood fill from edges
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
        r, g, b = arr[y, x, 0], arr[y, x, 1], arr[y, x, 2]
        if r >= threshold and g >= threshold and b >= threshold:
            arr[y, x, 3] = 0
            for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                    queue.append((ny, nx))

    # Feather edges — fade near-white fringe pixels adjacent to transparent
    for _ in range(2):
        transparent = (arr[:, :, 3] == 0)
        edge = np.zeros(transparent.shape, dtype=bool)
        edge[1:]    |= transparent[:-1]
        edge[:-1]   |= transparent[1:]
        edge[:, 1:] |= transparent[:, :-1]
        edge[:, :-1] |= transparent[:, 1:]
        edge &= ~transparent
        brightness = (arr[:,:,0].astype(np.float32) + arr[:,:,1].astype(np.float32) + arr[:,:,2].astype(np.float32)) / 3.0
        fade_mask = edge & (brightness > feather_threshold)
        fade_amount = np.clip((brightness - feather_threshold) / (255.0 - feather_threshold), 0.0, 1.0)
        new_alpha = np.clip(255.0 * (1.0 - fade_amount), 0, 255).astype(np.uint8)
        arr[:, :, 3] = np.where(fade_mask, new_alpha, arr[:, :, 3])

    Image.fromarray(arr).save(path)


def generate_sprites(prompt: str, ref_image_path: str | None = None, count: int = 2, fast: bool = False):
    client = genai.Client(api_key=API_KEY)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    slug = prompt[:40].replace(" ", "_").replace(",", "")
    saved = []

    base_prompt = (
        f"{prompt}. "
        "2D side-scrolling beat-em-up video game sprite, full body, "
        "transparent background, sharp outlines, game-ready character art."
    )

    if ref_image_path:
        ref = Path(ref_image_path)
        if not ref.exists():
            print(f"Reference image not found: {ref_image_path}")
            sys.exit(1)

        ref_img = load_pil(ref_image_path)
        print(f"Using reference: {ref.name}")
        print(f"Prompt: {base_prompt}")
        print(f"Generating {count} image(s) via {MODEL_REF}...")

        for i in range(count):
            response = client.models.generate_content(
                model=MODEL_REF,
                contents=[
                    types.Part.from_bytes(data=pil_to_bytes(ref_img), mime_type="image/png"),
                    types.Part.from_text(text=(
                        f"Using this character as a reference, generate: {base_prompt} "
                        "Keep the character's visual identity, proportions, and art style consistent."
                    )),
                ],
                config=types.GenerateContentConfig(
                    response_modalities=["IMAGE", "TEXT"],
                ),
            )

            usage = response.usage_metadata
            in_tok  = usage.prompt_token_count or 0
            out_tok = usage.candidates_token_count or 0
            cost    = in_tok * COST_GEMINI_IN_PER_TOK + out_tok * COST_GEMINI_OUT_PER_TOK

            for part in response.candidates[0].content.parts:
                if part.inline_data and "image" in part.inline_data.mime_type:
                    img = Image.open(io.BytesIO(part.inline_data.data))
                    out_path = OUTPUT_DIR / f"{slug}_{timestamp}_{i+1}.png"
                    img.save(out_path)
                    strip_white_bg(out_path)
                    print(f"Saved: {out_path}")
                    print(f"  tokens — in: {in_tok:,}  out: {out_tok:,}  total: {in_tok+out_tok:,}")
                    print_cost(MODEL_REF, cost)
                    saved.append(out_path)

    else:
        model = MODEL_FAST if fast else MODEL_STANDARD
        img_cost = COST_IMAGEN4_FAST if fast else COST_IMAGEN4_STD
        print(f"Prompt: {base_prompt}")
        print(f"Generating {count} image(s) via {model}...")

        response = client.models.generate_images(
            model=model,
            prompt=base_prompt,
            config=types.GenerateImagesConfig(
                number_of_images=min(count, 4),
                aspect_ratio="1:1",
                safety_filter_level="block_low_and_above",
            ),
        )

        for i, img_resp in enumerate(response.generated_images):
            img = Image.open(io.BytesIO(img_resp.image.image_bytes))
            out_path = OUTPUT_DIR / f"{slug}_{timestamp}_{i+1}.png"
            img.save(out_path)
            strip_white_bg(out_path)
            print(f"Saved: {out_path}")
            print_cost(model, img_cost)
            saved.append(out_path)

    print(f"\nDone. {len(saved)} image(s) in:\n{OUTPUT_DIR}")
    return saved


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("prompt", help="Description of the sprite to generate")
    parser.add_argument("--ref", help="Path to reference image", default=None)
    parser.add_argument("--count", type=int, default=2, help="Number of images to generate")
    parser.add_argument("--fast", action="store_true", help="Use faster/cheaper Imagen model")
    args = parser.parse_args()

    generate_sprites(args.prompt, args.ref, args.count, args.fast)
