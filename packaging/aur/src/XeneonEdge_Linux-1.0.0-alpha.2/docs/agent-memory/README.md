# Agent memory (mirror)

A version-controlled snapshot of the Claude Code auto-memory for this project.
The **live source of truth** is `~/.claude/projects/-home-simon-IdeaProjects-XeneonEdge-Linux/memory/`,
which Claude reads/writes across sessions; the copies here are for history,
review, and portability. Re-sync after memory changes:

```sh
cp ~/.claude/projects/-home-simon-IdeaProjects-XeneonEdge-Linux/memory/*.md docs/agent-memory/
```

`MEMORY.md` is the index loaded each session; the other files hold one fact each
(frontmatter `type`: user / feedback / project / reference).
