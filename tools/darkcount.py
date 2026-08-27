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

WIDTH = 320  # грубость по умолчанию; тонкие объекты требуют больше, см. --width


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


def frames(path, crop, width, height, color=False, out_w=WIDTH):
    """Отдаёт кадры: в градациях серого либо в rgb24, если считаем по цвету."""
    x, y, w, h = crop
    out_h = max(2, round(out_w * h / w / 2) * 2)
    fmt = "rgb24" if color else "gray"
    command = [
        "ffmpeg", "-v", "error", "-i", path,
        "-vf", f"crop={w}:{h}:{x}:{y},scale={out_w}:{out_h},format={fmt}",
        # passthrough обязателен: без него ffmpeg приводит переменную частоту
        # screenrecord к своей средней, дублируя и выбрасывая кадры, и номера
        # в выводе перестают совпадать с номерами в файле (замер 26.08.2026).
        "-fps_mode", "passthrough",
        "-f", "rawvideo", "-pix_fmt", fmt, "-",
    ]
    size = out_w * out_h * (3 if color else 1)
    # rawvideo-муксер ругается на неубывающие dts у записи с переменной
    # частотой; на данные это не влияет.
    process = subprocess.Popen(command, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL)
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
    parser.add_argument("--color", default=None, metavar="RRGGBB",
                        help="считать не тёмные пиксели, а близкие к этому "
                             "цвету — например 00A025 для линии маршрута")
    parser.add_argument("--tolerance", type=int, default=90,
                        help="допуск по сумме модулей отклонений R+G+B")
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
    parser.add_argument("--window", type=float, default=0.0,
                        help="базовый уровень считать по скользящему окну "
                             "такой длины в секундах вместо медианы всего "
                             "прогона. Нужно для убывающих рядов: erasedPart "
                             "постепенно съедает полилинию, её сигнал падает "
                             "по ходу прогона, и глобальная медиана метит "
                             "провалом половину записи")
    parser.add_argument("--width", type=int, default=WIDTH,
                        help="ширина кадра при разборе; по умолчанию 320. "
                             "Тонкие объекты вроде полилинии на 320 теряются: "
                             "линия толщиной 4 логических пикселя после сжатия "
                             "уходит в доли пикселя, сигнал тонет в шуме")
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
    if args.color:
        target = bytes.fromhex(args.color)
        tr, tg, tb = target[0], target[1], target[2]
        tol = args.tolerance
        for frame in frames(args.video, crop, crop[2], crop[3], color=True,
                            out_w=args.width):
            hit = 0
            for i in range(0, len(frame), 3):
                if (abs(frame[i] - tr) + abs(frame[i + 1] - tg)
                        + abs(frame[i + 2] - tb)) <= tol:
                    hit += 1
            counts.append(hit)
    else:
        for frame in frames(args.video, crop, crop[2], crop[3],
                            out_w=args.width):
            counts.append(sum(1 for b in frame if b < args.threshold))

    if not counts:
        sys.exit("кадров не получено — проверьте путь и кодек")

    fps = len(counts) / duration if duration > 0 else 0.0
    median = statistics.median(counts)
    what = f"пикселей цвета {args.color}" if args.color else "тёмных пикселей"

    if args.window > 0 and fps > 0:
        half = max(1, int(args.window * fps / 2))
        base = []
        for i in range(len(counts)):
            lo, hi = max(0, i - half), min(len(counts), i + half + 1)
            base.append(statistics.median(counts[lo:hi]))
        floors = [b * args.dip for b in base]
        print(f"кадров {len(counts)}, {fps:.1f} fps, медиана {what} "
              f"{median:.0f}, базовый уровень — скользящее окно "
              f"{args.window:g} с")
    else:
        floors = [median * args.dip] * len(counts)
        print(f"кадров {len(counts)}, {fps:.1f} fps, медиана {what} "
              f"{median:.0f}, порог провала {median * args.dip:.0f}")

    if not args.quiet:
        for i, value in enumerate(counts):
            mark = "  <-- провал" if value < floors[i] else ""
            print(f"{i:5d}  t={i / fps:6.2f}s  {value:6d}{mark}")

    dips, start = [], None
    for i, value in enumerate(counts):
        floor = floors[i]
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
