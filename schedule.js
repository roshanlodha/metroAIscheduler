// Global alias for Luxon
const DateTime = luxon.DateTime;

// --- Configuration & Constants ---

const SHIFT_DEFS = {
  "West": 7, "Acute": 7, "Trauma": 14,
  "E12": 7, "E18": 10,
  "Metro Night": 21, "CCF Night": 21,
  "Com Parma": 7, "Com Breckville": 7,
  "MLF Wayne": 7, "MLF Lorain": 7,
};

const CATEGORIES = {
  west: ["West", "WestAM", "WestPM"],
  acute: ["Acute", "A1", "A2", "C1", "C2", "E1", "E2"],
  trauma: ["Trauma"],
  ccf: ["E12", "E18"],
  overnight: ["Metro Night", "CCF Night"],
  community: ["Com Parma", "Com Breckville"],
  mlf: ["MLF Wayne", "MLF Lorain"]
};

function getCategory(name) {
  for (const [cat, names] of Object.entries(CATEGORIES)) {
    if (names.includes(name)) return cat;
  }
  return "unknown";
}

function getSite(name, category) {
  if (category === "overnight") return name === "CCF Night" ? "CCF" : "Metro";
  if (category === "community") return name.replace("Com ", "").replace(" ", "");
  if (category === "mlf") return name.replace("MLF ", "").replace(" ", "");
  if (category === "ccf") return "CCF";
  return "Metro";
}

// --- Main Logic ---

function runScheduler() {
  const btn = document.getElementById("solveBtn");
  const status = document.getElementById("status");
  const output = document.getElementById("output");

  btn.disabled = true;
  output.innerHTML = "";
  status.innerHTML = '<span class="loading">Generating optimized model...</span>';

  setTimeout(() => {
    try {
      executeSolver(status, output);
    } catch (e) {
      console.error(e);
      status.innerHTML = `<span class="error">Error: ${e.message}</span>`;
      btn.disabled = false;
    }
  }, 50);
}

function executeSolver(statusDiv, outputDiv) {
  const btn = document.getElementById("solveBtn");

  // 1. Get Inputs
  const startDateStr = document.getElementById("startDate").value;
  const endDateStr = document.getElementById("endDate").value;
  const studentInput = document.getElementById("studentList").value;

  if (!startDateStr || !endDateStr) throw new Error("Please select valid dates.");

  const students = studentInput
    .split(/[\n,]+/)
    .map(s => s.trim())
    .filter(s => s.length > 0);

  if (students.length === 0) throw new Error("No students provided.");

  const start = DateTime.fromISO(startDateStr);
  const end = DateTime.fromISO(endDateStr);

  // 2. Generate Shifts (same logic as before, matching Python solve.py)
  const allShifts = [];
  let current = start;
  let safetyCounter = 0;

  while (current <= end && safetyCounter < 365) {
    safetyCounter++;

    // Skip Wednesdays (weekday 3 in Luxon = Wednesday)
    if (current.weekday !== 3) {
      for (const [name, hour] of Object.entries(SHIFT_DEFS)) {
        const category = getCategory(name);
        const isOvernight = category === "overnight";

        // Prevent overnight shifts from starting on Tuesday (2) or Wednesday (3)
        if (isOvernight && (current.weekday === 2 || current.weekday === 3)) continue;

        const startDt = current.set({ hour: hour, minute: 0 });

        // Duration logic from Python:
        // - 48h for overnight
        // - 8h for West, Com Parma, Com Breckville, E18
        // - 10h for everything else
        let durationHours = 10;
        if (isOvernight) durationHours = 48;
        else if (["West", "Com Parma", "Com Breckville", "E18"].includes(name)) durationHours = 8;

        const endDt = startDt.plus({ hours: durationHours });

        allShifts.push({
          idx: allShifts.length,
          id: `${name}_${startDt.toFormat("yyyyMMddHH")}`,
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

  if (allShifts.length === 0) throw new Error("No shifts in selected date range.");

  // 3. Build LP Model for javascript-lp-solver
  // This uses a JSON model format instead of LP file format
  const model = {
    optimize: "total_assignments",
    opType: "max",
    constraints: {},
    variables: {},
    ints: {}
  };

  const getVar = (shiftId, stud) => `x|${shiftId}|${stud}`;

  // A) Global Shift Capacity: each shift can be assigned to at most 1 student
  allShifts.forEach(s => {
    model.constraints[`cap_${s.id}`] = { max: 1 };
  });

  // B) Student Requirements (matching Python solve.py exactly)
  students.forEach(stud => {
    // Per-student category requirements
    model.constraints[`${stud}_overnight`] = { equal: 1 };  // 1 overnight block
    model.constraints[`${stud}_trauma`] = { equal: 2 };     // 2 trauma shifts
    model.constraints[`${stud}_ccf`] = { equal: 3 };        // 3 CCF shifts
    model.constraints[`${stud}_community`] = { equal: 1 };  // 1 community shift
    model.constraints[`${stud}_mlf`] = { equal: 1 };        // 1 MLF shift
    model.constraints[`${stud}_total`] = { equal: 13 };     // 13 total shifts
    model.constraints[`${stud}_e18`] = { max: 1 };          // at most 1 E18
    model.constraints[`${stud}_acute`] = { min: 2 };        // at least 2 acute
    model.constraints[`${stud}_west`] = { min: 1 };         // at least 1 west

    allShifts.forEach(s => {
      const vName = getVar(s.id, stud);
      model.ints[vName] = 1;  // Binary variable

      const v = {
        total_assignments: 1,
        [`cap_${s.id}`]: 1,
        [`${stud}_total`]: 1
      };

      // Category contributions
      if (s.category === "overnight") v[`${stud}_overnight`] = 1;
      if (s.category === "trauma") v[`${stud}_trauma`] = 1;
      if (s.category === "ccf") v[`${stud}_ccf`] = 1;
      if (s.category === "community") v[`${stud}_community`] = 1;
      if (s.category === "mlf") v[`${stud}_mlf`] = 1;
      if (s.name === "E18") v[`${stud}_e18`] = 1;
      if (s.category === "acute") v[`${stud}_acute`] = 1;
      if (s.category === "west") v[`${stud}_west`] = 1;

      model.variables[vName] = v;
    });
  });

  // C) Conflict Constraints (matching Python solve.py)
  // - Rest: 20 hours between starts for two non-overnights
  // - Overlap: no time overlap for any shifts
  const REST_MS = 20 * 60 * 60 * 1000; // 20 hours in milliseconds

  const shiftsSorted = allShifts.slice().sort((a, b) => a.ts - b.ts);

  // Build conflict pairs using sweep-line approach
  let conflictCount = 0;
  for (let i = 0; i < shiftsSorted.length; i++) {
    const s1 = shiftsSorted[i];

    // Horizon: how far forward do we need to check?
    // - For overnights: only overlap matters (endTs)
    // - For non-overnights: max of overlap and rest window
    const horizonEnd = s1.isOvernight
      ? s1.endTs
      : Math.max(s1.endTs, s1.ts + REST_MS);

    for (let j = i + 1; j < shiftsSorted.length; j++) {
      const s2 = shiftsSorted[j];
      if (s2.ts >= horizonEnd) break; // No more conflicts possible

      // Check for overlap: s2 starts before s1 ends
      const overlap = s2.ts < s1.endTs;

      // Check for rest violation: both non-overnight and < 20h apart
      const restViolation = (!s1.isOvernight && !s2.isOvernight && (s2.ts - s1.ts) < REST_MS);

      if (overlap || restViolation) {
        const cNameBase = `conf_${conflictCount++}`;

        // Add constraint for each student
        students.forEach(stud => {
          const cName = `${cNameBase}_${stud}`;
          model.constraints[cName] = { max: 1 };

          const v1 = getVar(s1.id, stud);
          const v2 = getVar(s2.id, stud);

          if (model.variables[v1]) model.variables[v1][cName] = 1;
          if (model.variables[v2]) model.variables[v2][cName] = 1;
        });
      }
    }
  }

  console.log(`Model built. Variables: ${Object.keys(model.variables).length}, Constraints: ${Object.keys(model.constraints).length}`);

  // 4. Solve
  statusDiv.innerHTML = '<span class="loading">Solving...</span>';

  setTimeout(() => {
    try {
      if (typeof solver === 'undefined') {
        throw new Error("Solver library not loaded. Check that javascript-lp-solver is included.");
      }

      const results = solver.Solve(model);
      console.log("Solver results:", results);

      if (!results.feasible) {
        statusDiv.innerHTML = '<span class="error">No feasible solution found. Try adjusting dates or student count.</span>';
        btn.disabled = false;
        return;
      }

      statusDiv.innerHTML = '<span class="success">Solution Found!</span>';
      renderResults(results, allShifts, students, outputDiv);
    } catch (err) {
      console.error("Solver error:", err);
      statusDiv.innerHTML = `<span class="error">Solver error: ${err.message}</span>`;
    } finally {
      btn.disabled = false;
    }
  }, 50);
}

function renderResults(results, allShifts, students, container) {
  const schedule = {};
  students.forEach(s => schedule[s] = []);

  // Parse results - variable names are "x|shiftId|student"
  Object.keys(results).forEach(key => {
    if (key.startsWith("x|") && results[key] > 0.5) {
      const parts = key.split("|");
      const shiftId = parts[1];
      const student = parts[2];
      const shiftObj = allShifts.find(s => s.id === shiftId);
      if (shiftObj && schedule[student]) schedule[student].push(shiftObj);
    }
  });

  // Sort each student's shifts by time
  students.forEach(s => schedule[s].sort((a, b) => a.ts - b.ts));

  let html = '<table><thead><tr><th style="width:15%">Student</th><th style="width:5%">Count</th><th>Assigned Shifts</th></tr></thead><tbody>';

  students.forEach(student => {
    const myShifts = schedule[student];

    const shiftHtml = myShifts.map(s => {
      const dateStr = s.start.toFormat("MMM dd (EEE)");
      const timeStr = s.start.toFormat("HH:mm") + "-" + s.end.toFormat("HH:mm");
      let color = "#333";
      if (s.isOvernight) color = "#d35400";
      else if (s.category === "ccf") color = "#2980b9";
      else if (s.category === "trauma") color = "#c0392b";

      return `<div class="shift-cell" style="color:${color}">
          <span class="shift-time">${dateStr}</span>
          <b>${s.name}</b>
          <span class="shift-detail">[${timeStr}] @ ${s.site}</span>
      </div>`;
    }).join("");

    html += `<tr>
        <td style="vertical-align: top; font-weight: bold;">${student}</td>
        <td style="vertical-align: top; text-align: center;">${myShifts.length}</td>
        <td style="vertical-align: top;">${shiftHtml}</td>
      </tr>`;
  });

  html += "</tbody></table>";
  container.innerHTML = html;
}