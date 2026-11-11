// Browser test for a recipe page. check-page.ps1 appends this inside a <script>
// tag to a temporary copy of the page, loads it in headless Chrome or Edge and
// reads the lines written to the results element it adds. Each line starts with
// PASS, FAIL or INFO. It drives the page the way a person would and never
// changes the original file.
(function () {
  const out = [];
  // check-page.ps1 sets __pageErrors before the page's own script runs, so
  // errors thrown while the page loads are caught too.
  const errors = window.__pageErrors || [];
  if (!window.__pageErrors) window.addEventListener("error", function (e) { errors.push(e.message); });
  function ok(cond, msg) { out.push((cond ? "PASS " : "FAIL ") + msg); }
  function info(msg) { out.push("INFO " + msg); }
  function $(id) { return document.getElementById(id); }
  // innerText only covers what is visible, so script source can't trigger this.
  function badText(el) {
    const m = (el.innerText || "").match(/.{0,40}\b(NaN|undefined|null|Infinity)\b.{0,20}/);
    return m ? m[0].replace(/\s+/g, " ") : "";
  }

  try {
    const base = RECIPE.baseServings;
    const nSteps = RECIPE.steps.length;
    const nIng = RECIPE.ingredients.reduce(function (a, g) { return a + g.items.length; }, 0);
    const nSubs = (RECIPE.substitutions || []).length;

    // Main page
    ok($("name").textContent === RECIPE.name, "recipe name shown: " + RECIPE.name);
    if (document.title !== RECIPE.name) info("tab title \"" + document.title + "\" differs from recipe name \"" + RECIPE.name + "\"");
    ok($("steps").children.length === nSteps, "all " + nSteps + " steps shown");
    ok(nSubs > 0 && $("subs").children.length === nSubs, "substitutions shown: " + $("subs").children.length + " of " + nSubs);
    ok($("mfp").textContent.split("\n").length === RECIPE.mfp.length + 1, "MyFitnessPal list has all " + RECIPE.mfp.length + " items");

    // Servings, checked at several sizes for NaN, undefined or leftover {placeholders}
    const sizes = [1, 2, 3, base, base + 1, 8, 12, 24].filter(function (n, i, a) { return n <= 24 && a.indexOf(n) === i; });
    const broken = [];
    sizes.forEach(function (n) {
      setServings(n);
      const bad = badText(document.querySelector("main") || document.body) || badText($("macros"));
      if (bad) broken.push(n + " servings: \"" + bad + "\"");
      if (/\{\w+\}/.test($("steps").textContent)) broken.push(n + " servings: unfilled {placeholder} in steps");
    });
    ok(broken.length === 0, "amounts and steps valid at " + sizes.join(", ") + " servings" + (broken.length ? ": " + broken.join("; ") : ""));
    setServings(base);
    const baseMacros = $("macros").textContent;
    $("plus").click();
    ok(currentServings === Math.min(24, base + 1), "+ button works (" + base + " to " + currentServings + ")");
    $("minus").click();
    ok(currentServings === base && $("macros").textContent === baseMacros, "- button works and macros return to the same values");

    // Cooking mode
    $("cook-start").click();
    ok(!$("cook").hidden && document.documentElement.classList.contains("cooking"), "cooking mode opens");
    const boxes = $("cook-check").querySelectorAll("input[type=checkbox]");
    ok(boxes.length === nIng, "ingredient checklist has all " + nIng + " items");
    ok(!badText($("cook-check")), "checklist amounts valid");
    if (boxes.length) boxes[0].click();

    const timerLines = [];
    let stepsOk = true;
    for (let i = 1; i <= nSteps; i++) {
      $("cook-next").click();
      if ($("cook-count").textContent !== "Step " + i + " of " + nSteps) stepsOk = false;
      const t = $("timer-start");
      timerLines.push("step " + i + ": " + (t.hidden ? "no timer" : t.textContent.replace(/^Start | timer$/g, "")) +
        " | " + currentSteps[i - 1].slice(0, 90));
    }
    ok(stepsOk, "Next steps through all " + nSteps + " steps");
    ok($("cook-next").textContent === "Finish", "last step shows Finish");
    timerLines.forEach(function (line) { info("timer " + line); });

    // Timer on the first step that has one
    let tStep = 0;
    for (let i = 1; i <= nSteps && !tStep; i++) if (stepSeconds(currentSteps[i - 1])) tStep = i;
    if (tStep) {
      cook.index = tStep; showStep();
      $("timer-start").click();
      ok(!$("timer-band").hidden && timer.running, "timer starts (" + $("timer-time").textContent + ")");
      $("timer-pause").click();
      const paused = !timer.running && $("timer-pause").textContent === "Resume";
      $("timer-pause").click();
      ok(paused && timer.running, "timer pauses and resumes");
      timer.end = Date.now() - 1; tick();
      ok($("timer-band").classList.contains("done") && /Time's up/.test($("timer-label").textContent), "timer finishes and shows Time's up");
      $("timer-cancel").click();
      ok($("timer-band").hidden, "Dismiss hides the timer");
    } else {
      info("no step has a time in it, so no timer was tested");
    }

    // Keyboard, reopening and resetting
    if (nSteps >= 2) {
      cook.index = 1; showStep();
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight" }));
      const right = cook.index === 2;
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft" }));
      ok(right && cook.index === 1, "arrow keys move between steps");
    }
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    ok($("cook").hidden && !document.documentElement.classList.contains("cooking"), "Escape closes cooking mode");
    $("cook-start").click();
    ok(cook.index === Math.min(1, nSteps) && cook.checked.size === (boxes.length ? 1 : 0), "reopening keeps the step and ticked items");
    $("cook-exit").click();
    if (base < 24) {
      $("plus").click(); $("cook-start").click();
      ok(cook.index === 0 && cook.checked.size === 0, "changing servings restarts cooking mode");
      $("cook-exit").click();
      setServings(base);
    }
  } catch (e) {
    errors.push(e && e.stack ? e.stack.split("\n").slice(0, 2).join(" ") : String(e));
  }
  ok(errors.length === 0, "no JavaScript errors" + (errors.length ? ": " + errors.join(" | ") : ""));

  const pre = document.createElement("pre");
  pre.id = "TEST-RESULTS";
  pre.textContent = out.join("\n");
  document.body.append(pre);
})();
