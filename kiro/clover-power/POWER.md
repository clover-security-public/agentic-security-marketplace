---
name: clover-security
displayName: Clover Security
description: Clover reviews every spec before implementation and folds missing security requirements into the work. This power teaches the agent to honor Clover's review verdicts and requirement files.
author: Clover Security
repository: https://github.com/clover-security-public/agentic-security-marketplace
license: MIT
keywords:
  - security
  - appsec
  - clover
  - review
  - requirements
---

# Clover Security

## Overview

Clover is a security review layer for agentic coding. In this workspace, hooks
named "Clover Security" review the spec (`.kiro/specs/<feature>/`) as it is
written and again immediately before each task starts implementing. When a
review finds missing security requirements, they arrive in two ways:

- The blocked task's error text lists the requirements directly.
- A `.clover-requirements.md` file is written next to the spec files.

## Tool Usage

This power currently ships no MCP tools; the review runs through workspace
hooks. When Clover requirements are present, treat them as part of the spec:

1. If a task start is blocked with security requirements, update the spec
   (requirements.md and design.md) to address each one, then start the task
   again — the review re-evaluates the updated spec.
2. If a `.clover-requirements.md` file exists in the spec directory, read it
   before implementing and satisfy each requirement in the code you write.
3. Never delete or edit `.clover-requirements.md` to make a review pass; it is
   cleared automatically when the review approves the spec.

## Available MCP Servers

None yet. The Clover MCP server ("ask Clover") is a planned addition to this
power.

## Configuration

No configuration. The workspace hooks carry their own credentials
(`.kiro/clover/env.sh`); this power only provides agent guidance.
