#!/usr/bin/env python3
import json
import sys
from datetime import datetime


def parse_dt(v: str) -> datetime:
    if v.endswith("Z"):
        return datetime.fromisoformat(v.replace("Z", "+00:00"))
    return datetime.fromisoformat(v)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: ortools_solver.py input.json output.json", file=sys.stderr)
        return 2

    input_path, output_path = sys.argv[1], sys.argv[2]
    payload = json.load(open(input_path, "r", encoding="utf-8"))
    project = payload["project"]
    shifts = payload["shiftInstances"]
    students = project["students"]
    templates = {t["id"]: t for t in project["shiftTemplates"]}
    rules = project["rules"]

    try:
        from ortools.sat.python import cp_model
    except Exception as exc:
        out = {
            "status": "ERROR",
            "assignments": [],
            "diagnostic": {
                "message": "OR-Tools import failed.",
                "details": [str(exc), "Install with: pip install ortools"],
            },
        }
        json.dump(out, open(output_path, "w", encoding="utf-8"), indent=2)
        return 0

    if not students or not shifts:
        out = {
            "status": "INFEASIBLE",
            "assignments": [],
            "diagnostic": {
                "message": "Missing students or shifts.",
                "details": ["Need at least one student and one generated shift."],
            },
        }
        json.dump(out, open(output_path, "w", encoding="utf-8"), indent=2)
        return 0

    model = cp_model.CpModel()
    x = {}
    for s_idx, _ in enumerate(students):
        for sh_idx, _ in enumerate(shifts):
            x[(s_idx, sh_idx)] = model.NewBoolVar(f"x_{s_idx}_{sh_idx}")

    # Each student must hit required weighted shift total.
    target = int(rules["numShiftsRequired"])
    overnight_weight = int(rules.get("overnightShiftWeight", 1))
    for s_idx, _ in enumerate(students):
        terms = []
        for sh_idx, sh in enumerate(shifts):
            weight = overnight_weight if sh["isOvernight"] else 1
            terms.append(x[(s_idx, sh_idx)] * weight)
        model.Add(sum(terms) == target)

    # At most one student per shift instance when enabled.
    if rules.get("noDoubleBooking", True):
        for sh_idx, _ in enumerate(shifts):
            model.Add(sum(x[(s_idx, sh_idx)] for s_idx, _ in enumerate(students)) <= 1)

    # Rest and overlap constraints per student.
    min_rest_seconds = int(rules.get("timeOffHours", 0)) * 3600
    parsed_shifts = []
    for sh in shifts:
        parsed_shifts.append((parse_dt(sh["startDateTime"]), parse_dt(sh["endDateTime"]), sh))

    for s_idx, _ in enumerate(students):
        for i in range(len(parsed_shifts)):
            start_i, end_i, _ = parsed_shifts[i]
            for j in range(i + 1, len(parsed_shifts)):
                start_j, end_j, _ = parsed_shifts[j]
                overlap = start_i < end_j and start_j < end_i
                if overlap:
                    model.Add(x[(s_idx, i)] + x[(s_idx, j)] <= 1)
                    continue
                if end_i <= start_j:
                    rest_ok = (start_j - end_i).total_seconds() >= min_rest_seconds
                else:
                    rest_ok = (start_i - end_j).total_seconds() >= min_rest_seconds
                if not rest_ok:
                    model.Add(x[(s_idx, i)] + x[(s_idx, j)] <= 1)

    # Per-template student min/max.
    shifts_by_template = {}
    for idx, sh in enumerate(shifts):
        shifts_by_template.setdefault(sh["templateId"], []).append(idx)

    for s_idx, _ in enumerate(students):
        for template_id, shift_indices in shifts_by_template.items():
            template = templates.get(template_id)
            if not template:
                continue
            expr = sum(x[(s_idx, sh_idx)] for sh_idx in shift_indices)
            min_shifts = template.get("minShifts")
            max_shifts = template.get("maxShifts")
            if min_shifts is not None:
                model.Add(expr >= int(min_shifts))
            if max_shifts is not None:
                model.Add(expr <= int(max_shifts))

    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = float(max(1, int(rules.get("solverTimeLimitSeconds", 20))))
    solver.parameters.num_search_workers = 8

    status = solver.Solve(model)

    if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        assignments = []
        for s_idx, student in enumerate(students):
            for sh_idx, shift in enumerate(shifts):
                if solver.Value(x[(s_idx, sh_idx)]) == 1:
                    assignments.append({
                        "studentId": student["id"],
                        "shiftInstanceId": shift["id"],
                    })
        out = {
            "status": "OPTIMAL" if status == cp_model.OPTIMAL else "FEASIBLE",
            "assignments": assignments,
            "diagnostic": None,
        }
    else:
        total_required = len(students) * target
        weighted_capacity = sum(overnight_weight if sh["isOvernight"] else 1 for sh in shifts)
        details = [
            f"Required weighted assignments: {total_required}",
            f"Weighted shift capacity (if all unique): {weighted_capacity}",
            f"Double booking: {'off' if not rules.get('noDoubleBooking', True) else 'on'}",
            "Check min/max per-template constraints and rest-hour conflicts.",
        ]
        out = {
            "status": "INFEASIBLE",
            "assignments": [],
            "diagnostic": {
                "message": "No feasible schedule exists for the current rules.",
                "details": details,
            },
        }

    json.dump(out, open(output_path, "w", encoding="utf-8"), indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
