# pico_mmio_simple.py — RPi Pico ↔ FPGA (aktywnie HIGH: CS/WR/RD)
# Wgraj jako main.py

from machine import Pin
import time

# ======= PINOUT (Twoje ustawienia) =======
ADDR_BITS     = 6
ADDR_BASE_GP  = 0       # A0..A5 = GP0..GP5
RDATA_BASE_GP = 6       # D_R0..7 = GP6..GP13
WDATA_BASE_GP = 14      # D_W0..7 = GP14..GP21
CS_GP         = 22
WR_GP         = 26
RD_GP         = 27
RDY_GP        = 28      # wejście

# ======= Timingi (µs) — bezpieczne zapasy =======
T_SETUP_US    = 20
T_STROBE_US   = 20
RD_TIMEOUT_US = 20000

# ======= Inicjalizacja pinów =======
A  = [Pin(ADDR_BASE_GP+i,  Pin.OUT, value=0) for i in range(ADDR_BITS)]
DW = [Pin(WDATA_BASE_GP+i, Pin.OUT, value=0) for i in range(8)]
DR = [Pin(RDATA_BASE_GP+i, Pin.IN)           for i in range(8)]
CS = Pin(CS_GP, Pin.OUT, value=0)
WR = Pin(WR_GP, Pin.OUT, value=0)
RD = Pin(RD_GP, Pin.OUT, value=0)
RDY= Pin(RDY_GP, Pin.IN)

# ======= Rejestry (zgodnie z rozmową) =======
REG_STATUS = 0x00  # bit0: valid
REG_CTRL   = 0x01  # START/INIT + tryby
REG_TIN    = 0x02  # T (int8, Q7.0)
REG_DTIN   = 0x03  # dT (int8, Q7.0)
REG_G_OUT  = 0x04  # wynik G (0..255)

# ======= Prymitywy =======
def set_addr(a: int):
    a &= (1<<ADDR_BITS)-1
    for i in range(ADDR_BITS):
        A[i].value((a >> i) & 1)

def put_dw(v: int):
    v &= 0xFF
    for i in range(8):
        DW[i].value((v >> i) & 1)

def get_dr() -> int:
    v = 0
    for i in range(8):
        if DR[i].value():
            v |= (1 << i)
    return v & 0xFF

def write_reg(addr: int, val: int):
    """Zapis: ustaw A, DW; CS=1; (krótko) WR=1; WR=0; CS=0"""
    set_addr(addr)
    put_dw(val)
    time.sleep_us(T_SETUP_US)
    CS.value(1)
    time.sleep_us(T_SETUP_US)
    WR.value(1)
    time.sleep_us(T_STROBE_US)
    WR.value(0)
    time.sleep_us(T_SETUP_US)
    CS.value(0)
    time.sleep_us(T_SETUP_US)

def read_reg(addr: int, timeout_us: int = RD_TIMEOUT_US) -> int:
    """Odczyt: ustaw A; CS=1; RD=1; czekaj na RDY=1; czytaj D_R; RD=0; CS=0"""
    set_addr(addr)
    time.sleep_us(T_SETUP_US)
    CS.value(1)
    time.sleep_us(T_SETUP_US)
    RD.value(1)
    t0 = time.ticks_us()
    while RDY.value() == 0:
        if time.ticks_diff(time.ticks_us(), t0) > timeout_us:
            RD.value(0)
            CS.value(0)
            raise RuntimeError("RD timeout @0x%02X" % (addr & 0xFF))
    v = get_dr()
    time.sleep_us(T_STROBE_US)
    RD.value(0)
    time.sleep_us(T_SETUP_US)
    CS.value(0)
    time.sleep_us(T_SETUP_US)
    return v

# ======= Wyższy poziom =======
def pulse_init():
    # INIT = W1P (np. bit3)
    write_reg(REG_CTRL, 0b00001000)

def pulse_start():
    # START = W1P (np. bit0)
    write_reg(REG_CTRL, 0b00000001)

def set_modes_9rules_dt_external():
    # reg_mode=1, dt_mode=0 → 0b00000010
    write_reg(REG_CTRL, 0b00000010)

def set_modes_9rules_dt_internal():
    # reg_mode=1, dt_mode=1 → 0b00000110
    write_reg(REG_CTRL, 0b00000110)

def poll_valid(max_ms=1000, step_ms=5) -> bool:
    t0 = time.ticks_ms()
    while time.ticks_diff(time.ticks_ms(), t0) < max_ms:
        if read_reg(REG_STATUS) & 0x01:
            return True
        time.sleep_ms(step_ms)
    return False

def run_once_ext(T_val: int, dT_val: int) -> int:
    """Tryb: 9 reguł + dT zewnętrzne. Zapisz T, dT; INIT; START; czekaj; odczytaj G."""
    set_modes_9rules_dt_external()
    write_reg(REG_TIN,  T_val & 0xFF)
    write_reg(REG_DTIN, dT_val & 0xFF)
    pulse_init()
    pulse_start()
    if not poll_valid(max_ms=1000, step_ms=5):
        raise RuntimeError("VALID timeout")
    return read_reg(REG_G_OUT)

def cmd_status():
    s = read_reg(REG_STATUS)
    print("STATUS=0x%02X valid=%d" % (s, s & 1))


# ======= Auto-demo po starcie =======
def demo_once():
    print("BOOT OK")
    print("ADDR_BASE=%d  RDATA_BASE=%d  WDATA_BASE=%d  CS/WR/RD/RDY=%d/%d/%d/%d" %
          (ADDR_BASE_GP, RDATA_BASE_GP, WDATA_BASE_GP, CS_GP, WR_GP, RD_GP, RDY_GP))
    try:
        # przykład: T=+20, dT=+5
        set_modes_9rules_dt_external()
        cmd_status()
        G = run_once_ext(20, 5)
        print("G =", G)
    except Exception as e:
        print("ERROR:", e)
    print("READY. Type: repl()")

if __name__ == "__main__":
    demo_once()
    # wpisz w REPL: repl()

# ========= VIS CSV helpers (match TB) =========
def _open_csv_on_pico(filename: str):
    # zapis z LF; nagłówek jak w TB (Gexp = -1 na sprzęcie)
    f = open(filename, "w")
    f.write("T,dT,Gimpl,Gexp\n")
    return f

def vis_T_at_dt0_csv(path="vis_T_at_dt0.csv"):
    """DT_MODE=0, REG_MODE=1, dT=0, T=-128..127 step 2 (jak TB)."""
    set_modes_9rules_dt_external()
    f = _open_csv_on_pico(path)
    dT = 0
    for T in range(-128, 128, 2):
        G = run_once_ext(T, dT)
        f.write("%d,%d,%d,%d\n" % (T & 0xFF if T < 0 else T, dT & 0xFF if dT < 0 else dT, G, -1))
    f.flush(); f.close()
    print("INFO: VIS_T_at_dt0 ->", path)

def vis_dT_lines_csv(path="vis_dT_lines.csv"):
    """DT_MODE=0, REG_MODE=1, T in {-32,0,32}, dT=-60..60 step 4 (jak TB)."""
    set_modes_9rules_dt_external()
    f = _open_csv_on_pico(path)
    for T in (-32, 0, 32):
        for dT in range(-60, 61, 4):
            G = run_once_ext(T, dT)
            f.write("%d,%d,%d,%d\n" % (T & 0xFF if T < 0 else T, dT & 0xFF if dT < 0 else dT, G, -1))
    f.flush(); f.close()
    print("INFO: VIS_dT_lines ->", path)

def vis_heatmap_csv(path="vis_heatmap.csv"):
    """DT_MODE=0, REG_MODE=1, T=-64..64 step 8, dT=-60..60 step 5 (jak TB)."""
    set_modes_9rules_dt_external()
    f = _open_csv_on_pico(path)
    for T in range(-64, 65, 8):
        for dT in range(-60, 61, 5):
            G = run_once_ext(T, dT)
            f.write("%d,%d,%d,%d\n" % (T & 0xFF if T < 0 else T, dT & 0xFF if dT < 0 else dT, G, -1))
    f.flush(); f.close()
    print("INFO: VIS_heatmap ->", path)

# (opcjonalnie) prosty grid 10x7 jak w TB Block 1, jedna warstwa CSV z minimalnym meta
def grid_10x7_csv(path="grid_10x7.csv"):
    """DT_MODE=0, REG_MODE=1, GRID T(10)×dT(7) — tożsame punkty jak TB GRID."""
    Ts  = [-128, -64, -32, -16, 0, 16, 32, 64, 96, 127]
    dTs = [-60, -30, -10, 0, 10, 30, 60]
    set_modes_9rules_dt_external()
    f = _open_csv_on_pico(path)
    for T in Ts:
        for dT in dTs:
            G = run_once_ext(T, dT)
            f.write("%d,%d,%d,%d\n" % (T & 0xFF if T < 0 else T, dT & 0xFF if dT < 0 else dT, G, -1))
    f.flush(); f.close()
    print("INFO: GRID_10x7 ->", path)

# ========= REPL commands for convenience =========
def repl_help():
    print("cmds:")
    print("  wr a v        -> write reg (np. wr 0x02 20)")
    print("  rd a          -> read reg  (np. rd 0x04)")
    print("  modes_ext     -> 9 rules + dT external")
    print("  modes_int     -> 9 rules + dT internal")
    print("  init          -> pulse INIT")
    print("  start         -> pulse START")
    print("  status        -> print STATUS + valid bit")
    print("  goext T dT    -> run once (ext dT)")
    print("  vis_t0        -> make vis_T_at_dt0.csv")
    print("  vis_lines     -> make vis_dT_lines.csv")
    print("  vis_heatmap   -> make vis_heatmap.csv")
    print("  grid          -> make grid_10x7.csv")
    print("  dump <file>   -> print file to console")
    print("  help")

def _dump_file(p):
    try:
        with open(p, "r") as f:
            for line in f:
                # bez CRLF, czyste LF
                print(line.rstrip("\n"))
    except Exception as e:
        print("ERR:", e)

def repl():
    repl_help()
    while True:
        try:
            line = input(">> ").strip()
        except EOFError:
            break
        if not line:
            continue
        parts = line.split()
        cmd = parts[0].lower()
        try:
            if cmd == "wr" and len(parts) == 3:
                a = int(parts[1], 0); v = int(parts[2], 0)
                write_reg(a, v); print("ok")
            elif cmd == "rd" and len(parts) == 2:
                a = int(parts[1], 0); print("0x%02X" % read_reg(a))
            elif cmd == "modes_ext":
                set_modes_9rules_dt_external(); print("ok")
            elif cmd == "modes_int":
                set_modes_9rules_dt_internal(); print("ok")
            elif cmd == "init":
                pulse_init(); print("ok")
            elif cmd == "start":
                pulse_start(); print("ok")
            elif cmd == "status":
                cmd_status()
            elif cmd == "goext" and len(parts) == 3:
                T = int(parts[1], 0); dT = int(parts[2], 0)
                G = run_once_ext(T, dT); print("G =", G)
            elif cmd == "vis_t0":
                vis_T_at_dt0_csv(); print("done")
            elif cmd == "vis_lines":
                vis_dT_lines_csv(); print("done")
            elif cmd == "vis_heatmap":
                vis_heatmap_csv(); print("done")
            elif cmd == "grid":
                grid_10x7_csv(); print("done")
            elif cmd == "dump" and len(parts) == 2:
                _dump_file(parts[1])
            elif cmd == "help":
                repl_help()
            else:
                print("??? (help)")
        except Exception as e:
            print("ERR:", e)
