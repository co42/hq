---
name: hq-files
description: Write plans, designs, investigations, reports and other notes where HQ shows them, linked to their task. Use whenever you write a markdown document meant to outlive this session, when the user asks for a plan, a design, a write-up, findings, notes or a report, or asks to note a fact, decision or idea that isn't a thing to do.
---

# HQ files

The user reads your plans and reports in HQ: in Files and Artifacts (pinned first, then the newest) and on their task's card, opened in a sheet and rendered (Mermaid included). A file is a markdown note in their Obsidian vault under `hq/files/`. HQ names it by its date and title: `hq file new "Push path plan"` makes `2026-11-11 - Push path plan`, and every command takes that name (or the title alone). Don't put a date in the title. HQ owns the front matter; the user sets the project, tags and pin in HQ.

## Commands

Everything goes through `hq`, so you never need file permissions on the vault:

```
hq ls files                                     # existing notes, newest first
hq file show "<name>"                           # a note's text
hq file new "Title" [--task T-12] --body -      # create it with its markdown on stdin; prints its name
hq file write "<name>" --section "Next steps" --body -   # replace one section, or add it at the end
hq file write "<name>" --replace "old" --with "new"      # change an exact text, found once
hq file write "<name>" --body - [--append]      # replace all of it, or add to its end
hq task link T-34 "<name>"                      # show it on another task too
hq file delete "<name>" --yes                   # only when the user asks (without --yes: what it would delete)
```

Pipe the markdown in: `printf '%s\n' '# Push path plan' '' 'The registry retries…' | hq file new "Push path plan" --task T-12 --body -`. A new note links to this session and to its task: `--task`, else the one task this session works on (pass `--task` when it works on several). It takes the task's project. Writing a note links this session to it.

## When

- **Before creating** a note, check `hq ctx` and `hq ls files`. If one covers the subject, update it with `hq file write`.
- **A plan, design, investigation or report** you write for the user: always an HQ file linked to its task, not in the chat alone and not loose in the repo (unless the user asks for a repo file).
- **When the work moves on**: update the note so it stays true.
- **Ready for the user to read**: `hq notify "Push path plan ready to read"`. It links the notes this session wrote since its last notification (the `hq` skill, Telling the user).
- **The user asks to note something** that isn't a thing to do (a fact, a decision, an idea to keep): an HQ file.

## Content

- Start with `# Title`, then the point in a few lines. Headings, short paragraphs, lists.
- Diagrams in Mermaid code blocks. Links to other notes as `[[Title]]`, to code as URLs or paths.
- A plan ends with its open questions and next steps; a report with what was found and what to do.

## Rules

- Don't edit the front matter, move or rename notes: HQ and Obsidian rely on them. A note that's no longer true gets updated; one to throw away, the user deletes in HQ, or asks you to (`hq file delete`: it goes to the Trash).
