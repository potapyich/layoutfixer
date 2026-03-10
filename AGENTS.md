# AGENTS.md

## Scope
These instructions apply to the entire repository unless a deeper `AGENTS.md` overrides them.

## Default Approach
- Keep changes tightly scoped to the user's request.
- Prefer root-cause fixes over cosmetic patches.
- Preserve existing structure, targets, schemes, and naming unless a change is required.
- Avoid speculative refactors and dependency churn unless explicitly requested.

## Apple Project Assumptions
- Treat this repository as an Apple-platform codebase first if Xcode, Swift, or Objective-C files are present.
- Prefer edits in source files and build settings over manual `project.pbxproj` changes unless the project file must be updated.
- When touching UI or layout code, preserve Auto Layout intent, existing constraints, and device-size behavior.
- Keep changes compatible with the current deployment target and existing framework choices.

## Editing Rules
- Match surrounding style, file organization, and naming conventions.
- Use ASCII by default unless the file already requires Unicode.
- Add comments only when they clarify non-obvious logic or layout decisions.
- Update nearby docs, examples, or config comments when behavior changes.

## Validation
- Start with the smallest relevant validation for the touched area.
- For Apple targets, prefer targeted `xcodebuild` validation or existing test schemes over broad clean builds.
- If UI layout code changes, call out what should be verified on device/simulator when full validation is not possible here.
- If validation cannot be run, state that clearly in the final handoff.

## Safety
- Do not overwrite unrelated user changes.
- Do not delete files, remove targets, or run destructive git commands unless explicitly requested.
- Keep diffs reviewable and avoid incidental formatting-only churn.

## Repo Hygiene
- Do not commit, create branches, or rewrite history unless explicitly requested.
- Keep generated artifacts out of version control, including build outputs, DerivedData-style files, and local IDE state.
- If `.gitignore` is missing or incomplete, update it only as needed for artifacts introduced by the task.

## Communication
- Summarize what changed, why it changed, and what was validated.
- Call out assumptions, blockers, and any manual verification still worth doing.
