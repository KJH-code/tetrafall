# W19 얼굴 텍스처 그리기 (numpy, Blender 안에서 부름 — 밖 라이브러리 없음). 표정마다 한 장 (기본·맞음·기합).
# 좌표: 얼굴 칸 정규 좌표 x, y ∈ [-1, 1] (x = 캐릭터 왼쪽 +, 정면에서 보면 오른쪽 · y = 위 +), 얼굴 구 앞면을 정면에서 평면 투영한 자리 (build_character.py face_uv).
# 그림 배열: [행 (아래 → 위, Blender 이미지 순서), 열, RGBA] 선형 아닌 sRGB 값 0..1
import numpy as np


def _hex(h):
    return np.array([(h >> 16 & 255) / 255.0, (h >> 8 & 255) / 255.0, (h & 255) / 255.0])


class Canvas:
    def __init__(self, n, bg):
        self.n = n
        self.px = 2.0 / n
        c = (np.arange(n) + 0.5) / n * 2 - 1
        self.x, self.y = np.meshgrid(c, c)  # y 는 행 (아래부터)
        self.img = np.ones((n, n, 3)) * _hex(bg)

    def cov(self, d, soft=1.0):
        """부호 거리 d (안 = 음수) → 덮음 (가장자리 soft 픽셀 부드럽게)"""
        return np.clip(0.5 - d / (self.px * soft), 0.0, 1.0)

    def put(self, a, col, alpha=1.0):
        a = a[..., None] * alpha
        self.img = self.img * (1 - a) + _hex(col) * a if isinstance(col, int) else self.img * (1 - a) + col * a

    # 모양 거리
    def ellipse(self, cx, cy, rx, ry, rot=0.0):
        x, y = self.x - cx, self.y - cy
        if rot:
            c, s = np.cos(rot), np.sin(rot)
            x, y = x * c + y * s, -x * s + y * c
        r = np.sqrt((x / rx) ** 2 + (y / ry) ** 2)
        return (r - 1) * min(rx, ry)

    def stroke(self, pts, w):
        """꺾은선 굵기 w (끝 둥글게)"""
        d = np.full(self.x.shape, 1e9)
        for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
            vx, vy = bx - ax, by - ay
            L2 = vx * vx + vy * vy + 1e-12
            t = np.clip(((self.x - ax) * vx + (self.y - ay) * vy) / L2, 0, 1)
            dx, dy = self.x - (ax + t * vx), self.y - (ay + t * vy)
            d = np.minimum(d, np.sqrt(dx * dx + dy * dy))
        return d - w / 2

    def stroke_taper(self, pts, w0, w1):
        """굵기가 w0 → w1 로 변하는 꺾은선 (붓 느낌)"""
        n = len(pts) - 1
        d = np.full(self.x.shape, 1e9)
        for i, ((ax, ay), (bx, by)) in enumerate(zip(pts[:-1], pts[1:])):
            vx, vy = bx - ax, by - ay
            L2 = vx * vx + vy * vy + 1e-12
            t = np.clip(((self.x - ax) * vx + (self.y - ay) * vy) / L2, 0, 1)
            dx, dy = self.x - (ax + t * vx), self.y - (ay + t * vy)
            ww = w0 + (w1 - w0) * ((i + t) / n)
            d = np.minimum(d, np.sqrt(dx * dx + dy * dy) - ww / 2)
        return d


def arc(cx, cy, rx, ry, a0, a1, k=12):
    return [(cx + rx * np.cos(a), cy + ry * np.sin(a)) for a in np.linspace(a0, a1, k)]


SKIN = 0xf6cba8
SKIN_SHADE = 0xe9a988
BLUSH = np.array([0.96, 0.52, 0.50])
LINE = 0x3a2418
IRIS_TOP = 0x22150f
IRIS_BOT = 0x9a5a2c
MOUTH = 0x8a2f2a
TONGUE = 0xe0706a
BROW = 0x5a3418

EYE = {"x": 0.37, "y": -0.04, "rx": 0.165, "ry": 0.225}


def _blush(c):
    for s in (-1, 1):
        d = c.ellipse(s * 0.6, -0.33, 0.15, 0.075)
        c.put(c.cov(d, soft=14), BLUSH, 0.55)
        for k in range(3):  # 볼 빗금 세 줄 (치비 볼터치)
            x0 = s * (0.53 + k * 0.055)
            c.put(c.cov(c.stroke([(x0 - s * 0.012, -0.30), (x0 + s * 0.012, -0.355)], 0.018)), 0xe57b74, 0.65)


def _eye_open(c, s, squint=0.0):
    ex, ey, rx, ry = s * EYE["x"], EYE["y"], EYE["rx"], EYE["ry"]
    d = c.ellipse(ex, ey, rx, ry)
    if squint > 0:  # 윗눈꺼풀을 낮춤 (기합: 눈을 부릅뜸)
        lid = (c.y - (ey + ry * (1 - squint))) + (c.x - ex) * s * 0.25 * squint
        d = np.maximum(d, lid * 0.5)
    inside = c.cov(d)
    # 흰자 테두리 조금 → 큰 홍채 (위 어둡고 아래 밝은 그라데이션)
    c.put(inside, 0xffffff)
    di = c.ellipse(ex - s * 0.005, ey - 0.01, rx * 0.86, ry * 0.9)
    di = np.maximum(di, d)
    t = np.clip((c.y - (ey - ry)) / (2 * ry), 0, 1)[..., None]
    grad = _hex(IRIS_BOT) * (1 - t) + _hex(IRIS_TOP) * t
    c.put(c.cov(di), grad)
    # 동공 + 홍채 빛 고리
    c.put(c.cov(np.maximum(c.ellipse(ex - s * 0.01, ey, rx * 0.42, ry * 0.46), d)), 0x0e0806)
    ring = np.abs(c.ellipse(ex - s * 0.005, ey - 0.03, rx * 0.66, ry * 0.68)) - 0.008
    c.put(c.cov(np.maximum(ring, d)) * (c.y < ey - ry * 0.1), 0xd08a48, 0.6)
    # 반짝임 두 점 (큰 점 위·바깥, 작은 점 아래·안)
    c.put(c.cov(c.ellipse(ex + s * rx * 0.32, ey + ry * 0.38, rx * 0.3, ry * 0.24)), 0xffffff)
    c.put(c.cov(c.ellipse(ex - s * rx * 0.35, ey - ry * 0.42, rx * 0.13, ry * 0.1)), 0xffffff)
    # 윗눈꺼풀 선 (속눈썹, 바깥으로 살짝 뻗침)
    top = ey + ry * (1 - squint) if squint > 0 else ey + ry * 0.92
    pts = arc(ex, ey if squint == 0 else ey - ry * squint * 0.5, rx * 1.04, (top - ey) + 0.01 if squint else ry * 1.0, np.pi * 0.97, np.pi * 0.05, 14)
    if s < 0:
        pts = [(2 * ex - x, y) for (x, y) in pts]
    pts = pts + [(pts[-1][0] + s * 0.05, pts[-1][1] + 0.025)]
    c.put(c.cov(c.stroke_taper(pts, 0.022, 0.03)), LINE)


def _eye_squeeze(c, s):
    """맞음: > < 모양 (질끈 감은 눈)"""
    ex, ey = s * EYE["x"], EYE["y"]
    pts = [(ex + s * 0.11, ey + 0.11), (ex - s * 0.11, ey), (ex + s * 0.11, ey - 0.11)]
    c.put(c.cov(c.stroke(pts, 0.05)), LINE)


def _brows(c, kind):
    for s in (-1, 1):
        if kind == "idle":
            pts = [(s * 0.21, 0.27), (s * 0.36, 0.31), (s * 0.5, 0.29)]
            c.put(c.cov(c.stroke_taper(pts, 0.06, 0.04)), BROW)
        elif kind == "hit":  # 걱정 (안쪽이 올라감)
            pts = [(s * 0.2, 0.36), (s * 0.36, 0.31), (s * 0.5, 0.25)]
            c.put(c.cov(c.stroke_taper(pts, 0.06, 0.04)), BROW)
        else:  # 기합 (안쪽이 내려감, 굵게)
            pts = [(s * 0.17, 0.21), (s * 0.34, 0.27), (s * 0.52, 0.34)]
            c.put(c.cov(c.stroke_taper(pts, 0.08, 0.05)), BROW)


def _nose(c):
    c.put(c.cov(c.ellipse(0.0, -0.22, 0.035, 0.022), soft=3), SKIN_SHADE, 0.9)


def _mouth(c, kind):
    if kind == "idle":  # 작은 웃음
        c.put(c.cov(c.stroke(arc(0, -0.36, 0.09, 0.06, np.pi * 1.15, np.pi * 1.85, 10), 0.028)), MOUTH)
    elif kind == "hit":  # 놀란 작은 입 (세모진 o)
        d = c.ellipse(0, -0.43, 0.06, 0.07)
        c.put(c.cov(d), MOUTH)
        c.put(c.cov(np.maximum(c.ellipse(0, -0.47, 0.04, 0.03), d)), TONGUE)
    else:  # 기합: 크게 벌린 입 (위 이 한 줄 + 혀)
        d = c.ellipse(0, -0.42, 0.13, 0.1)
        d = np.maximum(d, c.y + 0.33)  # 윗입술 평평
        c.put(c.cov(d), MOUTH)
        c.put(c.cov(np.maximum(c.ellipse(0, -0.49, 0.08, 0.05), d)), TONGUE)
        c.put(c.cov(np.maximum(d, -(c.y + 0.37))), 0xffffff)


def paint_face(kind, n=512):
    """kind = idle | hit | attack → (n, n, 4) RGBA (Blender 이미지 픽셀 순서)"""
    c = Canvas(n, SKIN)
    # 얼굴 아래·가장자리 살짝 그늘 (손칠 그라데이션)
    r = np.sqrt(c.x ** 2 + (c.y * 1.1) ** 2)
    c.put(np.clip((r - 0.75) / 0.35, 0, 1), SKIN_SHADE, 0.5)
    _blush(c)
    _nose(c)
    if kind == "hit":
        for s in (-1, 1):
            _eye_squeeze(c, s)
    else:
        for s in (-1, 1):
            _eye_open(c, s, 0.35 if kind == "attack" else 0.0)
    _brows(c, kind)
    _mouth(c, kind)
    out = np.ones((n, n, 4))
    out[..., :3] = np.clip(c.img, 0, 1)
    return out
