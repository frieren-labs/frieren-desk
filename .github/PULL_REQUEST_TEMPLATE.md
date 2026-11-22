---
name: Pull Request
about: Create a pull request
title: ''
labels: ''
assignees: ''
---

## Description
A clear and concise description of the changes in this PR.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Code refactoring
- [ ] Performance improvement
- [ ] Test addition or update
- [ ] CI/CD update

## Area
- [ ] Pet UI (QML in `quickshell/frieren/`)
- [ ] Tray helper (C in `quickshell/frieren/tray.c`)
- [ ] Scripts and tools (`tools/`, `hooks/`)
- [ ] Docs, skills or CI

## Checklist
- [ ] My code follows the style guidelines of this project
- [ ] I have performed a self-review of my own code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] `qmllint quickshell/frieren/components/*.qml` passes locally
- [ ] `bash -n` passes on every touched shell script
- [ ] `tray.c` still compiles (`cc -O2 -o /tmp/frieren-tray quickshell/frieren/tray.c $(pkg-config --cflags --libs gio-2.0)`)
- [ ] I ran `./install.sh` and smoke-tested the pet
- [ ] Any dependent changes have been merged and published

## Screenshots/Videos
If applicable, add screenshots or videos to help explain your changes.

## Additional Notes
Add any other context about the pull request here.
