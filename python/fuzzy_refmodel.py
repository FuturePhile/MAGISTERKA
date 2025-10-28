#!/usr/bin/env python3
"""
fuzzy_refmodel.py — Bit-accurate reference model for the Fuzzy Logic coprocessor
Covers REQ-010/020/030/040/050/210 (dt_mode=0 exact), and provides a pluggable estimator for REQ-060/061/062.
"""

from dataclasses import dataclass
from typing import Tuple, Optional, List

Q15_MAX = 32767

# -------------------- Common helpers --------------------

def sat_q15(x: int) -> int:
    if x < 0: return 0
    if x > Q15_MAX: return Q15_MAX
    return x

def clamp_s8(x: int) -> int:
    return -128 if x < -128 else (127 if x > 127 else x)

def g2q15_percent(gpct: int) -> int:
    # tmp = gpct * 32767 + 50; tmp /= 100; clamp
    tmp = gpct * Q15_MAX + 50
    tmp //= 100
    return sat_q15(tmp)

def mul_q15_round(a_q15: int, b_q15: int) -> int:
    # (a*b + 0.5 LSB) >> 15, clamp to Q1.15
    mul = int(a_q15) * int(b_q15)
    mul += (1 << 14)
    return sat_q15(mul >> 15)

# -------------------- Bit-accurate SV-style arithmetic helpers --------------------

def sxt(value: int, bits: int) -> int:
    """Sign-extend 'value' that fits in 'bits' bits to Python int (SV-like)."""
    mask = (1 << bits) - 1
    value &= mask
    sign_bit = 1 << (bits - 1)
    return (value ^ sign_bit) - sign_bit

def clip_to_range(x: int, lo: int, hi: int) -> int:
    return lo if x < lo else (hi if x > hi else x)

# -------------------- Memberships, rules, aggregation, defuzz --------------------

def trapezoid_mu(x: int, a: int, b: int, c: int, d: int) -> int:
    # Bit-identical do ref_mu() z TB
    if x <= a or x >= d: return 0
    if b <= x <= c: return Q15_MAX
    if a < x < b:
        dx = int(b) - int(a)
        if dx == 0: dx = 1
        t  = int(x) - int(a)
        return min(Q15_MAX, (t << 15) // dx)
    dx = int(d) - int(c)
    if dx == 0: dx = 1
    t  = int(d) - int(x)
    return min(Q15_MAX, (t << 15) // dx)

def rules9_min(muTn:int, muTz:int, muTp:int, muDn:int, muDz:int, muDp:int):
    w00 = min(muTn, muDn); w01 = min(muTn, muDz); w02 = min(muTn, muDp)
    w10 = min(muTz, muDn); w11 = min(muTz, muDz); w12 = min(muTz, muDp)
    w20 = min(muTp, muDn); w21 = min(muTp, muDz); w22 = min(muTp, muDp)
    return w00,w01,w02,w10,w11,w12,w20,w21,w22

def aggregate(reg_mode: int,
              w: Tuple[int,int,int,int,int,int,int,int,int],
              g: Tuple[int,int,int,int,int,int,int,int,int]) -> Tuple[int,int]:
    w00,w01,w02,w10,w11,w12,w20,w21,w22 = w
    g00,g01,g02,g10,g11,g12,g20,g21,g22 = g

    if reg_mode == 0:
        # center/edges off in 4-rule mode
        w01 = w10 = w11 = w12 = w21 = 0

    gq = [g2q15_percent(x) for x in (g00,g01,g02,g10,g11,g12,g20,g21,g22)]
    wg = [mul_q15_round(wi, gi) for wi,gi in zip((w00,w01,w02,w10,w11,w12,w20,w21,w22), gq)]

    sumw  = int(w00)+int(w01)+int(w02)+int(w10)+int(w11)+int(w12)+int(w20)+int(w21)+int(w22)
    sumwg = int(wg[0])+int(wg[1])+int(wg[2])+int(wg[3])+int(wg[4])+int(wg[5])+int(wg[6])+int(wg[7])+int(wg[8])

    S_w  = sumw  if sumw  <= Q15_MAX else Q15_MAX
    S_wg = sumwg if sumwg <= Q15_MAX else Q15_MAX
    return S_w, S_wg

def defuzz(S_w: int, S_wg: int) -> int:
    # ratio_q15 = ((S_wg << 15) / max(S_w,1)); percent = (ratio_q15*100)>>15; clamp 0..100
    den = S_w if S_w >= 1 else 1
    ratio_q15 = (int(S_wg) << 15) // den
    percent_u = (ratio_q15 * 100) >> 15
    if percent_u > 100: percent_u = 100
    if percent_u < 0:   percent_u = 0
    return int(percent_u)

# -------------------- Dataclasses --------------------

@dataclass
class MfThresholds:
    a:int; b:int; c:int; d:int

@dataclass
class MfSet3:
    neg:MfThresholds; zero:MfThresholds; pos:MfThresholds

@dataclass
class Singletons:
    g00:int=100; g01:int=50;  g02:int=30
    g10:int=50;  g11:int=50;  g12:int=50
    g20:int=80;  g21:int=50;  g22:int=0

@dataclass
class CoprocessorCfg:
    mf_T:MfSet3
    mf_dT:MfSet3
    singletons:Singletons=Singletons()

DEFAULT_CFG = CoprocessorCfg(
    mf_T=MfSet3(
        neg=MfThresholds(-128,-64,-32,0),
        zero=MfThresholds(-16,0,0,16),
        pos=MfThresholds(0,32,64,127),
    ),
    mf_dT=MfSet3(
        neg=MfThresholds(-100,-50,-30,-5),
        zero=MfThresholds(-10,0,0,10),
        pos=MfThresholds(5,25,35,60),
    ),
    singletons=Singletons()
)

# -------------------- Estimators --------------------

class SimpleDtEstimator:
    """Prosty, nienumeryczny placeholder (zostawiony dla porównań)."""
    def __init__(self, alpha_p:int=32, kdt_p:int=3, dmax_p:int=64):
        self.alpha_p = alpha_p
        self.kdt_p   = kdt_p
        self.dmax_p  = dmax_p
        self.prev_T  = 0
        self.inited  = False
    def reset(self): self.prev_T=0; self.inited=False
    def init_pulse(self, T_cur:int):
        self.prev_T = T_cur; self.inited = True
    def step(self, T_cur:int):
        if not self.inited:
            self.prev_T = T_cur; self.inited = True
            return 0, False
        raw = T_cur - self.prev_T
        self.prev_T = T_cur
        raw >>= max(self.kdt_p, 0)
        filt = (self.alpha_p * raw) >> 8
        dT = clamp_s8(filt)
        if dT >  self.dmax_p: dT =  self.dmax_p
        if dT < -self.dmax_p: dT = -self.dmax_p
        return dT, True

class EstimatorRTLExact:
    """
    Bit-accurate port of dt_estimator.sv (REQ-060/061/062, REQ-210).
    Odwzorowuje:
      - delta_q8 = T_cur - T_prev (signed 9b)
      - delta_q15 = delta_q8 << 7
      - delta_scaled = delta_q15 >>> k_dt
      - Q8.8 alpha path: term1/term2 z <<8 i finalnym sum32[31:16]
      - clamp do ±{d_max,7'b0}
      - dT_out = clip[14:7] (trunc)
      - init/reset i dt_valid
    """
    def __init__(self, alpha:int = 32, k_dt:int = 3, d_max:int = 64):
        self.alpha = alpha & 0xFF       # 0..255
        self.k_dt  = k_dt  & 0xFF       # 0..255 (realnie 0..7)
        self.d_max = sxt(d_max, 8)      # Q7.0 magnitude
        # state
        self.T_prev = 0                 # s8
        self.dT_prev_q15 = 0            # s16
        self.dt_valid = False

    def reset(self):
        self.T_prev = 0
        self.dT_prev_q15 = 0
        self.dt_valid = False

    def init_pulse(self, T_cur: int):
        # sekwencja jak w RTL: przechwyć T_cur, wyzeruj filtr, dt_valid=0
        self.T_prev = sxt(T_cur, 8)
        self.dT_prev_q15 = 0
        self.dt_valid = False

    def step(self, T_cur: int) -> Tuple[int, bool]:
        T_cur_s8  = sxt(T_cur, 8)
        # delta_q8 (s9)
        delta_q8  = sxt(T_cur_s8, 8) - sxt(self.T_prev, 8)
        delta_q8  = sxt(delta_q8, 9)

        # delta_q15 = <<7
        delta_q15 = sxt(delta_q8 << 7, 16)

        # arith >>> k_dt
        sh = min(max(self.k_dt, 0), 31)
        delta_scaled = sxt(delta_q15, 16) >> sh
        delta_scaled = sxt(delta_scaled, 16)

        # Q8.8 alpha path
        alpha_q = self.alpha & 0xFF
        one_q   = 256
        inv_a   = (one_q - alpha_q) & 0xFFFF

        term1 = sxt(self.dT_prev_q15, 16) * sxt((inv_a << 8), 24)
        term2 = sxt(delta_scaled, 16)     * sxt(((alpha_q & 0xFFFF) << 8), 24)
        sum32 = sxt(term1 + term2, 32)
        dT_new_q15 = sxt(sum32 >> 16, 16)

        # clamp ±{d_max,7'b0}
        dmax_q15 = sxt((int(self.d_max) & 0xFF) << 7, 16)
        hi = dmax_q15
        lo = sxt(-dmax_q15, 16)
        clip = dT_new_q15
        if clip > hi: clip = hi
        if clip < lo: clip = lo
        clip = sxt(clip, 16)

        # update seq
        self.T_prev = T_cur_s8
        self.dT_prev_q15 = clip

        # dT_out = clip[14:7] -> s8
        slice_14_7 = (clip >> 7) & 0xFF
        dT_out_s8 = sxt(slice_14_7, 8)

        was_valid = self.dt_valid
        self.dt_valid = True
        return dT_out_s8, was_valid

# -------------------- Top-level ref step --------------------

def fuzzify(x:int, mf:MfSet3)->Tuple[int,int,int]:
    return (
        trapezoid_mu(x, mf.neg.a,  mf.neg.b,  mf.neg.c,  mf.neg.d),
        trapezoid_mu(x, mf.zero.a, mf.zero.b, mf.zero.c, mf.zero.d),
        trapezoid_mu(x, mf.pos.a,  mf.pos.b,  mf.pos.c,  mf.pos.d),
    )

def top_step(T_in:int, dT_in:int, cfg:CoprocessorCfg, reg_mode:int,
             dt_mode:int=0, estimator:Optional[object]=None):
    # dT select (dt_valid zwracamy w dbg dla wglądu)
    if dt_mode==1:
        if estimator is None:
            raise ValueError("dt_mode=1 requires estimator")
        dT_sel, dt_valid = estimator.step(T_in)
    else:
        dT_sel, dt_valid = dT_in, True

    muT = fuzzify(T_in, cfg.mf_T)
    muD = fuzzify(dT_sel, cfg.mf_dT)
    w   = rules9_min(muT[0],muT[1],muT[2], muD[0],muD[1],muD[2])

    g = (cfg.singletons.g00,cfg.singletons.g01,cfg.singletons.g02,
         cfg.singletons.g10,cfg.singletons.g11,cfg.singletons.g12,
         cfg.singletons.g20,cfg.singletons.g21,cfg.singletons.g22)

    S_w, S_wg = aggregate(reg_mode, w, g)
    G = defuzz(S_w, S_wg)
    dbg = {"dT_sel":dT_sel,"dt_valid":dt_valid,"muT":muT,"muD":muD,"w":w,"S_w":S_w,"S_wg":S_wg}
    return G, dbg

# -------------------- CLI --------------------

def _parse_int(s:str)->int:
    v = int(s,0)
    if v < -128 or v > 127: raise ValueError("s8 expected")
    return v

def main(argv: List[str] = None) -> int:
    import argparse, sys, csv, pathlib
    p = argparse.ArgumentParser("Fuzzy coprocessor refmodel")
    p.add_argument("--reg-mode", type=int, default=1, choices=[0,1])
    p.add_argument("--dt-mode",  type=int, default=0, choices=[0,1])

    # single run
    p.add_argument("--T",  type=_parse_int, help="single run T_in (s8)")
    p.add_argument("--dT", type=_parse_int, default=0, help="single run dT_in (s8) for dt_mode=0")

    # batch (dt_mode=0 only)
    p.add_argument("--csv", type=str, help="CSV with columns: T,dT (dt_mode=0 only)")
    p.add_argument("--out", type=str, help="write CSV with: T,dT,G_out,S_w,S_wg")

    # estimator options
    p.add_argument("--est", choices=["simple","exact"], default="exact",
                   help="Estimator backend for dt_mode=1 (default: exact)")
    p.add_argument("--alpha", type=int, default=32, help="Estimator alpha (0..255), ~alpha/256")
    p.add_argument("--kdt",   type=int, default=3,  help="Estimator k_dt (0..7) -> /2^k")
    p.add_argument("--dmax",  type=int, default=64, help="Estimator DMAX clamp (Q7.0 magnitude)")
    p.add_argument("--no-est-init", action="store_true",
                   help="Do NOT perform implicit INIT capture before first step (default: INIT is performed)")

    args = p.parse_args(argv)

    cfg = DEFAULT_CFG

    est = None
    if args.dt_mode==1:
        if args.est == "exact":
            est = EstimatorRTLExact(alpha=args.alpha, k_dt=args.kdt, d_max=args.dmax)
        else:
            est = SimpleDtEstimator(alpha_p=args.alpha, kdt_p=args.kdt, dmax_p=args.dmax)
        # domyślnie zasymuluj INIT (zgodnie z TB), można wyłączyć flagą --no-est-init
        if not args.no_est_init:
            init_T = args.T if args.T is not None else 0
            if hasattr(est, "init_pulse"):
                est.init_pulse(init_T)
            else:
                est.reset()
                est.init_pulse(init_T)  # SimpleDtEstimator też ma init_pulse

    rows = []
    if args.csv:
        if args.dt_mode!=0:
            print("CSV batch only for dt_mode=0", file=sys.stderr); return 2
        with open(args.csv, newline="") as f:
            rdr = csv.DictReader(f)
            for row in rdr:
                T  = _parse_int(row["T"]); dT = _parse_int(row["dT"])
                G, dbg = top_step(T, dT, cfg, args.reg_mode, 0, None)
                rows.append({"T":T,"dT":dT,"G_out":G,"S_w":dbg["S_w"],"S_wg":dbg["S_wg"]})
                print(f"T={T:4d} dT={dT:4d} | G={G:3d} S_w={dbg['S_w']:5d} S_wg={dbg['S_wg']:5d}")
    else:
        if args.T is None:
            print("Provide --T (and --dT) or --csv", file=sys.stderr); return 2
        G, dbg = top_step(args.T, args.dT, cfg, args.reg_mode, args.dt_mode, est)
        print(f"G={G} (S_w={dbg['S_w']}, S_wg={dbg['S_wg']}, dT_sel={dbg['dT_sel']}, dt_valid={dbg['dt_valid']})")

    if args.out and rows:
        pth = pathlib.Path(args.out)
        with pth.open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["T","dT","G_out","S_w","S_wg"])
            w.writeheader(); w.writerows(rows)
        print(f"Saved: {pth}")
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
