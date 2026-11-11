---
context: fork
background: false
name: recipe-check
description: Checks saved recipes in recipes/ against the user's cut rules (300 to 500 kcal, 50 g or more protein per serving, no yogurt, cucumber or zucchini), then tests each recipe's servings page in a headless browser (matching data, servings, cooking mode, timers), and reports pass or fail for each one. Use when the user asks whether a recipe fits their macros or rules, whether a recipe page works, or wants their recipes audited. Read-only; never edits recipes.
when_to_use: Phrases like "is this cut-friendly?", "check my macros", "does the beef recipe pass?", "audit my recipes", "does the page work?", "test cooking mode".
argument-hint: "[recipe name, or blank for all]"
shell: powershell
allowed-tools:
  - Read
  - Glob
  - Grep
  - PowerShell(Get-ChildItem *)
  - PowerShell(powershell -NoProfile -File *check-macros.ps1*)
  - PowerShell(powershell -NoProfile -File *check-page.ps1*)
disallowed-tools:
  - Edit
  - Write
---

# Recipe check

Check recipes against the user's cut rules and report what passes and what doesn't. This skill is read-only: report problems and offer fixes, but don't change any files.

## Which recipes

Requested: "$ARGUMENTS"

Recipes on disk right now:
!`Get-ChildItem recipes -Filter *.md -Name`

- If something was requested, check only the recipe from the list above that best matches it. If nothing matches, say so and show the list.
- If the request is blank, check every recipe in the list.

## The rules

Read the **Targets** and **Ingredients the user can buy and eats** sections of `.claude/agents/recipe-builder.md`. That file is the single source of truth, so take the numbers and banned ingredients from it rather than from this skill.

## Run the script for each recipe

```
powershell -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/check-macros.ps1" -Path recipes/<file>.md -MinKcal <min> -MaxKcal <max> -MinProtein <protein> -Banned "<comma,separated,words>"
```

Fill the numbers and banned words from the rules file. Include obvious related words, such as tzatziki and raita for yogurt and cucumber, and courgette for zucchini.

The script handles the mechanical checks: kcal range, protein minimum, whether the macros add up, banned-word hits with line numbers, and whether the `.html` page exists. Trust its numbers rather than redoing the maths.

## Test the page for each recipe

If the `.html` page exists, run:

```
powershell -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/check-page.ps1" -Path recipes/<file>.md
```

It takes up to a minute per recipe. It checks three things:
- **Data:** the page's `RECIPE.macros` and `baseServings` match the `.md`.
- **Template:** the page's code matches `recipes/beef-and-broccoli-stir-fry.html` apart from the recipe data and `<title>`. A FAIL here usually means the page is an older copy made before the template gained a feature, or was edited by hand.
- **Browser test:** it opens a temporary copy in headless Chrome or Edge and clicks through it, testing servings from 1 to 24, substitutions, the MyFitnessPal list, cooking mode, the timer, keyboard shortcuts and JavaScript errors.

It writes only to a temporary folder that it deletes afterwards. If it says `SKIPPED` because no browser was found, report that rather than a pass. It can't test the Copy button, the timer sound or keeping the screen on, because those need a person at a real browser.

## Then use judgment

The macro script only matches words, so check its banned-word hits in context:
- A hit like "no yogurt needed" is not a real use. Mark it as a pass with a note.
- Read the Ingredients and Substitutions sections for banned items the word list wouldn't catch, such as a store-bought dressing or sauce that usually contains yogurt.

The page script lists `INFO` lines that aren't failures, but they're worth a look:
- `INFO timer` shows the timer cooking mode offers for each step. Point out timers that don't fit, such as one for "about 5 minutes" of chopping, and a long step with no timer because its time isn't written as a number.
- `INFO tab title` means the browser tab name differs from the recipe name. Mention it as a small fix.

## Report

Show a table with one row per recipe:

| Recipe | kcal | Protein | Banned items | Macros add up | Page matches .md | Page works |
|---|---|---|---|---|---|---|

Use ✅ or ❌ in each cell, with the number or the problem next to it. **Page matches .md** covers the data and template checks; **Page works** is the browser test, written as "✅ 21/21" or "❌ 19/21". Then list each failure in one line, with the change that would fix it (for example, "swap 2 tbsp oil for 1 tbsp to cut about 120 kcal"), followed by any timer or title notes. If everything passes, say so in one line.
