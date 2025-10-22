# ref_model.py
# Reference model for the Fuzzy Logic coprocessor (Sugeno 0-order)
# Mirrors the RTL fixed-point behavior used in the thesis design.
# No external deps; pure integer math. Python ints are unbounded, so we
# emulate bit widths and saturation explicitly.

# ------------------------------
# Q-format helpers
# ------------------------------
def clamp_u16(x: int) -> int:
    """Clamp to unsigned 16-bit."""
    return max(0, min(0xFFFF, int(x)))

def clamp_s8(x: int) -> int:
    """Clamp to signed 8-bit (-128..127)."""
    x = int(x)
    if x > 127:  return 127
    if x < -128: return -128
    return x

def q15_to_pct(q15: int) -> int:
    """Convert Q1.15 (0..32767) to integer percent 0..100 (truncate)."""
    return (int(q15) * 100) >> 15

def pct_to_q15(g_pct: int) -> int:
    """
    Percent (0..100) -> Q1.15 (0..32767).
    RTL uses scaling to 32767 with rounding and clamp.
    """
    gp = max(0, min(100, int(g_pct)))
    tmp = gp * 32767 + 50  # +0.5 for /100 rounding
    tmp //= 100
    if tmp > 32767:
        tmp = 32767
    return int(tmp)  # 0..32767

# ------------------------------
# Trapezoid MF (Q7.0 → Q1.15)
# ------------------------------
def trapezoid_mu(x: int, a: int, b: int, c: int, d: int) -> int:
    """
    Inputs x,a,b,c,d are signed 8-bit (Q7.0). Output μ is Q1.15 (0..32767).
    Mirrors RTL: guards divide-by-zero, uses widening (<<7 then <<8) before /den.
    """
    # outside support
    if x <= a or x >= d:
        return 0
    # plateau
    if x >= b and x <= c:
        return 0x7FFF

    # left slope: (x-a)/(b-a)
    if x > a and x < b:
        dx1 = int(b) - int(a)           # 0..255
        xb  = int(x) - int(a)           # 0..(b-a)
        den = dx1 if dx1 != 0 else 1
        num_q87 = (xb & 0xFF) << 7      # Q8.7
        num_q15 = num_q87 << 8          # widen to Q1.15 (like RTL)
        return min(0x7FFF, num_q15 // den)

    # right slope: (d-x)/(d-c)
    dx2 = int(d) - int(c)
    xa  = int(d) - int(x)
    den = dx2 if dx2 != 0 else 1
    num_q87 = (xa & 0xFF) << 7
    num_q15 = num_q87 << 8
    return min(0x7FFF, num_q15 // den)

# ------------------------------
# Fuzzifiers
# ------------------------------
def fuzzifier_three(x: int, params):
    """
    Generic 3-set fuzzifier: params = dict with keys:
    neg=(a,b,c,d), zero=(a,b,c,d), pos=(a,b,c,d)
    All params are signed 8-bit numbers.
    Returns tuple (mu_neg, mu_zero, mu_pos) in Q1.15.
    """
    (an,bn,cn,dn) = params["neg"]
    (az,bz,cz,dz) = params["zero"]
    (ap,bp,cp,dp) = params["pos"]
    mu_neg  = trapezoid_mu(x, an,bn,cn,dn)
    mu_zero = trapezoid_mu(x, az,bz,cz,dz)
    mu_pos  = trapezoid_mu(x, ap,bp,cp,dp)
    return mu_neg, mu_zero, mu_pos

# ------------------------------
# Rules (min t-norm)
# ------------------------------
def rules4(muT_neg, muT_pos, muD_neg, muD_pos):
    """4-corner rule weights (Q1.15)."""
    f = min
    return (f(muT_neg, muD_neg),
            f(muT_neg, muD_pos),
            f(muT_pos, muD_neg),
            f(muT_pos, muD_pos))

def rules9(muT_neg, muT_zero, muT_pos, muD_neg, muD_zero, muD_pos):
    """Full 3x3 grid of rule weights (Q1.15)."""
    f=min
    w00=f(muT_neg ,muD_neg ); w01=f(muT_neg ,muD_zero); w02=f(muT_neg ,muD_pos )
    w10=f(muT_zero,muD_neg ); w11=f(muT_zero,muD_zero); w12=f(muT_zero,muD_pos )
    w20=f(muT_pos ,muD_neg ); w21=f(muT_pos ,muD_zero); w22=f(muT_pos ,muD_pos )
    return w00,w01,w02,w10,w11,w12,w20,w21,w22

# ------------------------------
# Aggregator (Σw, Σw·g) with rounding and saturation
# ------------------------------
def aggregator(reg_mode: int, w, g):
    """
    reg_mode: 0 -> 4-rule (corners only), 1 -> 9-rule (full grid).
    w: 9-tuple of weights in Q1.15 (non-negative).
    g: 9-tuple of singleton percentages (0..100).
    Returns (S_w, S_wg) in Q1.15 with saturation to 0..32767.
    Mirrors RTL rounding of (w*g_q15)>>15 and wide accumulators.
    """
    (w00,w01,w02,w10,w11,w12,w20,w21,w22) = w
    (g00,g01,g02,g10,g11,g12,g20,g21,g22) = g
    # Gate middle/edges in 4-rule mode
    if reg_mode == 0:
        w01=w10=w11=w12=w21=0

    def mul_q15(w_i, g_pct):
        prod = w_i * pct_to_q15(g_pct) + (1<<14)  # add half LSB for rounding
        return prod >> 15

    # Weighted terms
    gw00=mul_q15(w00,g00); gw01=mul_q15(w01,g01); gw02=mul_q15(w02,g02)
    gw10=mul_q15(w10,g10); gw11=mul_q15(w11,g11); gw12=mul_q15(w12,g12)
    gw20=mul_q15(w20,g20); gw21=mul_q15(w21,g21); gw22=mul_q15(w22,g22)

    # Wide Σ to avoid overflow (16b + ceil(log2(9)) ≈ 20b)
    Sw  = (w00+w01+w02+w10+w11+w12+w20+w21+w22)
    Swg = (gw00+gw01+gw02+gw10+gw11+gw12+gw20+gw21+gw22)

    # Saturate back to Q1.15 range 0..32767
    Sw  = min(Sw , 32767)
    Swg = min(Swg, 32767)
    return Sw, Swg

# ------------------------------
# Defuzz (ratio * 100 with epsilon guard)
# ------------------------------
def defuzz(Sw: int, Swg: int) -> int:
    """
    Inputs Q1.15, output integer 0..100.
    Uses epsilon=1 (1 LSB) on denominator, truncation like RTL.
    """
    den = Sw if Sw >= 1 else 1
    ratio_q15 = (Swg << 15) // den      # Q1.15
    percent   = (ratio_q15 * 100) >> 15 # integer
    if percent > 100: percent = 100
    if percent < 0:   percent = 0
    return int(percent)

# ------------------------------
# dT estimator (EMA), internal Q0.7, INIT behavior
# ------------------------------
class DtEstimator:
    """
    Mirrors RTL:
      - alpha: 0..255 (~alpha/256 in Q8.8)
      - k_dt:  shift right (divide by 2^k)
      - d_max: clamp magnitude in Q7.0
      - State: T_prev (Q7.0), dT_prev_q15 (Q0.7 stored in Q1.15 container)
      - Output: dT_out is Q7.0 (int8), taken as bits [14:7] of internal Q0.7
    """
    def __init__(self):
        self.T_prev = 0                  # int8
        self.dT_prev_q15 = 0             # Q0.7 in Q1.15 container
        self.valid = False

    def reset(self):
        self.T_prev = 0
        self.dT_prev_q15 = 0
        self.valid = False

    def init_pulse(self, T_cur: int):
        """INIT pulse behavior: capture T_cur, zero internal state, valid=0."""
        self.T_prev = clamp_s8(T_cur)
        self.dT_prev_q15 = 0
        self.valid = False

    @staticmethod
    def _clip_q15(x: int, d_max: int) -> int:
        """Clamp internal Q0.7 (in Q1.15 container) to ±d_max (Q7.0)."""
        lim = (int(d_max) << 7)  # Q0.7 limit
        if x >  lim: return lim
        if x < -lim: return -lim
        return x

    def step(self, T_cur: int, alpha: int, k_dt: int, d_max: int):
        """
        One EMA step. Returns (dT_out:int8, valid:bool).
        """
        # delta in Q8.0
        delta_q8 = int(clamp_s8(T_cur)) - int(clamp_s8(self.T_prev))
        # Q0.7 in Q1.15 container
        delta_q15 = delta_q8 << 7
        delta_scaled = (delta_q15 >> int(k_dt)) if k_dt >= 0 else (delta_q15 << (-int(k_dt)))

        alpha_q = int(alpha)      # 0..255, Q8.8 fraction without point
        one_q   = 256
        inv_a   = one_q - alpha_q

        # Q0.7 * Q8.8 -> align by <<8 like RTL, accumulate in 32-bit Python ints
        term1 = int(self.dT_prev_q15) * (inv_a << 8)
        term2 = int(delta_scaled)  * (alpha_q << 8)
        sum32 = term1 + term2
        dT_new_q15 = (sum32 >> 16)  # back to Q0.7 (in Q1.15 container)

        dT_new_q15 = self._clip_q15(dT_new_q15, d_max)

        # Update state & produce output (Q7.0 from bits [14:7])
        self.T_prev = clamp_s8(T_cur)
        self.dT_prev_q15 = int(dT_new_q15)
        self.valid = True
        dT_out_q7_0 = clamp_s8(dT_new_q15 >> 7)  # bits [14:7]
        return dT_out_q7_0, self.valid

# ------------------------------
# Top-level one-sample evaluation
# ------------------------------
def coproc_step(
    # inputs
    T: int, dT_ext: int, use_internal_dt: bool,
    # fuzzifier params
    T_params: dict, dT_params: dict,
    # singletons (row-major 3x3)
    g: tuple,
    # reg mode
    reg_mode: int,
    # estimator state & params
    est: DtEstimator = None, alpha: int = 32, k_dt: int = 3, d_max: int = 64
):
    """
    Evaluate one sample through the full chain and return (G_out, debug_dict).
    If use_internal_dt=True, uses estimator 'est' (must be provided/initialized).
    """
    # Select dT source
    if use_internal_dt:
        assert est is not None, "Estimator instance required for internal dT."
        dT_val, _ = est.step(T_cur=T, alpha=alpha, k_dt=k_dt, d_max=d_max)
    else:
        dT_val = clamp_s8(dT_ext)

    # Fuzzify
    muT = fuzzifier_three(clamp_s8(T),  T_params)  # (neg,zero,pos)
    muD = fuzzifier_three(clamp_s8(dT_val), dT_params)

    # Rules (9)
    w = rules9(muT[0], muT[1], muT[2], muD[0], muD[1], muD[2])

    # Aggregate
    Sw, Swg = aggregator(reg_mode, w, g)

    # Defuzz
    G_out = defuzz(Sw, Swg)

    dbg = {
        "muT": muT, "muD": muD,
        "w": w, "S_w": Sw, "S_wg": Swg,
        "G_out": G_out, "dT_used": dT_val
    }
    return G_out, dbg

# ------------------------------
# Quick self-check (executed when run as a script)
# ------------------------------
if __name__ == "__main__":
    # Simple symmetric triangles
    tri = (-64, 0, 0, 64)
    T_params  = {"neg": tri, "zero": (-16,-1,1,16), "pos": (0,32,64,80)}
    dT_params = {"neg": tri, "zero": (-16,-1,1,16), "pos": (0,32,64,80)}

    # Singletons: only (pos,pos)=100%
    g = (0,0,0, 0,0,0, 0,0,100)

    # External dT, REG_MODE=9 rules
    G, dbg = coproc_step(T=32, dT_ext=32, use_internal_dt=False,
                         T_params=T_params, dT_params=dT_params,
                         g=g, reg_mode=1)
    print("G_out =", G, " %  | S_w =", q15_to_pct(dbg["S_w"]), "%")
    assert 40 <= G <= 60
    print("Self-check OK.")
