# Meal prep recipes

## New or changed recipes

1. Build the recipe with the `recipe-builder` subagent. Its file, `.claude/agents/recipe-builder.md`, holds the rules: 300 to 500 kcal and 50 g or more protein per serving, Sheng Siong ingredients only, and no yogurt, cucumber or zucchini.
2. When it finishes, run the `recipe-check` skill on the new recipe. The subagent can't run a browser, so this is the only test the servings page gets.
3. If anything fails, fix both the `.md` and the `.html`, keeping them matched, and run `recipe-check` again. Then give the user the macros, the MyFitnessPal list, the check results and the agent's "Check at Sheng Siong" list.

Sheng Siong's stock can't be checked online: the site blocks automated access, and search engines don't index its products. Never claim an ingredient was confirmed there. Ask the user to check uncertain items in the app or in store.

For a small tweak to an existing recipe, edit it in the main conversation instead of starting the subagent. Follow the same rules file and run `recipe-check` afterwards.

`recipes/beef-and-broccoli-stir-fry.html` is the template every servings page is copied from. If you change its code, update the other pages' code to match. Otherwise `recipe-check` reports them as template FAIL.
