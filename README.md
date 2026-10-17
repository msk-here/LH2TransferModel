> **Fork note — CoolProp instead of REFPROP**
>
> This is a fork of [Albert-Gil/LH2TransferModel](https://github.com/Albert-Gil/LH2TransferModel),
> the model published in Gil-Esmendia, Flores & Brouwer, *"Modeling and improving liquid
> hydrogen transfer processes"*, Applied Energy **390** (2025) 125779.
>
> The proprietary REFPROP dependency has been replaced with a drop-in
> `refpropm.m` shim backed by
> [CoolProp](http://www.coolprop.org/), so the model runs **without a REFPROP licence**.
> This fork also includes conservative spray/jet top filling and custom scenarios; see below.
>
> **Requirements:** MATLAB with a configured Python environment (`pyenv`), and CoolProp
> (`py -m pip install CoolProp`).
>
> **Before running:** execute `validate_shim.m`. It runs 42 checks on the property shim
> and must report all passed. A mis-mapped property code produces plausible-looking but
> wrong results.
>
> See [`SHIM_NOTES.md`](SHIM_NOTES.md) for verification details.
>
> Upstream licence (GPL-3.0) is unchanged and applies to this fork.

# LH₂ Transfer Model

This repository contains a set of MATLAB scripts developed to simulate **liquid hydrogen (LH₂) transfer processes** in refueling stations. The model supports the design and analysis of LH₂ operations for **heavy-duty vehicle fueling**, with a focus on minimizing venting and optimizing thermal behavior.

The model and its results are formally presented in the following peer-reviewed publication:

> **Gil, A., Flores, R., Brouwer, J.**  
> *Modeling and improving liquid hydrogen transfer processes*,  
> **Applied Energy**, Volume 390, 2025, 125779.  
> https://doi.org/10.1016/j.apenergy.2025.125779

---

## 📌 Objective

This simulation tool is designed to:
- Simulate LH₂ transfer between cryogenic tanks (e.g., trailer to station, or station to onboard).
- Track **boil-off gas (BOG)** generation and **venting** during transfer.
- Compare driving strategies:  **pressurization** vs. **pump-driven** transfer.
- Evaluate key process parameters including **flow rate**, **inlet temperature**, and **cooling strategies**.

---

## 🧠 Model Description

- The model is a **0D, lumped-parameter thermodynamic model**.
- It performs transient mass and energy balances on both the liquid and vapor phases of LH₂.
- Key features include:
  - Environmental heat ingress through the tank walls
  - Liquid-vapor thermal stratification
  - Phase change and venting dynamics
  - Transfer control logic

### 🔬 Scientific Foundations

This model is built upon and extends the methodology developed by:

> **Petitpas, G., Aceves, S., Morris, J. et al.**  
> *Modeling of liquid hydrogen boil-off in cryogenic pressure vessels*,  
> **International Journal of Hydrogen Energy**, Volume 44, Issue 3, 2019, pp. 1943–1953.  
> https://doi.org/10.1016/j.ijhydene.2018.11.080

The original framework was adapted to simulate dynamic refueling conditions and extended to include pump-driven transfer and top-fill strategies.

### ⚙️ Thermodynamic Properties

- All fluid properties are computed using **NIST's REFPROP** package.
- A valid REFPROP license is required.  
  More info: https://www.nist.gov/srd/refprop

---

## 🧰 Repository Contents

### 🔁 Main Scripts
- `MAIN.m` – Entry point to run simulations.
- `LH2Simulate.m` / `LH2Simulate_Pump.m` – Pressure-based or pump-based transfer.
- `LH2Control.m` / `LH2Control_pump.m` – Control logic for start, stop, and venting.

### 📄 Parameter Files
- Predefined transfer cases (e.g., `TrailerToMain`, `MainToOnboard`) with adjustable inputs.

### 📊 Post-Processing & Utilities
- `plotLH2Data.m` – Visualization of results.
- `Data_extraction.m`, `SaveResultsFunction.m` – Data management tools.
- `CreateXLSTXT.m`, `UpdateXLSLog.m` – Optional Excel log generation.

### 🧩 Helper Functions
- Thermophysical: `vaporpressure.m`, `gasFlow.m`, `cylVToH.m`
- UI: `waitbartime.m`

---

## ▶️ How to Run

1. Clone the repository:
   ```bash
   git clone https://github.com/Albert-Gil/LH2TransferModel.git
   cd LH2TransferModel
   ```

2. Install and configure **NIST REFPROP**.

3. Open MATLAB, set the folder as working directory, and run:
   ```matlab
   MAIN
   ```

You can modify parameter files to define your desired scenario.

---

## 📈 Outputs

- Time series for:
  - Liquid and vapor temperature
  - Tank pressure
  - Boil-off rate and vented mass
- Exported results and plots for further analysis

---

## 📜 References

If you use this model, please cite both:

**1.**  
> **Gil, A., Flores, R., Brouwer, J.**  
> *Modeling and improving liquid hydrogen transfer processes*,  
> **Applied Energy**, Volume 390, 2025, 125779.  
> https://doi.org/10.1016/j.apenergy.2025.125779

**2.**  
> **Petitpas, G. et al.**  
> *Modeling of liquid hydrogen boil-off in cryogenic pressure vessels*,  
> International Journal of Hydrogen Energy, 44(3), 2019, pp. 1943–1953.  
> https://doi.org/10.1016/j.ijhydene.2018.11.080

---

## ⚠️ Notes

- This repository is intended for academic and research use.
- **REFPROP license required.**
- This repository **may not be regularly maintained or updated.**
- No warranty is provided. Use at your own risk.

---

## 👤 Author

**Albert Gil**  
PhD Researcher, University of California, Irvine  
https://www.linkedin.com/in/albertgilesmendia/

---

## 📄 License

This project is released under the **GNU General Public License v3.0**.  
See the `LICENSE` file or visit: https://www.gnu.org/licenses/gpl-3.0.html

---

## 📬 Contact

For questions or collaboration opportunities, feel free to open an issue or reach out.


## Custom scenarios and unified inlet control

Select `Case=7` (pressure-driven, `LH2Simulate`) or `Case=8` (pump-driven,
`LH2Simulate_Pump`) in `MAIN.m`, then run `MAIN`. Cases 1–6 retain their existing
parameter sets and solver routing. Unsupported case numbers raise an error.

Edit `Parameters_Custom_PressDiff.m` or `Parameters_Custom_Pump.m`. Each file
contains an independent `C` configuration with SI units in comments: tank volumes
and radii, initial pressures/temperatures/fill, line dimensions, vent thresholds,
heat ingress and duration. The pump file also exposes fast/slow mass flow,
efficiency and heat-gain settings. The existing geometry is a horizontal cylindrical
supply tank and vertical cylindrical receiving tank; these files do not introduce
other tank shapes.

Custom files inherit material properties, grids and numerical controls from Case 2
or 3, then `initialize_custom_parameters` applies their primary inputs and rebuilds
areas, cylinder length/height, phase densities and masses, ullage, film temperatures
and pipe friction. Empty vapor-temperature settings use the existing pressure
correlation. Empty heat ingress/wall mass settings use existing volume correlations;
explicit values override them. Empty `C.tFinal` uses the existing transfer-duration
estimate. Set a positive value to specify the transfer duration. `HydrogenTransfer=0`
retains stationary behavior and a default duration of 3600 s.

The supply `initialfillfraction` retains the legacy convention: it estimates **total
mass** as fraction × volume × reference liquid density, rather than prescribing an
exact liquid volume fraction. Receiving `pct_hL20` is the liquid height fraction.
Change primary inputs in `C`, not calculated masses or geometry after initialization.
For extreme geometries/pressures the inherited empirical correlations still need
scientific validation; custom configuration is not a new validity range for them.

`TopBottomRatio` is the only inlet activation control:

- `0`: original bottom-fill equations; `TopfillMode` is ignored.
- `1`: all transfer flow enters the selected top-fill model.
- Between `0` and `1`: top flow is `r*Jtr`, bottom flow is `(1-r)*Jtr`.
- With a positive ratio, `TopfillMode` must be exactly `'spray'` or `'jet'`.

There is no independent `Topfill` input. Ratios must be finite real numeric scalars
in `[0,1]`. Internally `TF_r` and `TF_mode` hold the settings; `TF_enabled` is derived
from `TF_r>0`. The top source model retains its existing mass/enthalpy ports, signed
phase change, and vapor-to-liquid heat treatment. Total upstream flow and pump heat
are retained once, with no changes to the governing equations or numerical tolerances.

Example: edit `Parameters_Custom_Pump.m` to set `C.VTotal2=12` (m³) and
`C.tFinal=120` (s). In the **options section of MAIN.m**, set:

```matlab
Case=8;
HydrogenTransfer=1;
TopBottomRatio=0.3;
TopfillMode='spray';
odesolver=1;
```

Then run `MAIN`. It clears the workspace, so setting these variables only at the
command prompt will not override its options. Use Case 7 and its dedicated file for
a pressure-driven hybrid run. Extraction, plotting, MAT saving and XLS/TXT export
follow the same workflow. Custom names and descriptive metadata identify each case.
With `UpdateLog=1`, Cases 7/8 (and blowdown Case 6) write separate per-run XLS/TXT
reports in `LogPath`; they do not append to either legacy `ResultsLog.xlsx` sheet.
Existing Cases 1–5 retain the legacy log layout, with hybrid fill labeled explicitly.

### Verification

Run these from the repository folder with MATLAB and its CoolProp Python bridge:

```matlab
validate_shim
run_scenario_checks                 % validation, custom runs and full output workflow
run_topfill_checks                  % module conservation + 20 host runs of 120 s
% Optional exact comparison against a complete pre-change working-copy snapshot:
run_scenario_checks('C:/path/to/baseline', 2)
```

The snapshot must contain the old hosts and parameter scripts, including any local
edits that should be preserved. Baseline checks compare all six parameter structures,
all saved numeric state bits and time grids without interpolation. The default new
scenario smoke tests simulate 2 s; pass a longer second argument for longer runs.
`run_topfill_checks` retains its existing mass/energy source acceptance tolerances;
its host integrated-mass residual remains a diagnostic without an invented tolerance.
See `VERIFICATION_CUSTOM_SCENARIOS.md` for the executed checks and limitations.
