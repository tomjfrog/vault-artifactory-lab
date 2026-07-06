# Internal working notes

Customer discovery notes live in `internal/` (gitignored) — **do not edit** `internal/customer-requirements.md`; lab answers go in `docs/`.
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

Customer-facing content belongs in [../setup-and-validation.md](../setup-and-validation.md), [../visual-architecture.md](../visual-architecture.md), `README.md`, and `scripts/`.
