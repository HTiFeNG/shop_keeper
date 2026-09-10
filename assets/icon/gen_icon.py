"""Generate the app icon (1024x1024 PNG) without external dependencies.

Warm-orange storefront glyph: cream background, rounded orange tile,
white/cream awning stripes, storefront body, orange door.
"""
import struct
import zlib
import math
import os

SIZE = 1024

# RGBA palette
CREAM_BG = (255, 248, 240, 255)
ORANGE = (245, 124, 0, 255)
ORANGE_LIGHT = (255, 183, 77, 255)
WHITE = (255, 255, 255, 255)
AWNING_CREAM = (255, 224, 178, 255)
BODY = (255, 253, 250, 255)


def rounded_rect_mask(x0, y0, x1, y1, r):
    """Yield pixel grid mask for a rounded rectangle."""
    mask = [[False] * SIZE for _ in range(SIZE)]
    cx0, cy0 = x0 + r, y0 + r
    cx1, cy1 = x1 - r, y1 - r
    for y in range(SIZE):
        row = mask[y]
        for x in range(SIZE):
            if x0 + r <= x <= x1 - r and y0 <= y <= y1:
                row[x] = True
            elif x0 <= x < x0 + r and y0 <= y < y0 + r:
                if (x - cx0) ** 2 + (y - cy0) ** 2 <= r * r:
                    row[x] = True
            elif x1 - r < x <= x1 and y0 <= y < y0 + r:
                if (x - cx1) ** 2 + (y - cy0) ** 2 <= r * r:
                    row[x] = True
            elif x0 <= x < x0 + r and y1 - r < y <= y1:
                if (x - cx0) ** 2 + (y - cy1) ** 2 <= r * r:
                    row[x] = True
            elif x1 - r < x <= x1 and y1 - r < y <= y1:
                if (x - cx1) ** 2 + (y - cy1) ** 2 <= r * r:
                    row[x] = True
    return mask


def main():
    # pixel buffer (row-major RGBA)
    px = bytearray()
    tile = rounded_rect_mask(72, 72, 952, 952, 210)

    awning_x0, awning_y0, awning_y1 = 192, 300, 386
    body = rounded_rect_mask(192, 386, 832, 848, 28)
    door_x0, door_x1, door_y0, door_y1 = 452, 572, 566, 848
    # window squares
    win1 = rounded_rect_mask(236, 500, 396, 640, 16)
    win2 = rounded_rect_mask(628, 500, 788, 640, 16)

    for y in range(SIZE):
        for x in range(SIZE):
            c = CREAM_BG
            if tile[y][x]:
                c = ORANGE
            # body over tile
            if body[y][x]:
                c = BODY
            # awning stripes
            if awning_y0 <= y <= awning_y1 and awning_x0 <= x <= 832:
                c = WHITE if ((x - awning_x0) // 128) % 2 == 0 else AWNING_CREAM
            # door
            if door_x0 <= x <= door_x1 and door_y0 <= y <= door_y1:
                c = ORANGE
            # windows
            if win1[y][x] or win2[y][x]:
                c = ORANGE_LIGHT
            # roof line accent above awning
            if 268 <= y <= 288 and 192 <= x <= 832 and tile[y][x]:
                c = ORANGE
            px += bytes(c)

    # ---- encode PNG ----
    raw = bytearray()
    stride = SIZE * 4
    for y in range(SIZE):
        raw.append(0)  # filter: none
        raw += px[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        c += struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'app_icon.png')
    with open(out, 'wb') as f:
        f.write(png)
    print('saved', out, len(png), 'bytes')


if __name__ == '__main__':
    main()
