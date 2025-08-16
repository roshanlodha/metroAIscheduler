import json
from datetime import date, datetime, timedelta

# Rotation window: August 8–29, 2025 (skip Wednesdays)
start_date = date(2025, 8, 6)
end_date   = date(2025, 8, 29)
num_days   = (end_date - start_date).days + 1
all_dates = [
    start_date + timedelta(days=i)
    for i in range(num_days)
    #if (start_date + timedelta(days=i)).weekday() != 2
]

# Shift definitions: key → start hour (24h)
shift_defs = {
    # Regular shifts
    'T1AM': 7,      # 7a-3p T1
    'T2A_wknd': 12,  # 12p-9p T2A weekend
    'T2A_wkday': 10, # 10a-6p T2A weekdays
    'T1PM': 14,    # 2p-11p T1
    'T2B': 17,    # 5p-1a T2B
    'T3': 15,    # 3-11 T3

    # Trauma
    'Red': 12,   # 12pm-8p RED

    # Overnight shifts
    'Night': 23,
    
    # Community Shifts
    'Needham': 12,
}

# Categories by name
regular         = {'T1AM', 'T2A_wknd', 'T2A_wkday', 'T1PM', 'T2B', 'T3'}
trauma_names    = {'Red'}
overnight_names = {'Night'}
community_names = {'Needham'}

# ------------------------
# 2. Build the all_shifts
# ------------------------

all_shifts = []
for current_date in all_dates:
    day = current_date.weekday()  # Mon=0 ... Sun=6

    for name, hour in shift_defs.items():
        is_overnight = name in overnight_names

        # Enforce weekend/weekday constraints
        if name == 'T2A_wknd' and day not in (5, 6):   # Sat/Sun only
            continue
        if name == 'T2A_wkday':
            # Weekdays only (Mon–Fri), but skip Tue/Wed mornings
            if day not in (0, 1, 2, 3, 4):
                continue
            if day in (1, 2):  # Tue or Wed
                continue

        # Skip Tuesday and Wednesday morning shifts
        if name == 'T1AM' and day in (1, 2):
            continue

        # Keep your original overnight restriction
        if is_overnight and day in (0, 1):  # No overnight shifts on Monday or Tuesday
            continue

        start_dt = datetime(
            current_date.year,
            current_date.month,
            current_date.day,
            hour, 0
        )

        # Durations
        if name == 'T2A_wknd' or name == 'T1PM':
            duration = timedelta(hours=9)
        else:
            duration = timedelta(hours=8)

        # Categories (updated sets)
        if is_overnight:
            category = 'overnight'
        elif name in trauma_names:
            category = 'trauma'
        elif name in community_names:
            category = 'community'
        elif name in regular:
            category = 'regular'
        else:
            category = 'other'

        # Simplified site (no CCF/Metro legacy)
        site = 'Community' if name in community_names else 'Main'

        all_shifts.append({
            'id':           f"{name}_{start_dt:%Y%m%d%H}",
            'start':        start_dt,
            'end':          start_dt + duration,
            'name':         name,
            'category':     category,
            'site':         site,
            'is_overnight': is_overnight,
        })

def save_shifts_json(filename, shifts):
    # Convert datetime objects to ISO strings for JSON serialization
    def serialize_shift(s):
        return {
            'id': s['id'],
            'start': s['start'].isoformat(),
            'end': s['end'].isoformat(),
            'name': s['name'],
            'category': s['category'],
            'site': s['site'],
            'is_overnight': s['is_overnight'],
        }
    with open(filename, 'w') as f:
        json.dump([serialize_shift(s) for s in shifts], f, indent=2)

save_shifts_json("bidmc_shifts.json", all_shifts)