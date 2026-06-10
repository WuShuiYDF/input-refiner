# Input Refiner Implementation Plan

**Goal:** Python CLI tool that refines user input via local LLM before forwarding to upstream APIs.

**Architecture:** Single Python script (`refiner`) with subcommands (serve/models/switch/status). HTTP proxy on :18888 intercepts Anthropic Messages API, refines user messages via local llama.cpp, forwards to upstream. Config in `config.yaml`.

**Tech Stack:** Python 3.10+, httpx, pyyaml, Docker CLI

---

### Task 1: config.yaml

Create default configuration file.

### Task 2: refiner — config loader + CLI skeleton

Load config.yaml, parse subcommands, argparse setup.

### Task 3: refiner serve — HTTP proxy core

Anthropic Messages API proxy with refinement logic, streaming support, skip prefix.

### Task 4: refiner models / switch / status

Model listing, Docker-based switching, health checking.

### Task 5: install.sh

One-click install: deps, symlink, systemd unit.

### Task 6: Integration test

End-to-end test against local :8080.
