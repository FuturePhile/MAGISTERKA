from machine import Pin
import time

# ===== KONFIG: wpisz bazy dla swoich taśm =====
ADDR_BITS     = 6                      # 0..0x27 → 6 bitów
ADDR_BASE_GP  = 0                      # A0..A5 = GP0..GP5
RDATA_BASE_GP = 6   # D_R0..7 zaraz po adresie
WDATA_BASE_GP = 14          # D_W0..7 zaraz po D_R
CS_GP         = 22          # dalej CS, WR, RD, RDY po kolei
WR_GP         = 26
RD_GP         = 27
RDY_GP        = 28               # wejście

# ===== Delaye (µs) — zapas przy 20/50 MHz w FPGA =====
T_SETUP_US    = 1
T_STROBE_US   = 1
RD_TIMEOUT_US = 20000

# ===== Inicjalizacja pinów =====
A  = [Pin(ADDR_BASE_GP+i,  Pin.OUT, value=0) for i in range(ADDR_BITS)]
DW = [Pin(WDATA_BASE_GP+i, Pin.OUT, value=0) for i in range(8)]
DR = [Pin(RDATA_BASE_GP+i, Pin.IN)           for i in range(8)]
CS = Pin(CS_GP, Pin.OUT, value=0)
WR = Pin(WR_GP, Pin.OUT, value=0)
RD = Pin(RD_GP, Pin.OUT, value=0)
RDY= Pin(RDY_GP, Pin.IN)

# ===== Prosty rejestr map (zgodny z Twoim projektem) =====
REG_STATUS = 0x00  # bit0: valid
REG_CTRL   = 0x01  # [3]=INIT(W1P), [0]=START(W1P), [1]=reg_mode(1=9r), [2]=dt_mode(1=internal)
REG_TIN    = 0x02  # T_in (Q7.0, int8)
REG_DTIN   = 0x03  # dT_in (Q7.0, int8) — używane przy dt_mode=external
REG_G_OUT  = 0x04  # wynik G (8-bit)

# ===== Niskopoziomowe prymitywy =====
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
    return v

def write_reg(addr: int, val: int):
    set_addr(addr)
    put_dw(val)
    time.sleep_us(T_SETUP_US)
    CS.value(1); WR.value(1)
    time.sleep_us(T_STROBE_US)
    WR.value(0); CS.value(0)
    time.sleep_us(T_SETUP_US)

def read_reg(addr: int, timeout_us: int = RD_TIMEOUT_US) -> int:
    set_addr(addr)
    time.sleep_us(T_SETUP_US)
    CS.value(1); RD.value(1)
    t0 = time.ticks_us()
    while RDY.value() == 0:
        if time.ticks_diff(time.ticks_us(), t0) > timeout_us:
            RD.value(0); CS.value(0)
            raise RuntimeError("RD timeout @0x%02X" % (addr & 0xFF))
    v = get_dr()
    time.sleep_us(T_STROBE_US)
    RD.value(0); CS.value(0)
    time.sleep_us(T_SETUP_US)
    return v & 0xFF

# ===== Wyższy poziom: tryby, INIT/START, polling =====
def pulse_init():
    # INIT = bit3 w REG_CTRL, W1P (write-one pulse)
    write_reg(REG_CTRL, 0b00001000)

def pulse_start():
    # START = bit0 w REG_CTRL, W1P
    write_reg(REG_CTRL, 0b00000001)

def set_modes_9rules_dtinternal():
    # 9 reguł + dT internal → 0b00000110
    write_reg(REG_CTRL, 0b00000110)

def set_modes_9rules_dt_external():
    # reg_mode=1 (bit1), dt_mode=0 (bit2=0)
    write_reg(REG_CTRL, 0b00000010)

def poll_valid(max_ms=1000, step_ms=5) -> bool:
    t0 = time.ticks_ms()
    while time.ticks_diff(time.ticks_ms(), t0) < max_ms:
        if read_reg(REG_STATUS) & 0x01:
            return True
        time.sleep_ms(step_ms)
    return False

# ===== Scenariusze wykonania =====
def run_once(T_val: int = 20) -> int:
    """
    9 reguł + dT internal; wpisz T, zrób INIT/START, czekaj na VALID, zwróć G.
    """
    set_modes_9rules_dtinternal()
    write_reg(REG_TIN, T_val & 0xFF)
    pulse_init()
    pulse_start()
    if not poll_valid(max_ms=1000, step_ms=5):
        raise RuntimeError("VALID timeout")
    return read_reg(REG_G_OUT)

def run_once_ext(T_val: int, dT_val: int) -> int:
    """
    9 reguł + dT external; wpisz T oraz dT, INIT/START, czekaj na VALID, zwróć G.
    """
    set_modes_9rules_dt_external()
    write_reg(REG_TIN,  T_val  & 0xFF)  # int8 two's complement
    write_reg(REG_DTIN, dT_val & 0xFF)
    pulse_init()
    pulse_start()
    if not poll_valid(max_ms=1000, step_ms=5):
        raise RuntimeError("VALID timeout")
    return read_reg(REG_G_OUT)

# ===== Test/diagnostyka: wiggle, status, siatki =====
def dump_status():
    try:
        s = read_reg(REG_STATUS)
        print("STATUS=0x%02X valid=%d" % (s, s & 1))
    except Exception as e:
        print("STATUS read ERR:", e)

def wiggle_addr():
    print("Addr walk-1...")
    for a in range(1<<ADDR_BITS):
        set_addr(a)
        time.sleep_ms(1)
    print("OK")

def wiggle_ctrl():
    print("CTRL pulses...")
    pulse_init(); time.sleep_ms(1)
    pulse_start(); time.sleep_ms(1)
    print("OK")

def sweep(vectors=None, use_external=True):
    """
    Krótka siatka testów. Dla use_external=True używa run_once_ext(T,dT),
    w przeciwnym razie run_once(T).
    """
    if vectors is None:
        vectors = [(0,0),(+20,0),(0,+10),(0,-10),(+40,+10),(-40,-10)]
    for t, dt in vectors:
        try:
            if use_external:
                g = run_once_ext(t, dt)
            else:
                g = run_once(t)  # dt ignorowane
            print("T=%+4d dT=%+4d -> G=%3d" % (t, dt, g))
        except Exception as e:
            print("ERR  T=%+4d dT=%+4d : %s" % (t, dt, e))

def sweep_csv(t_vals=None, dt_vals=None):
    """
    Logger CSV dla zewnętrznego dT: drukuje `T,dT,G`.
    Użyteczne do zrzutu do pliku po USB/UART.
    """
    if t_vals is None:  t_vals = range(-60, 61, 20)
    if dt_vals is None: dt_vals = [-20, 0, +20]
    print("T,dT,G")
    for t in t_vals:
        for d in dt_vals:
            try:
                g = run_once_ext(t, d)
                print("%d,%d,%d" % (t, d, g))
            except Exception as e:
                print("%d,%d,ERR" % (t, d))

# ===== Batch helpery: wgrywanie listy (addr, val) i weryfikacja =====
def write_bulk(pairs):
    """pairs = [(addr, val), ...]"""
    for a, v in pairs:
        write_reg(a, v)

def verify_bulk(pairs, raise_on_mismatch=True):
    ok = True
    for a, exp in pairs:
        got = read_reg(a)
        if got != (exp & 0xFF):
            print("VERIFY FAIL @0x%02X: got=0x%02X exp=0x%02X" % (a & 0xFF, got, exp & 0xFF))
            ok = False
            if raise_on_mismatch:
                raise RuntimeError("Verify failed")
    return ok

# ===== Minimalny „interfejs ręczny” przez REPL =====
def repl_help():
    print("cmds: wr a v | rd a | go T | goext T dT | init | start | modes_int | modes_ext | status | wiggle | sweep | csv | help")

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
                a = int(parts[1], 0)
                print("0x%02X" % read_reg(a))
            elif cmd == "go" and len(parts) == 2:
                T = int(parts[1], 0)
                G = run_once(T)
                print("G =", G)
            elif cmd == "goext" and len(parts) == 3:
                T  = int(parts[1], 0)
                dT = int(parts[2], 0)
                G = run_once_ext(T, dT)
                print("G =", G)
            elif cmd == "init":
                pulse_init(); print("ok")
            elif cmd == "start":
                pulse_start(); print("ok")
            elif cmd == "modes_int":
                set_modes_9rules_dtinternal(); print("ok")
            elif cmd == "modes_ext":
                set_modes_9rules_dt_external(); print("ok")
            elif cmd == "status":
                dump_status()
            elif cmd == "wiggle":
                wiggle_addr(); wiggle_ctrl()
            elif cmd == "sweep":
                sweep()
            elif cmd == "csv":
                sweep_csv()
            elif cmd == "help":
                repl_help()
            else:
                print("??? (help)")
        except Exception as e:
            print("ERR:", e)

# ===== Demo na start =====
def demo():
    print("BOOT OK")
    print("ADDR_BASE=%d  WDATA_BASE=%d  RDATA_BASE=%d  CS/WR/RD/RDY=%d/%d/%d/%d" %
          (ADDR_BASE_GP, WDATA_BASE_GP, RDATA_BASE_GP, CS_GP, WR_GP, RD_GP, RDY_GP))
    dump_status()
    try:
        # przykład: T=+20, dT=+5 (obie int8)
        G = run_once_ext(T_val=20, dT_val=5)
        print("G =", G)
    except Exception as e:
        print("ERROR:", e)
    print("DONE")

if __name__ == "__main__":
    # Auto-demo przy starcie; zakomentuj jeśli wolisz tylko REPL
    demo()
    # Odkomentuj, aby wejść w mini-CLI po USB (polecam do ręcznych prób):
    # repl()
