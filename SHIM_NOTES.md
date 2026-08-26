# refpropm → CoolProp shim: verified findings

Everything below was checked against the actual upstream source
(`Albert-Gil/LH2TransferModel`, cloned fresh), against NIST's own
`refpropm.m` (`usnistgov/REFPROP-wrappers`, `wrappers/MATLAB/legacy/`), and
against CoolProp numerically. Where something is inference rather than
verification it says so explicitly.

---

## 1. Corrections to the handoff

### 1.1 Viscosity is Pa·s, **not** µPa·s — this one matters most

The handoff says `'V'` is µPa·s and that the shim needs a 1e6 factor.
That is wrong, and applying it would inflate every Rayleigh number by 1e6.

Three independent confirmations:

1. NIST `refpropm.m` header: `V   Dynamic viscosity [Pa*s]`.
2. NIST `refpropm.m` body, `case 'v'`: `varargout(i) = {eta*1e-6};` —
   REFPROP's DLL returns µPa·s and the wrapper converts to Pa·s.
3. The repo's own REFPROP-derived constants, in every `Parameters_*.m`:
   ```
   LH2Model.mu_L = 13.54e-6;   % [Pa*s]   CoolProp @NBP: 1.3496e-5
   LH2Model.mu_v = 0.98e-6;    % [Pa*s]   CoolProp @NBP: 9.9013e-7
   ```
   These are the defaults that the `refpropm('V',...)` calls overwrite at
   runtime, so both must be in the same units.

CoolProp's `viscosity` is already Pa·s → **no conversion**.
`validate_shim.m` §2 and §3a both fail loudly if this is ever "fixed".

The kPa pressure trap in the handoff **is** correct and is handled
(`×1000` on input, `÷1000` on output).

### 1.2 Not every call uses `'PARAHYD'`

The handoff says the fluid string is `'PARAHYD'` in every call. There is
exactly one exception, `LH2Simulate_Pump.m:666`:

```matlab
str_L     = refpropm('S','T',TL1(P.nL1),'P',pv1/1000,'PARAHYD');
htr_L     = refpropm('H','T',TL1(P.nL1),'P',pv1/1000,'PARAHYD');
Pumphisen = refpropm('H','P',pv2/1000,'S',str_L,'hydrogen');   % <-- normal H2
PumpPisen = Jtr0*(Pumphisen - htr_L);
```

An entropy computed on parahydrogen is fed into a **normal hydrogen**
flash, and the resulting enthalpy is differenced against a parahydrogen
enthalpy. This is an upstream bug, not a shim concern, and the shim
reproduces it faithfully (`'hydrogen'` → CoolProp `Hydrogen`).

Magnitude, at TL1 = 21 K, pv1 = 6 bar, pv2 = 3 bar:

| quantity | value |
|---|---|
| Δh as written (`hydrogen`) | −4231.24 J/kg |
| Δh if consistent (`parahydrogen`) | −4252.90 J/kg |
| ΔP/ρ, the paper's eq. (1) | −4245.61 J/kg |

≈0.5 % on the pump enthalpy term, which is itself small. **Not** a
showstopper — but do not "fix" it before you have a baseline, or you
will not be comparing like with like.

*Caveat, stated as a guess:* CoolProp references both `ParaHydrogen` and
`Hydrogen` to h = s = 0 at their own normal boiling points, so the two
scales are compatible enough for the difference above to be meaningful.
I could not verify REFPROP 10's reference state for these fluids without
a licence. If REFPROP used a different pair of reference states, this
term would differ more.

### 1.3 The Scenario B inconsistency does **not** fire in this repo

The handoff warns that Scenario B initialises gH2 at 25 K with tank
pressures of 5 and 6 bar, which is subcooled liquid. The physics is
right — but the code never uses 25 K.

`Parameters_MainToOnboard_Pump.m:66` and `:76` compute the initial vapour
temperature from a saturation correlation instead:

```matlab
LH2Model.Tv10 = 0.1 + ( ...polynomial in psi... );  % Tsat(p) fitted from REFPROP
```

Evaluated:

| p [bar] | Tsat [K] | code's Tv0 [K] | superheat | ρ_v [kg/m³] | phase |
|---|---|---|---|---|---|
| 3 | 24.566 | 24.662 | +0.096 | 3.645 | gas |
| 5 | 27.112 | 27.224 | +0.112 | 6.075 | gas |
| 6 | 28.119 | 28.226 | +0.107 | 7.389 | gas |

Always ~0.1 K superheated, by construction. For contrast, the paper's
stated 25 K at 6 bar would give **65.1 kg/m³** — liquid, 8.8× the vapour
density, exactly the failure mode from your sibling repo.

So: the paper's Table (Scenario B) and the shipped parameter file
disagree, and the parameter file is the self-consistent one.
`validate_shim.m` §7 asserts this so it cannot silently regress.

### 1.4 `q` and `Q` are the *same code*

`refpropm.m:328` is `propReq = lower(varargin{1});` — the request is
lowercased before dispatch, so there is no lowercase/uppercase
distinction at all. Both reach `case 'q'`:

```matlab
case 'q'
    if ((q <= 0) || (q >= 1))
        varargout(i) = {q};              % raw REFPROP flag passthrough
    else
        varargout(i) = {q*wmol*1e-3/molw};  % mole -> mass basis
    end
```

For a pure fluid `wmol == molw`, so mass quality ≡ mole quality. Outside
the dome REFPROP's flags (−998 subcooled, 998 superheated, 999
supercritical) pass straight through.

Every consumer in the model tests only `quality > 0 && quality < 1`
(`LH2Simulate_Pump.m` lines 200, 294, 505, 1133; `vaporpressure.m:51`),
so the flag value itself is never used. The shim emits REFPROP-style
flags anyway, because CoolProp returns `10000.0` for *both* subcooled
liquid and superheated vapour, which makes debug output useless.

### 1.5 Other codes — confirmed, no change needed

| code | meaning | source |
|---|---|---|
| `Y` | heat of vaporisation [J/kg] | NIST header + `case 'y'` does a SATT flash at T and returns `(hv-hl)/molw`; **the second input is ignored** |
| `^` | Prandtl number [−] | NIST header; `case '^'` computes `eta*cp/tcx/molw/1e6` ≡ µ·c_p/k |
| `S` | entropy [J/(kg·K)] | NIST header; call site is the pump isentropic work |
| `B` | volumetric expansivity [1/K] | NIST header; verified β·T → 1 in the dilute limit |
| `O` / `C` | cv / cp | verified cp > cv everywhere, and cp/cv → 5/3 at 40 K (matches the model's own `gamma_ = 5/3`) |

### 1.6 Call inventory

204 `refpropm` occurrences, of which **18 are commented out**, leaving
**186 active**. The handoff's per-code frequencies count the commented
ones; the set of 15 codes is identical either way.

All 186 active calls are 6-argument, single-output — confirming "no
multi-output call sites". The shim supports multi-output anyway (for the
LLNL fork), via the standard `[a,b] = refpropm('AB',...)` form.

Input pairs used: `(T,P) (T,Q) (T,D) (D,U) (P,U) (P,H) (P,S) (P,Q)`.
All eight are natively supported by `PropsSI` — no fallbacks needed.

---

## 2. Things that will bite when you run `MAIN.m`

1. **`MAIN.m:16` defaults to `Case=2`**, which is Trailer→Main by pressure
   difference and runs `LH2Simulate.m`. For paper Fig. 4 you need
   **`Case=5`** (Main→On-board, pump), which runs `LH2Simulate_Pump.m`.
2. **Hardcoded absolute Windows paths** at lines 34, 38, 42, 46 point at
   `C:\Users\alber\...`. With `SavePlots=1`, `SaveResults=1`,
   `UpdateLog=1` these will fail. Repoint them or set the flags to 0.
3. **`LH2Model.T_c = 32.938`** (`Parameters_*.m:33`) is hardcoded and sits
   **1.45e-4 K above** the true Tcrit (32.937855…). It only feeds
   `Ts0 = T_c*(p/p_c)^(1/λ)`, and for p ≤ 12 bar that gives Ts ≤ 32.49 K,
   so it does not throw in this scenario — but it is exactly the trap you
   described. The shim supports `refpropm('T','C',0,' ',0,'PARAHYD')` if
   you want to query it at runtime instead.
4. **Silent `try`/`catch` fallbacks already exist upstream** at
   `LH2Simulate_Pump.m:184–197, 254–267, 659–665, 1120–1131`. These
   swallow flash failures and substitute truncated inputs or saturated
   values. CoolProp and REFPROP do not throw under identical conditions,
   so *which branch runs may differ*. If results drift, instrument these
   before suspecting the shim.

---

## 3. The Fig. 4 validation targets — read before trusting them

Paper §3.3.1: ~4.5 min, 87.6 kg transferred, 6.2 kg vented, 7.1 % relative
venting, 0→100 % SOC of a 1700 L tank (10 %→90 % of volume = 1360 L).

**87.6 kg into 1360 L implies a mean added density of 64.4 kg/m³.** That
is physically fine (para-H2 at ~26 K, 11 bar), so Fig. 4 is a usable
target.

But the paper's other reported masses are **not** physically possible for
a 1700 L receiving tank:

| figure | claim | required mean density | max possible (triple pt.) |
|---|---|---|---|
| Fig. 4 | 87.6 kg | 64.4 kg/m³ | 76.98 kg/m³ — OK |
| Fig. 5 | 144 kg ("fast") | 105.9 kg/m³ | **impossible** |
| Fig. 5 | 150 kg ("slow") | 110.3 kg/m³ | **impossible** |
| Fig. 12 | up to ~247 kg | 181.6 kg/m³ | **impossible** |

Both Fig. 5 and Fig. 12 are described in the text as Scenario B with the
1700 L receiving tank. They cannot be. Something about the configuration
behind those figures differs from what is written.

**Practical consequence:** validate against Fig. 4 only, and if Fig. 5 or
Fig. 12 do not reproduce, that is not evidence your shim is broken.

### Parameter deltas: shipped file vs paper Scenario B table

| quantity | paper Table | `Parameters_MainToOnboard_Pump.m` |
|---|---|---|
| Tank 2 initial pressure | 5 bar | **3 bar** (line 75) |
| Tank 1 initial fill | 65 % | **70 %** (line 63) |
| Tank 2 initial LH2 temp | 25 K | **22 K** (line 77) |
| Tank 2 initial wall temp | 25 K | **35 K** (line 78) |
| Initial gH2 temp (both) | 25 K | **Tsat(p) + 0.1 K** (lines 66, 76) |
| Tank 1 initial pressure | 6 bar | 6 bar ✓ |
| MWP / vent-down | 12 / 11 bar | 12 / 11 bar ✓ (lines 150–151) |
| Flow setpoint | 30 kg/min | 30 kg/min ✓ (line 139) |
| SOC window | 0→100 % | 10 %→90 % ✓ (lines 79, 154) |

The MWP, vent hysteresis, flow setpoint and SOC window all match Fig. 4
exactly, and `PumpMassTransferSlow = 15 kg/min` matches the paper's "50 %
of setpoint" initial stage. So this **is** the Fig. 4 configuration —
but you will likely need `p20 = 5*barToPa` to match the reported venting,
since venting is strongly dependent on tank 2 initial pressure (paper
§3.4.1). Change it as its own commit so the effect is isolated.

---

## 4. Performance

Bridge cost ≈0.154 ms/call × ~85 calls per RHS evaluation ≈ 13 ms per RHS.
With a few thousand RHS evaluations that is ~1–2 minutes of bridge
overhead — tolerable. Leave `CACHE_ENABLED = false` until you have a
baseline run committed; then flip it and confirm the four target numbers
are bit-identical before keeping it.

---

## 5. Portability to the LLNL fork

The shim is self-contained: one file, no repo dependencies, no globals
beyond an optional cache. It implements the 15 codes used here plus
`A K M Z` and the `C`/`R`/`M` fixed-point forms. Since LLNL uses a strict
subset (all but `S` and `Y`), it should drop in unchanged.

Unsupported codes raise `refpropm:unsupportedProperty` rather than
returning anything — add new codes deliberately, after checking both
`refpropm.m` and the call site.
