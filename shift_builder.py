import json
from datetime import date, datetime, timedelta

# Rotation window: July 1–25, 2025 (skip Wednesdays)
start_date = date(2025, 7, 1)
end_date   = date(2025, 7, 25)
num_days   = (end_date - start_date).days + 1
all_dates = [
    start_date + timedelta(days=i)
    for i in range(num_days)
    #if (start_date + timedelta(days=i)).weekday() != 2
]

# Shift definitions: key → start hour (24h)
shift_defs = {
    # Metro shifts
    'West':        7,
    'Acute':            7,
    'Trauma':       14,

    # CCF shifts
    'E12':           7,
    'E18':          10,

    # Overnight shifts
    'Metro Night': 21,  # overnight at Metro
    'CCF Night': 21,   # overnight at CCF
    
    # Community Shifts
    'Com Parma': 7,
    'Com Breckville': 7,

    # MLF Shifts
    'MLF Wayne': 7,
    'MLF Lorain': 7,
}

# Categories by name
west_names      = {'West', 'WestAM', 'WestPM'}
acute_names     = {'Acute', 'A1', 'A2', 'C1', 'C2', 'E1', 'E2'}
trauma_names    = {'Trauma'}
ccf_names       = {'E12', 'E18'}
overnight_names = {'Metro Night', 'CCF Night'}
community_names = {'Com Parma', 'Com Breckville'}
mlf_names       = {'MLF Wayne', 'MLF Lorain'}

# ------------------------
# 2. Build the all_shifts
# ------------------------

all_shifts = []
for current_date in all_dates:
    # Skip Wednesdays (weekday() == 2)
    if current_date.weekday() == 2:
        continue
    for name, hour in shift_defs.items():
        is_overnight = name in overnight_names
        # Prevent overnight shifts from starting on Tuesday or Wednesday
        if is_overnight and current_date.weekday() in (1, 2):  # 1=Tuesday, 2=Wednesday
            continue
        start_dt = datetime(
            current_date.year,
            current_date.month,
            current_date.day,
            hour, 0
        )
        if is_overnight:
            duration = timedelta(hours=48)
        elif name in {'West', 'Com Parma', 'Com Breckville', 'E18'}:
            duration = timedelta(hours=8)
        else:
            duration = timedelta(hours=10)

        # Determine category
        if is_overnight:
            category = 'overnight'
        elif name in trauma_names:
            category = 'trauma'
        elif name in ccf_names:
            category = 'ccf'
        elif name in acute_names:
            category = 'acute'
        elif name in west_names:
            category = 'west'
        elif name in community_names:
            category = 'community'
        elif name in mlf_names:
            category = 'mlf'
        
        if is_overnight:
            site = 'CCF' if name == 'CCF Night' else 'Metro'
        elif name in community_names:
            site = name.strip('Com ').replace(' ', '')
        elif name in mlf_names:
            site = name.strip('MLF ').replace(' ', '')
        else:
            site = 'CCF' if name in ccf_names else 'Metro'

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

save_shifts_json("shifts.json", all_shifts)