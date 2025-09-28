import json
import re
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional

BASE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = BASE_DIR / "shift_templates"
DAY_NAME_TO_INDEX = {
    "Monday": 0,
    "Tuesday": 1,
    "Wednesday": 2,
    "Thursday": 3,
    "Friday": 4,
    "Saturday": 5,
    "Sunday": 6,
}
INDEX_TO_DAY_NAME = {v: k for k, v in DAY_NAME_TO_INDEX.items()}
TIME_FORMAT = "%H:%M"


def ensure_templates_dir() -> None:
    """Ensure the directory for storing shift templates exists."""
    TEMPLATES_DIR.mkdir(parents=True, exist_ok=True)


def _slugify(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    value = value.strip("-")
    return value or "template"


def list_templates() -> List[Dict[str, Any]]:
    """Return metadata for all saved templates."""
    ensure_templates_dir()
    templates = []
    for path in sorted(TEMPLATES_DIR.glob("*.json")):
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        templates.append({
            "slug": path.stem,
            "template_name": data.get("template_name", path.stem),
            "institution": data.get("institution", ""),
            "path": str(path),
        })
    return templates


def load_template(slug: str) -> Dict[str, Any]:
    ensure_templates_dir()
    path = TEMPLATES_DIR / f"{slug}.json"
    if not path.exists():
        raise FileNotFoundError(f"Template '{slug}' not found")
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_template(
    template_name: str,
    institution: str,
    week_slots: List[Dict[str, Any]],
    slug: Optional[str] = None,
) -> str:
    """Persist a shift template and return its slug."""
    ensure_templates_dir()
    slug = slug or _slugify(template_name)
    data = {
        "template_name": template_name,
        "institution": institution,
        "week_slots": week_slots,
    }
    path = TEMPLATES_DIR / f"{slug}.json"
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    return slug


def _parse_time(value: str) -> time:
    return datetime.strptime(value, TIME_FORMAT).time()


def build_shifts_from_template(
    template: Dict[str, Any],
    start_date: date,
    end_date: date,
) -> List[Dict[str, Any]]:
    """Expand a weekly template into dated shifts between start_date and end_date."""
    week_slots = template.get("week_slots", [])
    slots_by_index: Dict[int, List[Dict[str, Any]]] = {i: [] for i in range(7)}
    for slot in week_slots:
        day_name = slot.get("day_of_week")
        if day_name not in DAY_NAME_TO_INDEX:
            continue
        slots_by_index[DAY_NAME_TO_INDEX[day_name]].append(slot)

    all_shifts: List[Dict[str, Any]] = []
    current_day = start_date
    while current_day <= end_date:
        weekday_index = current_day.weekday()
        for slot in slots_by_index.get(weekday_index, []):
            start_time = _parse_time(slot["start_time"])
            start_dt = datetime.combine(current_day, start_time)
            duration_hours = float(slot.get("duration_hours", 10))
            block_hours = float(slot.get("block_hours", duration_hours))
            end_dt = start_dt + timedelta(hours=duration_hours)
            block_end = start_dt + timedelta(hours=block_hours)
            name = slot["name"]
            shift_id = f"{name}_{start_dt:%Y%m%d%H%M}"

            all_shifts.append({
                "id": shift_id,
                "start": start_dt,
                "end": end_dt,
                "block_end": block_end,
                "name": name,
                "category": slot.get("category", ""),
                "site": slot.get("site", ""),
                "is_overnight": bool(slot.get("is_overnight", False)),
            })
        current_day += timedelta(days=1)
    return all_shifts


def save_shifts_json(filename: str, shifts: List[Dict[str, Any]]) -> None:
    """Persist expanded shifts to disk (datetimes serialized to ISO strings)."""
    def serialize_shift(s: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "id": s["id"],
            "start": s["start"].isoformat(),
            "end": s["end"].isoformat(),
            "block_end": s["block_end"].isoformat(),
            "name": s["name"],
            "category": s.get("category", ""),
            "site": s.get("site", ""),
            "is_overnight": s.get("is_overnight", False),
        }

    with open(filename, "w", encoding="utf-8") as f:
        json.dump([serialize_shift(s) for s in shifts], f, indent=2)
