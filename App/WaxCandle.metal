#include <metal_stdlib>
using namespace metal;

struct U {
    float2 res;
    float  p;
    float  t;
};

// ---------------------------------------------------------------- noise
static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}
static float fbm(float2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
    return s;
}

// ---------------------------------------------------------------- scene
struct P {
    float h;
    float poolR;
    float flame;
    float p;
};

static float sdRoundCyl(float3 p, float hh, float r, float rb) {
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r - rb, hh - rb);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rb;
}
// tapered capsule: a wax run that is wide at the lip and thin at the tip
static float sdRoundCone(float3 p, float3 a, float3 b, float r1, float r2) {
    float3 ba = b - a;
    float l2 = dot(ba, ba);
    float rr = r1 - r2;
    float a2 = l2 - rr * rr;
    float il2 = 1.0 / l2;
    float3 pa = p - a;
    float y = dot(pa, ba);
    float z = y - l2;
    float3 xv = pa * l2 - ba * y;
    float x2 = dot(xv, xv);
    float y2 = y * y * l2;
    float z2 = z * z * l2;
    float k = sign(rr) * rr * rr * x2;
    if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
    if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
    return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}
static float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// the melted lip of the candle, low frequency so it reads at small sizes
static float rimWave(float ang) {
    return 0.026 * sin(ang * 2.0 + 0.35)
         + 0.014 * sin(ang * 3.0 - 1.15)
         + 0.007 * sin(ang * 5.0 + 2.30);
}
static float bodyR(float ang, float yn) {
    return 0.400 + 0.026 * yn * yn
         + 0.012 * sin(ang * 2.0 + 0.90)
         + 0.007 * sin(ang * 3.0 - 1.60)
         + 0.004 * sin(ang * 5.0 + 2.20);
}
static float poolR(float ang, float base) {
    return base * (1.0 + 0.070 * sin(ang * 3.0 + 1.00)
                       + 0.040 * sin(ang * 5.0 - 0.60)
                       + 0.022 * sin(ang * 9.0 + 2.00));
}

static float mapD(float3 p, P q) {
    float ang = atan2(p.z, p.x);
    float bh = max(q.h, 0.0);

    // ---- puddle of wax on the table
    float ph = 0.028 + 0.014 * q.p;
    float3 e = p / float3(poolR(ang, q.poolR), ph, poolR(ang, q.poolR));
    float puddle = (length(e) - 1.0) * ph;

    float d;
    if (bh > 0.02) {
        float yn = clamp(p.y / bh, 0.0, 1.0);
        float3 c = p - float3(0.0, bh * 0.5, 0.0);
        c.y -= rimWave(ang) * yn * yn;                 // melted, uneven lip
        float body = sdRoundCyl(c, bh * 0.5, bodyR(ang, yn), 0.045);

        // ---- scoop the dish out of the top
        float dish = length(p - float3(0.0, bh + 0.205, 0.0)) - 0.320;
        body = max(body, -dish);

        // ---- molten wax sitting in the dish
        float3 m = (p - float3(0.0, bh - 0.118, 0.0)) / float3(0.243, 0.042, 0.243);
        body = min(body, (length(m) - 1.0) * 0.042);

        // ---- drips running over the lip
        const float angs[4] = { 0.55, 2.15, 3.55, 5.05 };
        for (int i = 0; i < 4; i++) {
            float fi = float(i);
            float a = angs[i] + 0.20 * sin(fi * 4.1);
            float rnd = fract(sin(fi * 12.9898) * 43758.5453);
            float L = (0.34 + 0.40 * q.p) * (0.60 + 0.80 * rnd);
            float rr = 0.026 + 0.016 * rnd;
            float r0 = bodyR(a, 1.0) - 0.020;
            float3 top = float3(cos(a) * r0, bh - 0.010, sin(a) * r0);
            float3 bot = top - float3(0.0, L, 0.0);
            body = smin(body, sdRoundCone(p, top, bot, rr, rr * 0.55), 0.030);
            body = min(body, length(p - bot) - rr * 0.95);   // bead at the end
        }

        d = smin(body, puddle, 0.055);
    } else {
        d = puddle;
    }
    return min(d, p.y);   // table
}

static float3 nrm(float3 p, P q) {
    float2 e = float2(0.0012, 0.0);
    return normalize(float3(mapD(p + e.xyy, q) - mapD(p - e.xyy, q),
                            mapD(p + e.yxy, q) - mapD(p - e.yxy, q),
                            mapD(p + e.yyx, q) - mapD(p - e.yyx, q)));
}

// soft vertical wax flow, used as a shading normal perturbation
static float waxH(float2 q) {
    return 0.62 * vnoise(q * float2(0.85, 0.26))
         + 0.26 * vnoise(q * float2(2.30, 0.70) + 9.1)
         + 0.12 * vnoise(q * float2(5.10, 1.60) + 4.7);
}
static float3 waxNormal(float3 p, float3 n) {
    float ang = atan2(p.z, p.x);
    float2 q = float2(ang * 1.9, p.y * 2.1);
    float e = 0.045;
    float h0 = waxH(q), hu = waxH(q + float2(e, 0.0)), hv = waxH(q + float2(0.0, e));
    float3 t1 = normalize(cross(n, float3(0.0, 1.0, 0.0)) + 1e-4);
    float3 t2 = cross(n, t1);
    return normalize(n - (t1 * ((hu - h0) / e) * 0.040 + t2 * ((hv - h0) / e) * 0.075));
}

// ---------------------------------------------------------------- shaders
struct VOut { float4 pos [[position]]; };

vertex VOut vsFull(uint vid [[vertex_id]]) {
    float2 v[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
    VOut o;
    o.pos = float4(v[vid], 0.0, 1.0);
    return o;
}

static float3 aces(float3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

fragment float4 fsMain(VOut in [[stage_in]], constant U &u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.res;
    float2 sc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float aspect = u.res.x / u.res.y;
    sc.x *= aspect;

    P q;
    float p = clamp(u.p, 0.0, 1.0);
    q.h = 0.16 + 1.30 * pow(max(1.0 - p, 0.0), 0.55);
    q.poolR = 0.300 + 0.360 * p;
    q.flame = 0.62 + 0.38 * (1.0 - p);
    q.p = p;

    // ---- camera, high enough to see into the melted dish
    float camY = 0.30 + 0.38 * q.h;
    float3 ro = float3(0.0, camY + 1.82, 3.22);
    float3 ta = float3(0.0, camY + 0.06, 0.0);
    float3 fwd = normalize(ta - ro);
    float3 rgt = normalize(cross(fwd, float3(0, 1, 0)));
    float3 upv = cross(rgt, fwd);
    float3 rd = normalize(fwd + rgt * sc.x * 0.375 + upv * sc.y * 0.375);

    float flick = 1.0 + 0.045 * sin(u.t * 10.7) + 0.026 * sin(u.t * 21.3 + 1.7);
    float3 wickTop = float3(0.0, q.h + 0.042, 0.0);
    float3 lp = wickTop + float3(0.0, 0.130 * q.flame, 0.0);
    float3 Lc = float3(1.0, 0.585, 0.255);

    float t = 0.0, hit = 0.0;
    for (int i = 0; i < 150; i++) {
        float d = mapD(ro + rd * t, q);
        if (d < 0.0011) { hit = 1.0; break; }
        t += d;
        if (t > 8.0) break;
    }

    // ---------------------------------------------------------- warm matte palette
    float3 BG      = pow(float3(0.141, 0.078, 0.075), 2.2);   // #241413, the card
    float3 BG_LOW  = pow(float3(0.106, 0.059, 0.055), 2.2);   // #1B0F0E
    float3 INK     = pow(float3(0.180, 0.098, 0.086), 2.2);
    float3 WAX_LIT = pow(float3(0.969, 0.929, 0.847), 2.2);   // #F7EDD8
    float3 WAX_DIM = pow(float3(0.788, 0.682, 0.541), 2.2);   // #C9AE8A
    float3 POOL    = pow(float3(0.914, 0.804, 0.627), 2.2);   // #E9CDA0
    float3 FLAME   = pow(float3(0.965, 0.761, 0.420), 2.2);   // #F6C26B
    float3 FLAMEDG = pow(float3(0.910, 0.569, 0.184), 2.2);   // #E8912F
    float3 FLAMEHI = pow(float3(1.000, 0.965, 0.839), 2.2);   // #FFF6D6
    float3 PUD_LIT = pow(float3(0.890, 0.800, 0.651), 2.2);   // #E3CCA6
    float3 PUD_DIM = pow(float3(0.718, 0.608, 0.455), 2.2);   // #B79B74
    float3 SHADOW  = pow(float3(0.078, 0.043, 0.039), 2.2);   // #140B0A

    float3 col = mix(BG, BG_LOW, smoothstep(0.10, 1.0, uv.y));

    if (hit > 0.5) {
        float3 pos = ro + rd * t;
        float3 n = nrm(pos, q);
        float r = length(pos.xz);
        bool isTable = (pos.y < 0.005);

        if (isTable) {
            float sd = length(float2(pos.x * 0.92, pos.z * 0.62));
            float sh = 1.0 - smoothstep(0.26, 0.86, sd);
            col = mix(col, SHADOW, sh * 0.9);
        } else {
            bool isPool   = (abs(pos.y - (q.h - 0.075)) < 0.010 && r < 0.330);
            bool isPuddle = (pos.y < 0.075);
            if (!isPool && !isPuddle) n = waxNormal(pos, n);

            // soft matte shading: two wax tones mixed by one broad light, no gloss
            float3 L1 = normalize(float3(-0.38, 0.42, 0.82));
            float ndl = dot(n, L1);
            float shade = clamp(0.40 + 0.60 * ndl, 0.0, 1.0);

            float3 wax = mix(WAX_DIM, WAX_LIT, shade);
            if (isPool) wax = mix(wax, POOL, 0.75);

            // contact darkening at the base and a warm bounce off the table
            wax *= mix(0.58, 1.0, smoothstep(0.0, 0.22, pos.y));
            wax += float3(0.10, 0.05, 0.02) * max(-n.y, 0.0) * 0.25;

            // the wax near the flame is warmed through, not lit from behind
            wax = mix(wax, wax * float3(1.03, 0.96, 0.86), smoothstep(0.55, 1.0, pos.y / max(q.h, 0.001)) * 0.55);

            if (isPuddle) {
                // thin wax: solid in the middle, sinking into the dark table at the rim
                float ang = atan2(pos.z, pos.x);
                float rn = clamp(r / max(poolR(ang, q.poolR), 0.001), 0.0, 1.0);
                float thick = pow(1.0 - rn * rn, 0.75);
                float3 pud = mix(PUD_DIM, PUD_LIT, shade);
                col = mix(SHADOW * 0.9, pud, smoothstep(0.0, 0.82, thick));
            } else {
                col = wax;
            }
        }
    }

    // ---------------------------------------------------------- flame, no glow
    float den = dot(rd, fwd);
    if (den > 0.0001 && q.flame > 0.001) {
        float tt = dot(wickTop - ro, fwd) / den;
        if (tt > 0.0 && (hit < 0.5 || t > tt)) {
            float3 hp = ro + rd * tt;
            float2 fq = float2(dot(hp - wickTop, rgt), hp.y - wickTop.y);
            float H = 0.52 * q.flame;

            float yy = fq.y;
            if (yy > -0.085 && yy < H * 1.02) {
                float un = clamp(yy / H, 0.0, 1.0);
                float wob = (fbm(float2(yy * 6.2 - u.t * 2.0, 3.0)) - 0.5) * 0.048 * un;
                float x = fq.x - wob;
                float prof = pow(max(0.0, 1.0 - un), 0.68) * smoothstep(0.0, 0.22, un);
                float w = 0.112 * prof + 0.0012;
                float ax = abs(x);
                float vfade = 1.0 - smoothstep(0.90, 1.0, un);
                float inside = (1.0 - smoothstep(w * 0.90, w * 1.04, ax)) * vfade;

                float outer = (1.0 - smoothstep(w * 0.80, w * 1.02, ax)) * vfade;
                float inner = (1.0 - smoothstep(w * 0.58, w * 0.80, ax)) * vfade;
                float core = 1.0 - smoothstep(0.0, 0.44, ax / max(w, 0.0001));

                col = mix(col, FLAMEDG, outer);
                col = mix(col, FLAME, inner);
                col = mix(col, FLAMEHI, core * smoothstep(0.08, 0.34, un) * inner);
                float wd = length(float2(fq.x, yy + 0.032));
                col = mix(col, INK, (1.0 - smoothstep(0.006, 0.011, wd)));
            }
        }
    }

    return float4(pow(max(col, 0.0), float3(1.0 / 2.2)), 1.0);
}
