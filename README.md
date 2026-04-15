# Elixir Benchmark Suite

A framework for evaluating AI-generated Elixir code against verified test harnesses.
Each solution runs in its own BEAM process — a non-compiling solution cannot affect
any other task's evaluation.

## Prerequisites

- Elixir 1.17+ / OTP 27+
- PostgreSQL 16+ (only for database-tagged tasks)

## Setup

```bash
mix deps.get
mix compile
```

Test a single task:

```
mix run ./scripts/eval_task.exs 8 | jq
```