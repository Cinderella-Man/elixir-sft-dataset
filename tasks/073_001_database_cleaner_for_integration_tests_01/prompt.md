# `DBCleaner` — Database Isolation Helper for Integration Tests

## Overview

This specification describes an Elixir module called `DBCleaner` that ensures database isolation between integration tests by cleaning up state between test runs.

Both strategies described below are to be entirely self-contained in a single file with no external dependencies beyond Ecto. State is carried between `start/2` and `clean/0` through the process dictionary (`Process.put/get`), so that no extra process is required.

## API

The public API consists of two functions.

- `DBCleaner.start(strategy, opts \\ [])` — called in a test's `setup` block. The `strategy` is either `:transaction` or `:truncation`. The `opts` keyword list accepts a `:repo` key (an Ecto repo module, e.g. `MyApp.Repo`) and a `:tables` key (a list of table name strings to truncate, e.g. `["users", "posts"]`). It stores whatever state is needed to clean up later.
- `DBCleaner.clean()` — called in `on_exit`. It performs the actual cleanup based on whichever strategy was started.

## Strategies

Two strategies are to be implemented.

**`:transaction`** — In `start/2`, a database transaction is begun (using `Ecto.Adapters.SQL.begin_transaction/1` or equivalent) and the connection/transaction reference is stored in the process dictionary or a named Agent. In `clean/0`, that transaction is rolled back so no data persists. This strategy is fast but only works with synchronous tests (`async: false`).

**`:truncation`** — `start/2` performs no database work: it only validates the table names and stashes the `:repo` and `:tables` options in the process dictionary so `clean/0` can retrieve them. In `clean/0`, a `TRUNCATE <table> RESTART IDENTITY CASCADE` SQL command is issued for every table listed in `:tables`, executed via `Ecto.Adapters.SQL.query!/3`. This strategy is slower but works with any test configuration.

## Additional interface contract

- Under the `:truncation` strategy, `clean/0` issues exactly one SQL statement per listed table (never a single combined multi-table `TRUNCATE`), each of the exact form `TRUNCATE <table> RESTART IDENTITY CASCADE` with the bare, unquoted table name. It is executed by calling `query!/3` on the configured repo module itself — `repo.query!(repo, sql, [])` — rather than by referencing `Ecto.Adapters.SQL` directly, so that a stand-in repo module which defines `query!/3` receives one call per table.
- The same stand-in-repo rule applies to the `:transaction` strategy: `start/2` must begin the transaction eagerly, during `start/2` itself (not deferred to `clean/0`), by calling `begin_transaction/0` with no arguments on the configured repo module — `repo.begin_transaction()`. It must not call `Ecto.Adapters.SQL.begin_transaction(repo)`, `repo.transaction/1`, `repo.checkout/1`, or anything that touches `get_dynamic_repo/0`; the "`Ecto.Adapters.SQL.begin_transaction/1` or equivalent" wording above means the repo-module call is the required equivalent here. The call returns `{:ok, ref}` — the ref may be stored or simply discarded.
- Under the `:transaction` strategy, `clean/0` rolls back by calling `rollback/0` with no arguments on the repo module — `repo.rollback()` — and must issue no SQL at all via `query!/3`. The `:tables` option is accepted but ignored entirely by this strategy: no `TRUNCATE` statement may be issued even when tables were passed to `start/2`.
- `start/2` returns exactly `{:ok, :transaction}` when the `:transaction` strategy starts successfully, and exactly `{:ok, :truncation}` when the `:truncation` strategy starts successfully.
- `clean/0` returns exactly `:ok` after a successful cleanup under both strategies.

## Edge cases

- `clean/0` when `start/2` was never called must be a safe no-op that returns `:ok` — it must not exit or crash the calling process.
- After a successful cleanup, `clean/0` discards the stored strategy state, so a subsequent `clean/0` with no intervening `start/2` is itself a safe no-op that returns `:ok` and issues no further SQL.
- Every `start/2` call fully replaces any previously stored strategy state, so consecutive start/clean cycles in the same process never bleed into each other: a `:truncation` cycle followed by a `:transaction` cycle must not produce any `TRUNCATE` query during the second cycle's `clean/0`.
- Calling `start/2` with any strategy other than `:transaction` or `:truncation` does not raise: it returns `{:error, message}` where `message` is a String describing the problem.
- If the `repo.begin_transaction()` call raises, `start/2` rescues the exception and returns `{:error, message}` where `message` is the exception's message String (as produced by `Exception.message/1`); the exception must not propagate to the caller.
- If `repo.rollback()` (`:transaction`) or `repo.query!/3` (`:truncation`) raises during `clean/0`, the exception is rescued and `clean/0` returns `{:error, message}` where `message` is the exception's message String.

## Deliverable

The complete module, in a single file.
