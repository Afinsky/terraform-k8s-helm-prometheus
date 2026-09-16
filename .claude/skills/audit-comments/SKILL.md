---
name: audit-comments
description: Audit comments across a set of files (or the whole repo) for staleness — verifying each comment's stated rationale ("why this was done") still matches what the code currently does, not just that the comment is grammatically plausible. Use when the user asks to "actualize"/refresh/audit comments, or after a structural refactor (file moves, module splits, renames) where comments written for the old shape may no longer be accurate.
---

# Audit comments

Comments rot silently: code changes, comments don't. A comment can read
perfectly and still be wrong — it described a constraint, a workaround, or a
rationale that no longer holds. Grepping for TODO/FIXME does not catch this;
it requires reading the comment next to the code it describes and asking "is
this still true."

## Process

1. **Scope the audit.** Default to every source file under the directory the
   user named (a module, a layer, a package) — not just files touched
   recently. Read each file **in full**, not excerpts; a stale rationale is
   easy to miss in a partial read. For a large tree, batch file reads (e.g.
   `cat` every file in a directory in one command) rather than reading one
   file at a time.

2. **For every comment, check two things independently:**
   - **Factual accuracy**: does it name a file, function, variable, path, or
     value that still exists with that name/value? (e.g. a comment
     hardcoding an account ID, a path, a version number, a "Phase N" label
     from an abandoned plan.)
   - **Rationale currency**: does the *reason* it gives still hold? A
     comment can be factually accurate today and still be stale — e.g. "X
     is required because Y" when a later change made Y no longer true, or a
     comment explaining a workaround for a bug that's since been fixed
     elsewhere. This is the check that actually matters; don't stop at the
     first one.

3. **Cross-reference sibling files.** If the same kind of variable/resource
   is documented in more than one place (e.g. the same input described in
   two modules' `variables.tf`), compare wording — a divergence is a strong
   signal one of them wasn't updated when the other was.

4. **Classify each finding before touching anything:**
   - Stale and misleading → fix now.
   - Vague/generic but not wrong → improve only if asked to be thorough;
     don't invent scope.
   - Missing entirely where a non-obvious rationale exists (a hidden
     constraint, a subtle invariant, a "why not the simpler way" decision)
     → add one, but don't add comments that just restate the code.

5. **Fix minimally.** Comment-only changes: don't refactor the code
   underneath while auditing its comments — that's a different task and
   inflates the diff being reviewed for a "just comments" change. If a fix
   naturally requires touching code (e.g. the comment was right and the code
   is what's wrong), stop and flag it to the user instead of silently
   fixing both.

6. **Verify without mutating state.** Run the project's read-only checks —
   formatters and validators (`terraform fmt -check`, `terraform validate`,
   linters, type checkers, `pre-commit run --all-files`) — never a command
   that applies, deploys, or destroys anything, even for a "just comments"
   change. In this repo specifically: **never run `apply` or `destroy`, or
   any Make target that wraps them — only `plan`/`validate`/`fmt`/other
   read-only commands**, per this repo's standing rule that the user runs
   all apply/destroy operations personally.

7. **Report the diff, not a narrative.** List what changed and, for each
   fix, the one-line reason it was stale — not a restated summary of every
   file that turned out fine.

## Anti-patterns to avoid

- Treating "the comment parses as a sentence" as proof it's accurate.
- Fixing only comments near code you were already editing for an unrelated
  task, then calling the audit done — if asked to audit, cover the whole
  named scope.
- Turning a comment audit into a refactor, a renaming pass, or a docs
  rewrite beyond what's needed to make the rationale accurate again.
- Skipping files that "probably" don't have stale comments — the whole point
  is that staleness isn't visible without reading.
