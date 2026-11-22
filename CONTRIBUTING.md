# Contributing to Frieren Desk

Thank you for your interest in contributing to Frieren Desk! This document provides guidelines and instructions for contributing.

## Code of Conduct

Be respectful and constructive in issues, reviews and discussions.

## Getting Started

1. Fork the repository
2. Clone your fork
3. Create a new branch
4. Make your changes
5. Run the checks below
6. Submit a pull request

## Branch Naming Convention

- Feature: `feature/description`
- Bug fix: `fix/description`
- Documentation: `docs/description`
- Refactor: `refactor/description`

## Commit Message Format

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types:
- feat: A new feature
- fix: A bug fix
- docs: Documentation changes
- style: Code style changes
- refactor: Code refactoring
- test: Adding or modifying tests
- chore: Maintenance tasks

## Verification

Before opening a PR, run what CI runs, plus a live smoke test:

```bash
bash -n install.sh tools/*.sh quickshell/frieren/hooks/*.sh
qmllint quickshell/frieren/components/*.qml
cc -O2 -o /tmp/frieren-tray quickshell/frieren/tray.c $(pkg-config --cflags --libs gio-2.0)
./install.sh   # then click the pet, send a message, check the tray menu
```

Notes:

- Keep code, docs and commit messages in English.
- Do not reformat files outside your change.
- Never hardcode secrets; the opencode key travels over stdin, never in files.
- After UI changes, update `quickshell/frieren/README.md` and the screenshots if they no longer match.

## Questions?

Feel free to open an issue for any questions or concerns.
