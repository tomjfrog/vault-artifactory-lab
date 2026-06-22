# Internal working notes

Use the `internal/` directory (gitignored) for material that should **not** be shared with customers:

- Customer discovery notes and constraints
- Draft specs and open questions
- Environment-specific URLs or credentials (never commit secrets — use `.env`)
- Failed approaches and debugging notes

## Suggested files

Create these locally under `internal/`:

```
internal/
├── customer-context.md    # org name, stakeholders, success criteria
├── spec.md                # lab requirements and scope
├── decisions.md           # ADR-style decision log
└── sandbox-notes.md       # tenant-specific quirks
```

Customer-facing content belongs in `README.md`, `docs/`, and `scripts/` instead.
