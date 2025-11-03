# test_refmodel.py — PyTest suite odzwierciedlający tb_top_coprocessor.sv (wersja pod "class" fuzzy_refmodel)
# Covers: REQ-010/020/030/040/050/060/061/062/210/230/310/320
# - Zakres przypadków jak w TB (GRID dla dt_mode=0; MAE losowe; estymator INIT/rampa/down/randwalk)
# - Eksport CSV w tym samym formacie/nazwach kolumn co TB
# - Używa pól cfg.mf_T / cfg.mf_dT (zamiast T/dT) i reguł rules9_min(muTn,muTz,muTp,muDn,muDz,muDp)

import os
import random
import pathlib
import pytest

from fuzzy_refmodel import (
    Q15_MAX,
    MfThresholds, MfSet3, CoprocessorCfg, Singletons,
    g2q15_percent, mul_q15_round, trapezoid_mu, rules9_min, aggregate, defuzz,
    top_step, EstimatorRTLExact, SimpleDtEstimator, fuzzify,
)

# ================== Konfiguracja równoważna TB ==================

# Singletons (G00..G22) jak w TB
SINGLETONS_TB = Singletons(
    g00=100, g01=50,  g02=30,
    g10=50,  g11=50,  g12=50,
    g20=80,  g21=50,  g22=0,
)

# Progi MF jak w TB (set_mf_defaults)
MF_T_TB = MfSet3(
    neg=MfThresholds(a=-128, b=-64,  c=-32, d=0),
    zero=MfThresholds(a=-16,  b=0,    c=0,   d=16),
    pos=MfThresholds(a=0,     b=32,   c=64,  d=127),
)
MF_DT_TB = MfSet3(
    neg=MfThresholds(a=-100, b=-50, c=-30, d=-5),
    zero=MfThresholds(a=-10,  b=0,   c=0,   d=10),
    pos=MfThresholds(a=5,     b=25,  c=35,  d=60),
)

CFG_TB = CoprocessorCfg(mf_T=MF_T_TB, mf_dT=MF_DT_TB, singletons=SINGLETONS_TB)

ALPHA_CONST = 32  # jak w TB (ALPHA_P)
KDT_CONST   = 3   # jak w TB (KDT_P)

# ================== CSV helpers (format jak w TB) ==================

def _csv_open():
    csv_path = os.environ.get("CSV", "out/results_tb.csv")
    try:
        pathlib.Path(csv_path).parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    fd = open(csv_path, "w", encoding="utf-8")
    return fd, csv_path


def _csv_header(fd):
    hdr = (
        "run_id,source,case_id,idx,reg_mode,dt_mode," \
        "T_in,dT_in,alpha,k_dt," \
        "Tneg_a,Tneg_b,Tneg_c,Tneg_d," \
        "Tzero_a,Tzero_b,Tzero_c,Tzero_d," \
        "Tpos_a,Tpos_b,Tpos_c,Tpos_d," \
        "dTneg_a,dTneg_b,dTneg_c,dTneg_d," \
        "dTzero_a,dTzero_b,dTzero_c,dTzero_d," \
        "dTpos_a,dTpos_b,dTpos_c,dTpos_d," \
        "S_w,S_wg,G_exp,G_impl,valid_impl," \
        "tool_ver,git_rev,seed"
    )
    fd.write(hdr + "\n")


def _csv_emit(fd, run_id, source, case_id, idx, reg_mode, dt_mode,
              T_in, dT_in, alpha, k_dt,
              cfg: CoprocessorCfg,
              Sw, Swg, Gexp, Gimpl, valid_impl,
              tool_ver, git_rev, seed_meta):
    line = (
        f"{run_id},{source},{case_id},{idx},{reg_mode},{dt_mode},"
        f"{T_in},{dT_in},{alpha},{k_dt},"
        f"{cfg.mf_T.neg.a},{cfg.mf_T.neg.b},{cfg.mf_T.neg.c},{cfg.mf_T.neg.d},"
        f"{cfg.mf_T.zero.a},{cfg.mf_T.zero.b},{cfg.mf_T.zero.c},{cfg.mf_T.zero.d},"
        f"{cfg.mf_T.pos.a},{cfg.mf_T.pos.b},{cfg.mf_T.pos.c},{cfg.mf_T.pos.d},"
        f"{cfg.mf_dT.neg.a},{cfg.mf_dT.neg.b},{cfg.mf_dT.neg.c},{cfg.mf_dT.neg.d},"
        f"{cfg.mf_dT.zero.a},{cfg.mf_dT.zero.b},{cfg.mf_dT.zero.c},{cfg.mf_dT.zero.d},"
        f"{cfg.mf_dT.pos.a},{cfg.mf_dT.pos.b},{cfg.mf_dT.pos.c},{cfg.mf_dT.pos.d},"
        f"{Sw},{Swg},{Gexp},{Gimpl},{1 if valid_impl else 0},"
        f"{tool_ver},{git_rev},{seed_meta}"
    )
    fd.write(line + "\n")


# ================== Pomocnicze: bit-accurate ścieżka jak w TB ==================

def _fuzzify_TD(T: int, dT: int, cfg: CoprocessorCfg):
    muT = fuzzify(T, cfg.mf_T)
    muD = fuzzify(dT, cfg.mf_dT)
    return muT, muD


def _weights_q15(muT, muD):
    # rules9_min(muTn,muTz,muTp,muDn,muDz,muDp)
    return rules9_min(muT[0], muT[1], muT[2], muD[0], muD[1], muD[2])


def _agg_and_defuzz(reg_mode: int, w, singletons: Singletons):
    g = (
        singletons.g00, singletons.g01, singletons.g02,
        singletons.g10, singletons.g11, singletons.g12,
        singletons.g20, singletons.g21, singletons.g22,
    )
    Sw, Swg = aggregate(reg_mode, w, g)
    Gexp = defuzz(Sw, Swg)
    return Sw, Swg, Gexp


# ================== Parametry wykonania (jak plusargs w TB) ==================

def _env(name, default):
    val = os.environ.get(name)
    return val if val is not None else default

RUN_ID    = _env("RUN_ID",  "tb_run")
GIT_REV   = _env("GIT_REV",  "")
TOOL_VER  = _env("TOOL_VER", "PyTest")
SOURCE_ID = _env("SOURCE",  "py")
SEED_META = int(_env("SEED", "0") or 0)

# ================== Testy ==================

@pytest.fixture(scope="module")
def csv_file():
    fd, path = _csv_open()
    _csv_header(fd)
    yield fd
    try:
        fd.flush()
        fd.close()
    except Exception:
        pass


def _grid_T_values():
    return [-128, -64, -32, -16, 0, 16, 32, 64, 96, 127]


def _grid_dT_values():
    return [-60, -30, -10, 0, 10, 30, 60]


# ---- Block 1: DT_MODE=0, GRID + edge case (REQ-010/020/030/040/050/210) ----
@pytest.mark.parametrize("reg_mode", [0, 1])
def test_grid_dt_mode0(csv_file, reg_mode):
    if SEED_META:
        random.seed(SEED_META)
    idx = 0

    for T in _grid_T_values():
        for dT in _grid_dT_values():
            muT, muD = _fuzzify_TD(T, dT, CFG_TB)
            w = _weights_q15(muT, muD)
            Sw, Swg, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)

            Gimpl, dbg = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)

            assert 0 <= Sw <= Q15_MAX
            assert 0 <= Swg <= Q15_MAX
            assert Gimpl == Gexp

            _csv_emit(
                csv_file, RUN_ID, SOURCE_ID,
                case_id=f"Grid_T={T}_dT={dT}", idx=idx,
                reg_mode=reg_mode, dt_mode=0,
                T_in=T, dT_in=dT, alpha=ALPHA_CONST, k_dt=KDT_CONST,
                cfg=CFG_TB,
                Sw=Sw, Swg=Swg, Gexp=Gexp, Gimpl=Gimpl, valid_impl=True,
                tool_ver=TOOL_VER, git_rev=GIT_REV, seed_meta=SEED_META,
            )
            idx += 1


# Edge: sum_w ≈ 0 → G=0
def test_edge_sumw_zero_dt_mode0(csv_file):
    reg_mode = 1
    T, dT = -128, 127
    muT, muD = _fuzzify_TD(T, dT, CFG_TB)
    w = _weights_q15(muT, muD)
    Sw, Swg, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
    Gimpl, dbg = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)
    assert Gexp == 0
    assert Gimpl == Gexp
    _csv_emit(
        csv_file, RUN_ID, SOURCE_ID,
        case_id="Edge_sumw_zero", idx=0,
        reg_mode=reg_mode, dt_mode=0,
        T_in=T, dT_in=dT, alpha=ALPHA_CONST, k_dt=KDT_CONST,
        cfg=CFG_TB,
        Sw=Sw, Swg=Swg, Gexp=Gexp, Gimpl=Gimpl, valid_impl=True,
        tool_ver=TOOL_VER, git_rev=GIT_REV, seed_meta=SEED_META,
    )


# ---- Block 2: DT_MODE=0, losowe MAE (REQ-310 <= 1%) ----

def test_random_mae_dt_mode0(csv_file):
    N = 1000
    reg_mode = 1
    mae_acc = 0
    idx = 0
    if SEED_META:
        random.seed(SEED_META)
    for _ in range(N):
        T = random.randint(-128, 127)
        dT = random.randint(-128, 127)
        muT, muD = _fuzzify_TD(T, dT, CFG_TB)
        w = _weights_q15(muT, muD)
        Sw, Swg, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
        Gimpl, dbg = top_step(T, dT, CFG_TB, reg_mode, dt_mode=0, estimator=None)

        diff = abs(Gimpl - Gexp)
        mae_acc += diff

        _csv_emit(
            csv_file, RUN_ID, SOURCE_ID,
            case_id="Random", idx=idx,
            reg_mode=reg_mode, dt_mode=0,
            T_in=T, dT_in=dT, alpha=ALPHA_CONST, k_dt=KDT_CONST,
            cfg=CFG_TB,
            Sw=Sw, Swg=Swg, Gexp=Gexp, Gimpl=Gimpl, valid_impl=True,
            tool_ver=TOOL_VER, git_rev=GIT_REV, seed_meta=SEED_META,
        )
        idx += 1

    mae = mae_acc // N
    assert mae <= 1, f"[REQ-310] MAE={mae}% > 1%"


# ---- Block 3: DT_MODE=1, scenariusze estymatora (REQ-060/061/062/230/320) ----

def _golden_at_dT0(T: int, reg_mode: int):
    muT, muD0 = _fuzzify_TD(T, 0, CFG_TB)
    w = _weights_q15(muT, muD0)
    Sw, Swg, Gexp = _agg_and_defuzz(reg_mode, w, CFG_TB.singletons)
    return Gexp


def test_estimator_flow_dt_mode1(csv_file):
    reg_mode = 1
    dt_mode = 1

    est = EstimatorRTLExact(alpha=ALPHA_CONST, k_dt=KDT_CONST, d_max=64)
    est.init_pulse(0)

    # INIT: oczekujemy zgodności z dT=0 dla T=0
    T = 0
    Gexp_init = _golden_at_dT0(T, reg_mode)
    Gimpl, dbg = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
    _csv_emit(csv_file, RUN_ID, SOURCE_ID, "EST_INIT", 0,
              reg_mode, dt_mode, T, 0, ALPHA_CONST, KDT_CONST,
              CFG_TB, -1, -1, -1, Gimpl, True, TOOL_VER, GIT_REV, SEED_META)
    assert 0 <= Gimpl <= 100
    assert Gimpl == Gexp_init, f"[REQ-062] after INIT got={Gimpl} exp={Gexp_init}"

    # Dwa przebiegi w stanie ustalonym
    for _ in range(2):
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
        assert 0 <= Gimpl <= 100

    # Ramp up 0->+40 co 2
    idx_up = 0
    for i in range(20):
        T = i * 2
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
        _csv_emit(csv_file, RUN_ID, SOURCE_ID, "EST_RampUp", idx_up,
                  reg_mode, dt_mode, T, 0, ALPHA_CONST, KDT_CONST,
                  CFG_TB, -1, -1, -1, Gimpl, True, TOOL_VER, GIT_REV, SEED_META)
        assert 0 <= Gimpl <= 100
        idx_up += 1

    # Ramp down +40->0
    idx_dn = 0
    for i in range(20, -1, -1):
        T = i * 2
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
        _csv_emit(csv_file, RUN_ID, SOURCE_ID, "EST_RampDown", idx_dn,
                  reg_mode, dt_mode, T, 0, ALPHA_CONST, KDT_CONST,
                  CFG_TB, -1, -1, -1, Gimpl, True, TOOL_VER, GIT_REV, SEED_META)
        assert 0 <= Gimpl <= 100
        idx_dn += 1

    # Random walk (100 kroków)
    T = 0
    idx_rw = 0
    for i in range(100):
        step = random.randint(-5, 5)
        nxt = T + step
        if nxt > 127: nxt = 127
        if nxt < -128: nxt = -128
        T = nxt
        Gimpl, _ = top_step(T, 0, CFG_TB, reg_mode, dt_mode, est)
        _csv_emit(csv_file, RUN_ID, SOURCE_ID, "EST_RandWalk", idx_rw,
                  reg_mode, dt_mode, T, 0, ALPHA_CONST, KDT_CONST,
                  CFG_TB, -1, -1, -1, Gimpl, True, TOOL_VER, GIT_REV, SEED_META)
        assert 0 <= Gimpl <= 100
        idx_rw += 1


# ---- Drobne sanity zgodnie z wcześniejszymi testami (opcjonalne) ----

def test_req210_percent_q15_mapping_and_mul_round():
    assert g2q15_percent(0) == 0
    assert g2q15_percent(100) == Q15_MAX
    mid = g2q15_percent(50)
    assert 16000 <= mid <= 16400
    q15_half = mid
    q15_quarter = mul_q15_round(q15_half, q15_half)
    assert 8000 <= q15_quarter <= 8400


def test_req020_trapezoid_mu_samples():
    # Kilka próbek, kompletne pokrycie jest w GRID
    assert trapezoid_mu(-5, 0, 10, 10, 30) == 0
    assert trapezoid_mu(10, 0, 10, 10, 30) == Q15_MAX
    assert trapezoid_mu(30, 0, 10, 10, 30) == 0
