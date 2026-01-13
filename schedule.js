// Global alias for Luxon
const DateTime = luxon.DateTime;

// --- Configuration & Constants ---

const SHIFT_DEFS = {
    'West': 7, 'Acute': 7, 'Trauma': 14,
    'E12': 7, 'E18': 10,
    'Metro Night': 21, 'CCF Night': 21,
    'Com Parma': 7, 'Com Breckville': 7,
    'MLF Wayne': 7, 'MLF Lorain': 7,
};

const CATEGORIES = {
    west: ['West', 'WestAM', 'WestPM'],
    acute: ['Acute', 'A1', 'A2', 'C1', 'C2', 'E1', 'E2'],
    trauma: ['Trauma'],
    ccf: ['E12', 'E18'],
    overnight: ['Metro Night', 'CCF Night'],
    community: ['Com Parma', 'Com Breckville'],
    mlf: ['MLF Wayne', 'MLF Lorain']
};

function getCategory(name) {
    for (const [cat, names] of Object.entries(CATEGORIES)) {
        if (names.includes(name)) return cat;
    }
    return 'unknown';
}

function getSite(name, category) {
    if (category === 'overnight') return name === 'CCF Night' ? 'CCF' : 'Metro';
    if (category === 'community') return name.replace('Com ', '').replace(' ', '');
    if (category === 'mlf') return name.replace('MLF ', '').replace(' ', '');
    if (category === 'ccf') return 'CCF';
    return 'Metro';
}

// --- Main Logic ---

function runScheduler() {
    const btn = document.getElementById('solveBtn');
    const status = document.getElementById('status');
    const output = document.getElementById('output');
    
    btn.disabled = true;
    output.innerHTML = '';
    status.innerHTML = '<span class="loading">Generating optimized model...</span>';

    setTimeout(() => {
        try {
            executeSolver(status, output);
        } catch (e) {
            console.error(e);
            status.innerHTML = `<span class="error">Error: ${e.message}</span>`;
        } finally {
            btn.disabled = false;
        }
    }, 100);
}

function executeSolver(statusDiv, outputDiv) {
    // 1. Get Inputs
    const startDateStr = document.getElementById('startDate').value;
    const endDateStr = document.getElementById('endDate').value;
    const studentInput = document.getElementById('studentList').value;

    if (!startDateStr || !endDateStr) throw new Error("Please select valid dates.");
    
    const students = studentInput.split(/[\n,]+/).map(s => s.trim()).filter(s => s.length > 0);
    if (students.length === 0) throw new Error("No students provided.");

    const start = DateTime.fromISO(startDateStr);
    const end = DateTime.fromISO(endDateStr);

    // 2. Generate Shifts
    const allShifts = [];
    let current = start;
    let safetyCounter = 0;
    
    while (current <= end && safetyCounter < 365) {
        safetyCounter++;
        if (current.weekday !== 3) { // Skip Wed
            for (const [name, hour] of Object.entries(SHIFT_DEFS)) {
                const category = getCategory(name);
                const isOvernight = category === 'overnight';

                if (isOvernight && (current.weekday === 2 || current.weekday === 3)) continue;

                const startDt = current.set({ hour: hour, minute: 0 });
                let durationHours = 10;
                if (isOvernight) durationHours = 48;
                else if (['West', 'Com Parma', 'Com Breckville', 'E18'].includes(name)) durationHours = 8;

                const endDt = startDt.plus({ hours: durationHours });

                allShifts.push({
                    id: `${name}_${startDt.toFormat('yyyyMMddHH')}`,
                    start: startDt,
                    end: endDt,
                    name: name,
                    category: category,
                    site: getSite(name, category),
                    isOvernight: isOvernight,
                    ts: startDt.toMillis(),
                    endTs: endDt.toMillis()
                });
            }
        }
        current = current.plus({ days: 1 });
    }

    console.log(`Generated ${allShifts.length} potential shifts.`);

    // 3. Build LP Model
    const model = {
        optimize: "total_assignments",
        opType: "max",
        constraints: {},
        variables: {},
        ints: {}
    };

    const getVar = (shiftId, stud) => `x|${shiftId}|${stud}`;

    // A. Global Shift Capacity
    allShifts.forEach(s => {
        model.constraints[`cap_${s.id}`] = { max: 1 };
    });

    // B. Student Assignments
    students.forEach(stud => {
        model.constraints[`${stud}_overnight`] = { equal: 1 };
        model.constraints[`${stud}_trauma`]    = { equal: 2 };
        model.constraints[`${stud}_ccf`]       = { equal: 3 };
        model.constraints[`${stud}_community`] = { equal: 1 };
        model.constraints[`${stud}_mlf`]       = { equal: 1 };
        model.constraints[`${stud}_total`]     = { equal: 13 };
        model.constraints[`${stud}_e18`]       = { max: 1 };
        model.constraints[`${stud}_acute`]     = { min: 2 };
        model.constraints[`${stud}_west`]      = { min: 1 };

        allShifts.forEach(s => {
            const vName = getVar(s.id, stud);
            model.ints[vName] = 1;

            const v = { 
                total_assignments: 1, 
                [`cap_${s.id}`]: 1,
                [`${stud}_total`]: 1
            };

            if (s.category === 'overnight') v[`${stud}_overnight`] = 1;
            if (s.category === 'trauma')    v[`${stud}_trauma`] = 1;
            if (s.category === 'ccf')       v[`${stud}_ccf`] = 1;
            if (s.category === 'community') v[`${stud}_community`] = 1;
            if (s.category === 'mlf')       v[`${stud}_mlf`] = 1;
            if (s.name === 'E18')           v[`${stud}_e18`] = 1;
            if (s.category === 'acute')     v[`${stud}_acute`] = 1;
            if (s.category === 'west')      v[`${stud}_west`] = 1;

            model.variables[vName] = v;
        });
    });

    // C. OPTIMIZED CONFLICTS (The speedup)
    
    // 1. "Overlap" via Time Buckets (Drastically faster than pairwise)
    // We check every 4 hours. If a shift covers a bucket, it adds to that bucket's constraint.
    // Buckets must be sum <= 1 per student.
    
    // Create buckets roughly every 4 hours across the date range
    let bucketTime = start.set({ hour: 0 });
    const buckets = [];
    while (bucketTime < end.plus({days:1})) {
        buckets.push(bucketTime.toMillis());
        bucketTime = bucketTime.plus({ hours: 4 });
    }

    students.forEach(stud => {
        buckets.forEach((bTs, idx) => {
             // We only create a constraint if shifts actually fall here
             // to save memory
             const bucketName = `time_${idx}_${stud}`;
             // We'll lazy-add this to model.constraints only if used
        });
    });

    // Pre-calculate shift coverage for buckets
    allShifts.forEach(s => {
        // Find which buckets this shift covers
        const sStart = s.ts;
        const sEnd = s.endTs;
        
        // Simple check: does the shift overlap the bucket point?
        // Actually, better: checking if shift exists during this specific moment
        // We scan buckets. Optimization: binary search or math would be faster, 
        // but linear scan of ~180 buckets is fine for 200 shifts.
        
        buckets.forEach((bTs, idx) => {
            // If the bucket time is inside the shift [Start, End)
            if (bTs >= sStart && bTs < sEnd) {
                const cNameBase = `t_conflict_${idx}`;
                
                students.forEach(stud => {
                    const cName = `${cNameBase}_${stud}`;
                    const vName = getVar(s.id, stud);
                    
                    // Add to constraint definition if not exists
                    if (!model.constraints[cName]) model.constraints[cName] = { max: 1 };
                    
                    // Add variable contribution
                    if (model.variables[vName]) model.variables[vName][cName] = 1;
                });
            }
        });
    });


    // 2. Rest Constraints (20 hours between starts of non-overnights)
    // We still need pairwise here, but ONLY for shifts within ~24h of each other
    // and ONLY for non-overnights.
    
    const nonOvernights = allShifts.filter(s => !s.isOvernight);
    // Sort by time to allow early exit
    nonOvernights.sort((a,b) => a.ts - b.ts);

    for (let i = 0; i < nonOvernights.length; i++) {
        const s1 = nonOvernights[i];
        
        // Only look ahead a short window
        for (let j = i + 1; j < nonOvernights.length; j++) {
            const s2 = nonOvernights[j];
            
            // If start times are > 20h apart, no conflict possible (since array is sorted)
            // 20 hours in ms = 72,000,000
            const diff = s2.ts - s1.ts;
            if (diff >= 72000000) break; // Optimization: Stop inner loop early

            // If we are here, diff < 20h. THIS IS A REST VIOLATION.
            // Constraint: s1 + s2 <= 1
            const cNameBase = `rest_${i}_${j}`;
            students.forEach(stud => {
                const cName = `${cNameBase}_${stud}`;
                model.constraints[cName] = { max: 1 };
                
                const v1 = getVar(s1.id, stud);
                const v2 = getVar(s2.id, stud);
                
                model.variables[v1][cName] = 1;
                model.variables[v2][cName] = 1;
            });
        }
    }

    console.log(`Model built. Variables: ${Object.keys(model.variables).length}, Constraints: ${Object.keys(model.constraints).length}`);

    // 4. Solve
    statusDiv.innerHTML = '<span class="loading">Solving...</span>';
    
    setTimeout(() => {
        if (typeof solver === 'undefined') {
            statusDiv.innerHTML = '<span class="error">Library Error: Solver not loaded.</span>';
            return;
        }

        const results = solver.Solve(model);
        console.log("Solver Status:", results);

        if (!results.feasible) {
            statusDiv.innerHTML = '<span class="error">No feasible solution found. Relax constraints.</span>';
            return;
        }

        statusDiv.innerHTML = '<span class="success">Solution Found!</span>';
        renderResults(results, allShifts, students, outputDiv);
    }, 50);
}

function renderResults(results, allShifts, students, container) {
    const schedule = {};
    students.forEach(s => schedule[s] = []);

    Object.keys(results).forEach(key => {
        if (key.startsWith('x|') && results[key] > 0.5) {
            const parts = key.split('|');
            const shiftId = parts[1];
            const student = parts[2];
            const shiftObj = allShifts.find(s => s.id === shiftId);
            if (shiftObj && schedule[student]) schedule[student].push(shiftObj);
        }
    });

    students.forEach(s => schedule[s].sort((a, b) => a.ts - b.ts));

    let html = '<table><thead><tr><th style="width:15%">Student</th><th style="width:5%">Count</th><th>Assigned Shifts</th></tr></thead><tbody>';

    students.forEach(student => {
        const myShifts = schedule[student];
        
        let shiftHtml = myShifts.map(s => {
            const dateStr = s.start.toFormat('MMM dd (EEE)');
            const timeStr = s.start.toFormat('HH:mm') + '-' + s.end.toFormat('HH:mm');
            let color = '#333';
            if (s.isOvernight) color = '#d35400';
            else if (s.category === 'ccf') color = '#2980b9';
            else if (s.category === 'trauma') color = '#c0392b';

            return `<div class="shift-cell" style="color:${color}">
                <span class="shift-time">${dateStr}</span> 
                <b>${s.name}</b> 
                <span class="shift-detail">[${timeStr}] @ ${s.site}</span>
            </div>`;
        }).join('');

        html += `<tr>
            <td style="vertical-align: top; font-weight: bold;">${student}</td>
            <td style="vertical-align: top; text-align: center;">${myShifts.length}</td>
            <td style="vertical-align: top;">${shiftHtml}</td>
        </tr>`;
    });

    html += '</tbody></table>';
    container.innerHTML = html;
}