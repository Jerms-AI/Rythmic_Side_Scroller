#!/usr/bin/env python3
"""
Offline beat extractor — outputs a JSON beat map for use in rhythm_engine.gd.

Usage:
    pip install librosa soundfile
    python beat_extract.py "assets/audio/music/Fast Shadow.ogg"

Output: assets/beat_maps/<songname>.json
"""

import sys
import json
import os
import librosa


def extract(song_path: str, output_path: str | None = None) -> str:
    print(f"Loading: {song_path}")
    y, sr = librosa.load(song_path, sr=None)

    print("Tracking beats...")
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    tempo, beat_frames = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)

    beat_times_ms = [
        int(round(t * 1000))
        for t in librosa.frames_to_time(beat_frames, sr=sr)
    ]

    song_name = os.path.splitext(os.path.basename(song_path))[0].lower().replace(" ", "_")

    if output_path is None:
        out_dir = os.path.join(os.path.dirname(song_path), "..", "..", "beat_maps")
        os.makedirs(out_dir, exist_ok=True)
        output_path = os.path.join(out_dir, f"{song_name}.json")

    data = {
        "bpm": float(tempo.item() if hasattr(tempo, 'item') else tempo),
        "song_file": f"res://assets/audio/music/{os.path.basename(song_path)}",
        "beats": beat_times_ms,
    }

    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)

    duration_s = len(y) / sr
    bpm_val = float(tempo.item() if hasattr(tempo, 'item') else tempo)
    print(f"Done. Detected BPM: {bpm_val:.1f}")
    print(f"Beat count: {len(beat_times_ms)} over {duration_s:.1f}s")
    print(f"Output: {os.path.abspath(output_path)}")
    return output_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python beat_extract.py <song_file.ogg> [output.json]")
        sys.exit(1)
    out = sys.argv[2] if len(sys.argv) > 2 else None
    extract(sys.argv[1], out)
