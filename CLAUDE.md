# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This is a personal Kubernetes learning workspace, not an application codebase. The user is learning Kubernetes hands-on, step by step.

## Notes file — keep it updated

`NOTES.md` is the user's running study notes. **Whenever a session teaches or uses something worth remembering, add it to `NOTES.md` before finishing.** This covers new commands, concepts, errors and how they were fixed, gotchas, and manifests written. The user asked for this explicitly.

- Add to the matching section, or create a new one. Don't duplicate entries that already exist.
- Keep entries short: the command or concept, one line on what it does or why it matters, and an example where it helps.
- Put troubleshooting entries in the "Troubleshooting" section as **symptom → cause → fix**.
- Add a dated line to the "Session log" at the bottom.

## Environment

- Local cluster: **minikube** (docker driver, containerd runtime) on CachyOS (Arch-based), shell is zsh.
- API server is at `192.168.49.2:8443`. Minikube does not restart on its own after a reboot. If `kubectl` returns `connect: no route to host`, run `minikube status`, then `minikube start`.
- Docker uses the btrfs storage driver, so minikube runs with `preload=false`, which makes the first start slower.

## Conventions

- Put YAML manifests you create in this directory, grouped by topic (for example `pods/`, `deployments/`), so the user can reapply them with `kubectl apply -f`.
- Explain what each command does as you run it. The goal is learning, not only getting the task done.
