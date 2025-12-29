# Contributing

Thanks for your interest.

## Development

- Run ShellCheck locally (recommended):
  ```bash
  shellcheck -x bin/netopt lib/*.sh
  ```

- Keep changes idempotent and safe by default.
- Any new tunings must include:
  - rationale
  - rollback support
  - clear documentation
