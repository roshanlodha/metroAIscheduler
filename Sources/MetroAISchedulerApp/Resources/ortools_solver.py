#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


def parse_dt(v: str) -> datetime:
    if v.endswith("Z"):
        return datetime.fromisoformat(v.replace("Z", "+00:00"))
    dt = datetime.fromisoformat(v)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=ZoneInfo("UTC"))
    return dt


def conference_overlap(shift_start: datetime, shift_end: datetime, rules: dict, local_tz: ZoneInfo) -> bool:
    conference_day = int(rules.get("conferenceDay", 4))
    conference_start = rules.get("conferenceStartTime", {"hour": 8, "minute": 0})
    conference_end = rules.get("conferenceEndTime", {"hour": 12, "minute": 0})
    start_hour = int(conference_start.get("hour", 8))
    start_minute = int(conference_start.get("minute", 0))
    end_hour = int(conference_end.get("hour", 12))
    end_minute = int(conference_end.get("minute", 0))

    local_shift_start = shift_start.astimezone(local_tz)
    local_shift_end = shift_end.astimezone(local_tz)

    day = local_shift_start.date()
    end_day = local_shift_end.date()

    while day <= end_day:
        weekday = ((day.weekday() + 1) % 7) + 1  # python monday=0 -> swift sunday=1
        if weekday == conference_day:
            conf_start = datetime(day.year, day.month, day.day, start_hour, start_minute, tzinfo=local_tz)
            conf_end = datetime(day.year, day.month, day.day, end_hour, end_minute, tzinfo=local_tz)
            if conf_end <= conf_start:
                conf_end = conf_end + timedelta(days=1)
            if local_shift_start < conf_end and conf_start < local_shift_end:
                return True
        day += timedelta(days=1)

    return False


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
    shift_types = {t["id"]: t for t in project.get("shiftTypes", [])}
    rules = project["rules"]
    timezone_name = rules.get("timezone", "UTC")
    try:
        local_tz = ZoneInfo(timezone_name)
    except Exception:
        local_tz = ZoneInfo("UTC")

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

    overnight_type_ids = {type_id for type_id, t in shift_types.items() if t.get("name", "").strip().lower() == "overnight"}
    overnight_required = 0
    for t in shift_types.values():
        if t.get("name", "").strip().lower() == "overnight":
            overnight_required = max(0, int(t.get("minShifts") or 0))
            break

    overnight_shift_indices = []
    overnight_before_conference_indices = []
    conference_day = int(rules.get("conferenceDay", 4))
    day_before_conference = 7 if conference_day == 1 else conference_day - 1
    for idx, sh in enumerate(shifts):
        template = templates.get(sh["templateId"], {})
        template_type_id = template.get("shiftTypeId")
        # Overnight block semantics are driven by the dedicated Overnight shift type.
        is_overnight_shift = template_type_id in overnight_type_ids
        if is_overnight_shift:
            overnight_shift_indices.append(idx)
            shift_start = parse_dt(sh["startDateTime"]).astimezone(local_tz)
            shift_weekday = ((shift_start.weekday() + 1) % 7) + 1
            if shift_weekday == day_before_conference:
                overnight_before_conference_indices.append(idx)

    # Conference window is a hard blackout interval for all students.
    conference_blocked_shift_indices = []
    for idx, sh in enumerate(shifts):
        start_dt = parse_dt(sh["startDateTime"])
        end_dt = parse_dt(sh["endDateTime"])
        if conference_overlap(start_dt, end_dt, rules, local_tz):
            conference_blocked_shift_indices.append(idx)

    # Each student must hit required shift count, collapsing an overnight block to one unit.
    user_target = int(rules["numShiftsRequired"])
    target = max(0, user_target - max(0, overnight_required - 1))
    for s_idx, _ in enumerate(students):
        terms = []
        for sh_idx, _ in enumerate(shifts):
            terms.append(x[(s_idx, sh_idx)])
        model.Add(sum(terms) == target)

    # Overnight requirement is derived from Overnight shift type minShifts.
    if overnight_required > 0:
        for s_idx, _ in enumerate(students):
            model.Add(sum(x[(s_idx, sh_idx)] for sh_idx in overnight_shift_indices) == overnight_required)

    # Overnight shifts for each student must be a single contiguous block.
    if overnight_required > 1:
        overnight_ordered = sorted(
            overnight_shift_indices,
            key=lambda idx: parse_dt(shifts[idx]["startDateTime"]),
        )
        valid_windows = []
        window_spans = []
        for start in range(0, len(overnight_ordered) - overnight_required + 1):
            window = overnight_ordered[start:start + overnight_required]
            starts = [parse_dt(shifts[idx]["startDateTime"]) for idx in window]
            consecutive = True
            for i in range(1, len(starts)):
                if (starts[i] - starts[i - 1]).total_seconds() != 86400:
                    consecutive = False
                    break
            if consecutive:
                valid_windows.append(window)
                window_spans.append((parse_dt(shifts[window[0]]["startDateTime"]), parse_dt(shifts[window[-1]]["endDateTime"])))

        if not valid_windows:
            out = {
                "status": "INFEASIBLE",
                "assignments": [],
                "diagnostic": {
                    "message": "No feasible overnight block exists in the current window.",
                    "details": [
                        f"Required overnight shifts/student: {overnight_required}",
                        "No contiguous overnight run is available from shift offerings and dates.",
                    ],
                },
            }
            json.dump(out, open(output_path, "w", encoding="utf-8"), indent=2)
            return 0

        for s_idx, _ in enumerate(students):
            start_vars = []
            for w_idx, _ in enumerate(valid_windows):
                start_vars.append(model.NewBoolVar(f"overnight_block_{s_idx}_{w_idx}"))

            model.Add(sum(start_vars) == 1)

            for sh_idx in overnight_ordered:
                covers = [start_vars[w_idx] for w_idx, window in enumerate(valid_windows) if sh_idx in window]
                if covers:
                    model.Add(x[(s_idx, sh_idx)] == sum(covers))
                else:
                    model.Add(x[(s_idx, sh_idx)] == 0)

            # If a block window is chosen, no other shift may overlap its full span.
            for w_idx, _ in enumerate(valid_windows):
                block_var = start_vars[w_idx]
                block_start, block_end = window_spans[w_idx]
                for sh_idx, sh in enumerate(shifts):
                    if sh_idx in valid_windows[w_idx]:
                        continue
                    sh_start = parse_dt(sh["startDateTime"])
                    sh_end = parse_dt(sh["endDateTime"])
                    if sh_start < block_end and block_start < sh_end:
                        model.Add(x[(s_idx, sh_idx)] + block_var <= 1)

    # At most one student per shift instance when enabled.
    if rules.get("noDoubleBooking", True):
        for sh_idx, _ in enumerate(shifts):
            model.Add(sum(x[(s_idx, sh_idx)] for s_idx, _ in enumerate(students)) <= 1)

    # No assignments may overlap conference window.
    for sh_idx in conference_blocked_shift_indices:
        for s_idx, _ in enumerate(students):
            model.Add(x[(s_idx, sh_idx)] == 0)

    # Overnight starts on the day before conference are disallowed.
    for sh_idx in overnight_before_conference_indices:
        for s_idx, _ in enumerate(students):
            model.Add(x[(s_idx, sh_idx)] == 0)

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

    # Per-shift-type student min/max.
    shifts_by_template = {}
    for idx, sh in enumerate(shifts):
        shifts_by_template.setdefault(sh["templateId"], []).append(idx)

    shifts_by_type = {}
    for template_id, shift_indices in shifts_by_template.items():
        template = templates.get(template_id)
        if not template:
            continue
        type_id = template.get("shiftTypeId")
        if not type_id:
            continue
        shifts_by_type.setdefault(type_id, []).extend(shift_indices)

    for s_idx, _ in enumerate(students):
        for type_id, shift_indices in shifts_by_type.items():
            shift_type = shift_types.get(type_id)
            if not shift_type:
                continue
            expr = sum(x[(s_idx, sh_idx)] for sh_idx in shift_indices)
            min_shifts = shift_type.get("minShifts")
            max_shifts = shift_type.get("maxShifts")
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
        total_capacity = len(shifts)
        details = [
            f"User requested shifts/student: {user_target}",
            f"Required overnight shifts/student: {overnight_required}",
            f"Internal target assignments/student: {target}",
            f"Required assignments: {total_required}",
            f"Shift capacity (if all unique): {total_capacity}",
            f"Double booking: {'off' if not rules.get('noDoubleBooking', True) else 'on'}",
            "Check min/max per-shift-type constraints and rest-hour conflicts.",
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
