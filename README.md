# EM Shift Scheduler

EM Shift Scheduler is a macOS desktop app that builds student schedules for EM Acting Internships with constraint programming. A sample project is available at `templates/metroAI.json`.

## Xcode Structure

- `EMShiftScheduler.xcodeproj` (native macOS app project)
- Target: `EMShiftScheduler`
- Deployment target: `macOS 26.0`
- Swift sources: `Sources/EMShiftSchedulerApp/**`
- Bundled solver script resource: `Sources/EMShiftSchedulerApp/Resources/ortools_solver.py`
- UI layout: single main workspace (shift templates on the left, students + scheduling controls on the right)

Open in Xcode:

```bash
open EMShiftScheduler.xcodeproj
```

Run with `Cmd+R`.

## One-Command .app Build

Use:

```bash
./build.sh
```

This script:

1. Builds `EM Shift Scheduler.app` in Release mode via `xcodebuild`.
2. Extracts bundled CPython runtime from:
   - `cpython-3.12.12+20260127-aarch64-apple-darwin-install_only.tar`
3. Copies Python packages (including OR-Tools) from:
   - `env/lib/python3.12/site-packages`
4. Embeds both into:
   - `EM Shift Scheduler.app/Contents/Resources/python`
5. Outputs distributable app at:
   - `dist/EM Shift Scheduler.app`

No Python or pip installation is required on end-user machines.

## Requirements to Build

- Latest stable Xcode (tested with Xcode 26.2)
- These files present in repo root:
  - `cpython-3.12.12+20260127-aarch64-apple-darwin-install_only.tar`
  - `env/lib/python3.12/site-packages` (with `ortools`)

## Tests (Swift Package)

```bash
swift test
```

Coverage includes:

- shift instance expansion
- overlap/rest conflict detection
- JSON encode/decode round-trip
- deterministic solver fixture

## Sample Data

- Example project JSON: `templates/metroAI.json`
- Shift template bundles are stored in `templateLibrary`; each bundle contains multiple shifts.
- The app includes a Metro preset derived from `solve.py` for:
  - `Trauma`, `Overnight`, `Acute`, `West`, `Community`, `MLF`
  - CCF shifts are intentionally excluded.

## Modeling Decisions

- Overnight duration:
  - If `lengthHours` is set, that exact duration is used in solver/UI/CSV/ICS.
  - If `lengthHours` is nil and `isOvernight=true`, duration defaults to 10 hours.
- Total-shift counting:
  - Per student: exact equality `sum(assigned shifts) == numShiftsRequired - max(0, overnightRequired - 1)`.
  - `overnightRequired` is derived from `minShifts` on the `Overnight` shift type.
  - Overnight assignments are constrained to one contiguous block per student.
- Rest constraints:
  - Overlapping shifts cannot both be assigned to the same student.
  - Non-overlapping shifts require gap `>= timeOffHours`.
