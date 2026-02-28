# transcribe.py
# Usage:
#   py -3.11 .\transcribe.py .\audio.wav
#   py -3.11 .\transcribe.py .\audio.wav --model medium
#   py -3.11 .\transcribe.py .\audio.wav --plain   (prints ONLY transcript)
# Optional:
#   py -3.11 .\transcribe.py .\audio.wav --plain --context
#   py -3.11 .\transcribe.py .\audio.wav --plain --language ms

import argparse
import os
import sys
from faster_whisper import WhisperModel


def build_parser():
    p = argparse.ArgumentParser(description="Faster-Whisper transcription (mixed Malay/English, worker-friendly)")
    p.add_argument("audio", help="Path to audio/video file (mp3/m4a/wav/mp4, etc.)")
    p.add_argument("--model", default="medium", help="Model size: small | medium | large-v3 (default: medium)")
    p.add_argument("--device", default="cpu", help="cpu | cuda (default: cpu)")
    p.add_argument(
        "--compute",
        default=None,
        help="Compute type. cpu: int8/int16/float32. cuda: float16/int8_float16. (default: auto)",
    )
    p.add_argument("--beam", type=int, default=7, help="Beam size (default: 7)")
    p.add_argument("--vad", action="store_true", default=True, help="Enable VAD filter (default: on)")
    p.add_argument("--no-vad", dest="vad", action="store_false", help="Disable VAD filter")
    p.add_argument("--language", default=None, help='Force language code, e.g. "ms" or "en" (default: auto)')
    p.add_argument(
        "--prompt",
        default="This audio is mixed Malay and English. Use Malaysian place names, food terms, and slang correctly.",
        help="Initial prompt to guide mixed-language transcription (default included)",
    )
    p.add_argument("--timestamps", action="store_true", help="Print timestamps per segment")
    p.add_argument("--write", default=None, help="Write transcript to file path (txt)")
    p.add_argument(
        "--plain",
        action="store_true",
        help="Print ONLY transcript (no headers/info). Best for Node worker parsing.",
    )

    # ✅ Optional: keep context across segments (sometimes improves coherence)
    p.add_argument(
        "--context",
        action="store_true",
        help="Enable condition_on_previous_text=True to improve cross-segment continuity (optional).",
    )
    return p


def pick_default_compute(device: str) -> str:
    device = (device or "cpu").lower()
    return "float16" if device == "cuda" else "int8"


def main():
    parser = build_parser()
    args = parser.parse_args()

    audio_path = args.audio
    if not os.path.exists(audio_path):
        print(f"ERROR: File not found: {audio_path}", file=sys.stderr)
        sys.exit(2)

    device = args.device.lower()
    compute_type = args.compute or pick_default_compute(device)

    model = WhisperModel(args.model, device=device, compute_type=compute_type)

    transcribe_kwargs = dict(
        beam_size=args.beam,
        vad_filter=args.vad,
        temperature=0.0,
        condition_on_previous_text=bool(args.context),
    )

    if args.language:
        transcribe_kwargs["language"] = args.language

    if args.prompt:
        transcribe_kwargs["initial_prompt"] = args.prompt

    segments, info = model.transcribe(audio_path, **transcribe_kwargs)

    # Print detection info to STDERR (so stdout is clean transcript)
    if not args.plain:
        lang = getattr(info, "language", None)
        prob = getattr(info, "language_probability", None)
        if lang is not None:
            if prob is not None:
                print(f"[Detected language] {lang} (prob={prob:.2f})", file=sys.stderr)
            else:
                print(f"[Detected language] {lang}", file=sys.stderr)

    lines = []
    for seg in segments:
        text = (seg.text or "").strip()
        if not text:
            continue

        if args.timestamps:
            lines.append(f"[{seg.start:8.2f} -> {seg.end:8.2f}] {text}")
        else:
            lines.append(text)

    transcript = "\n".join(lines).strip()

    if args.plain:
        print(transcript)
    else:
        print("\n" + transcript + "\n")

    if args.write:
        try:
            with open(args.write, "w", encoding="utf-8") as f:
                f.write(transcript + "\n")
            if not args.plain:
                print(f"[Saved] {args.write}", file=sys.stderr)
        except Exception as e:
            print(f"ERROR: Failed to write file: {e}", file=sys.stderr)
            sys.exit(3)


if __name__ == "__main__":
    main()