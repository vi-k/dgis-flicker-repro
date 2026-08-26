#!/usr/bin/env python3
"""Считает тёмные пиксели по кадрам записи экрана.

Моргание маркера глазами ловится плохо: пропажа длится два-пять кадров. Зато
машина — единственный крупный тёмный объект на светлой карте, и число тёмных
пикселей не зависит от того, куда она сдвинулась. Пропала — счётчик
проваливается.

Метод проверен на исходной записи бага: счётчик падал со 103 до 63 ровно в том
окне, где машина пропадала на глаз.

Нужен только ffmpeg/ffprobe в PATH; сторонних библиотек нет.

    python3 tools/darkcount.py запись.mp4
    python3 tools/darkcount.py запись.mp4 --top 0.12 --bottom 0.70 --threshold 40
"""

import argparse
import json
import shutil
import statistics
import subprocess
import sys

WIDTH = 320  # та же грубость, что у проверенного прогона


def probe(path):
    """Размер кадра и длительность.

    Частоту у записи экрана спрашивать бесполезно: screenrecord пишет с
    переменной частотой, и `avg_frame_rate` расходится с реальностью втрое
    (замер 26.08.2026: 23.7 против фактических 60.5). Поэтому время считается
    от длительности контейнера, поделённой на число декодированных кадров.
    """
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height:format=duration",
         "-of", "json", path],
        capture_output=True, text=True, check=True,
    )
    parsed = json.loads(out.stdout)
    stream = parsed["streams"][0]
    duration = float(parsed.get("format", {}).get("duration") or 0)
    return stream["width"], stream["height"], duration


def frames(path, crop, width, height):
    """Отдаёт кадры в градациях серого как bytes."""
    x, y, w, h = crop
    out_h = max(2, round(WIDTH * h / w / 2) * 2)
    command = [
        "ffmpeg", "-v", "error", "-i", path,
        "-vf", f"crop={w}:{h}:{x}:{y},scale={WIDTH}:{out_h},format=gray",
        "-f", "rawvideo", "-pix_fmt", "gray", "-",
    ]
    size = WIDTH * out_h
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    try:
        while True:
            chunk = process.stdout.read(size)
            if len(chunk) < size:
                return
            yield chunk
    finally:
        process.stdout.close()
        process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video")
    parser.add_argument("--threshold", type=int, default=40,
                        help="яркость, ниже которой пиксель считается тёмным")
    parser.add_argument("--top", type=float, default=0.12,
                        help="доля кадра сверху, которую отрезать (HUD)")
    parser.add_argument("--bottom", type=float, default=0.70,
                        help="нижняя граница области карты, доля кадра (панель)")
    parser.add_argument("--left", type=float, default=0.0,
                        help="левая граница области, доля ширины кадра")
    parser.add_argument("--right", type=float, default=1.0,
                        help="правая граница области, доля ширины кадра")
    parser.add_argument("--dip", type=float, default=0.7,
                        help="провал ниже этой доли медианы считается пропажей")
    parser.add_argument("--quiet", action="store_true",
                        help="печатать только провалы")
    args = parser.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            sys.exit(f"нужен {tool} в PATH")

    width, height, duration = probe(args.video)
    top = int(height * args.top) // 2 * 2
    bottom = int(height * args.bottom) // 2 * 2
    left = int(width * args.left) // 2 * 2
    right = int(width * args.right) // 2 * 2
    crop = (left, top, max(2, right - left), max(2, bottom - top))

    counts = []
    for frame in frames(args.video, crop, crop[2], crop[3]):
        counts.append(sum(1 for b in frame if b < args.threshold))

    if not counts:
        sys.exit("кадров не получено — проверьте путь и кодек")

    fps = len(counts) / duration if duration > 0 else 0.0
    median = statistics.median(counts)
    floor = median * args.dip
    print(f"кадров {len(counts)}, {fps:.1f} fps, медиана тёмных пикселей "
          f"{median:.0f}, порог провала {floor:.0f}")

    if not args.quiet:
        for i, value in enumerate(counts):
            mark = "  <-- провал" if value < floor else ""
            print(f"{i:5d}  t={i / fps:6.2f}s  {value:6d}{mark}")

    dips, start = [], None
    for i, value in enumerate(counts):
        if value < floor and start is None:
            start = i
        elif value >= floor and start is not None:
            dips.append((start, i - 1))
            start = None
    if start is not None:
        dips.append((start, len(counts) - 1))

    print()
    if not dips:
        print("провалов нет: маркер в кадре всё время")
        return
    print(f"провалов {len(dips)}:")
    for a, b in dips:
        print(f"  кадры {a}-{b}  t={a / fps:.2f}-{b / fps:.2f}s  "
              f"({b - a + 1} кадр(ов))")


if __name__ == "__main__":
    main()
