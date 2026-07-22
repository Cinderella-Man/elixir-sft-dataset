# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir module called `DBCleaner` that ensures database isolation between integration tests by cleaning up state between test runs.

I need these functions in the public API:
- `DBCleaner.start(strategy, opts \\ [])` — called in a test's `setup` block. The `strategy` is either `:transaction` or `:truncation`. The `opts` keyword list should accept a `:repo` key (an Ecto repo module, e.g. `MyApp.Repo`) and a `:tables` key (a list of table name strings to truncate, e.g. `["users", "posts"]`). Store whatever state is needed to clean up later.
- `DBCleaner.clean()` — called in `on_exit`. Performs the actual cleanup based on whichever strategy was started.

Implement two strategies:

**`:transaction`** — In `start/2`, begin a database transaction (using `Ecto.Adapters.SQL.begin_transaction/1` or equivalent) and store the connection/transaction reference in the process dictionary or a named Agent. In `clean/0`, roll back that transaction so no data persists. This strategy is fast but only works with synchronous tests (`async: false`).

**`:truncation`** — `start/2` performs no database work: it only validates the table names and stashes the `:repo` and `:tables` options in the process dictionary so `clean/0` can retrieve them. In `clean/0`, issue a `TRUNCATE <table> RESTART IDENTITY CASCADE` SQL command for every table listed in `:tables`, executed via `Ecto.Adapters.SQL.query!/3`. This strategy is slower but works with any test configuration.

Both strategies should be entirely self-contained in a single file with no external dependencies beyond Ecto. Use the process dictionary (`Process.put/get`) to carry state between `start/2` and `clean/0` so no extra process is required.

Give me the complete module in a single file.

## Additional interface contract

- Under the `:truncation` strategy, `clean/0` issues exactly one SQL statement per listed table (never a single combined multi-table `TRUNCATE`), each of the exact form `TRUNCATE <table> RESTART IDENTITY CASCADE` with the bare, unquoted table name. Execute it by calling `query!/3` on the configured repo module itself — `repo.query!(repo, sql, [])` — rather than referencing `Ecto.Adapters.SQL` directly, so a stand-in repo module that defines `query!/3` receives one call per table.
- The same stand-in-repo rule applies to the `:transaction` strategy: `start/2` must begin the transaction eagerly, during `start/2` itself (not deferred to `clean/0`), by calling `begin_transaction/0` with no arguments on the configured repo module — `repo.begin_transaction()`. Do not call `Ecto.Adapters.SQL.begin_transaction(repo)`, `repo.transaction/1`, `repo.checkout/1`, or anything that touches `get_dynamic_repo/0`; the "`Ecto.Adapters.SQL.begin_transaction/1` or equivalent" wording above means the repo-module call is the required equivalent here. The call returns `{:ok, ref}` — the ref may be stored or simply discarded.
- Under the `:transaction` strategy, `clean/0` rolls back by calling `rollback/0` with no arguments on the repo module — `repo.rollback()` — and must issue no SQL at all via `query!/3`. The `:tables` option is accepted but ignored entirely by this strategy: no `TRUNCATE` statement may be issued even when tables were passed to `start/2`.
- `clean/0` when `start/2` was never called must be a safe no-op that returns `:ok` — it must not exit or crash the calling process.
- Every `start/2` call fully replaces any previously stored strategy state, so consecutive start/clean cycles in the same process never bleed into each other: a `:truncation` cycle followed by a `:transaction` cycle must not produce any `TRUNCATE` query during the second cycle's `clean/0`.
- `start/2` returns exactly `{:ok, :transaction}` when the `:transaction` strategy starts successfully, and exactly `{:ok, :truncation}` when the `:truncation` strategy starts successfully.
- Calling `start/2` with any strategy other than `:transaction` or `:truncation` does not raise: it returns `{:error, message}` where `message` is a String describing the problem.
- If the `repo.begin_transaction()` call raises, `start/2` rescues the exception and returns `{:error, message}` where `message` is the exception's message String (as produced by `Exception.message/1`); the exception must not propagate to the caller.
- `clean/0` returns exactly `:ok` after a successful cleanup under both strategies. If `repo.rollback()` (`:transaction`) or `repo.query!/3` (`:truncation`) raises during `clean/0`, the exception is rescued and `clean/0` returns `{:error, message}` where `message` is the exception's message String.

## Module under test

```elixir
defmodule DBCleaner do
  @moduledoc """
  Ensures database isolation between integration tests by cleaning up state
  between test runs.

  ## Strategies

  ### `:transaction`
  Wraps each test in a database transaction that is rolled back in `clean/0`.
  Fast and zero-footprint, but requires `async: false` because all test
  interactions must share the single checked-out connection.

  `start/2` calls `repo.begin_transaction/0` on the given repo module.
  `clean/0` calls `repo.rollback/0`.

  ### `:truncation`
  Does no setup work. `clean/0` issues a
  `TRUNCATE <table> RESTART IDENTITY CASCADE` for every table listed in
  `:tables` by calling `repo.query!(repo, sql, [])`.
  Works with any test configuration but is slower due to WAL writes and
  sequence resets.

  ## Usage

      setup do
        {:ok, _} = DBCleaner.start(:transaction, repo: MyApp.Repo)
        # – or –
        {:ok, _} = DBCleaner.start(:truncation, repo: MyApp.Repo, tables: ["users", "posts"])

        on_exit(fn -> DBCleaner.clean() end)
        :ok
      end

  ## State

  All state is stored in the calling process's dictionary under the private key
  `{DBCleaner, :state}`, so no Agent or extra process is required.

  Every `start/2` call discards any previously registered state *before* doing
  any database work, so a failed start can never leave a stale strategy behind.
  """

  @state_key {__MODULE__, :state}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a cleaning strategy for the current test.

  Must be called from the test process (or a `setup` callback) so that the
  state ends up in the correct process dictionary.

  ## Options

    * `:repo`   – (required) the Ecto repo module, e.g. `MyApp.Repo`.
    * `:tables` – list of table-name strings to truncate when using the
                  `:truncation` strategy. Ignored by `:transaction`.

  Returns `{:ok, :transaction | :truncation}` on success, or
  `{:error, reason}` on failure. Any state registered by an earlier `start/2`
  is discarded first, even when this call ultimately fails.
  """
  @spec start(:transaction | :truncation, keyword()) ::
          {:ok, :transaction | :truncation} | {:error, term()}
  def start(strategy, opts \\ [])

  def start(:transaction, opts) do
    repo = fetch_repo!(opts)

    # Drop any prior registration before touching the database: if
    # begin_transaction/0 raises, no stale strategy may survive this call.
    clear_state()

    try do
      {:ok, _ref} = repo.begin_transaction()
      put_state(%{strategy: :transaction, repo: repo})
      {:ok, :transaction}
    rescue
      e ->
        clear_state()
        {:error, Exception.message(e)}
    end
  end

  def start(:truncation, opts) do
    repo = fetch_repo!(opts)
    tables = Keyword.get(opts, :tables, [])

    clear_state()
    validate_tables!(tables)

    put_state(%{strategy: :truncation, repo: repo, tables: tables})
    {:ok, :truncation}
  end

  def start(unknown, _opts) do
    {:error, "unknown strategy #{inspect(unknown)}. Expected :transaction or :truncation"}
  end

  @doc """
  Cleans up database state based on the strategy passed to `start/2`.

  Call this inside `on_exit/1` so it runs even when a test fails:

      on_exit(fn -> DBCleaner.clean() end)

  ## `:transaction`
  Calls `repo.rollback/0`, discarding every write made during the test.

  ## `:truncation`
  Calls `repo.query!(repo, sql, [])` with a
  `TRUNCATE <table> RESTART IDENTITY CASCADE` statement for every table
  registered in `start/2`.

  Returns `:ok` on success or `{:error, reason}` on failure.
  If `start/2` was never called the function is a safe no-op.
  """
  @spec clean() :: :ok | {:error, term()}
  def clean do
    case get_state() do
      nil -> :ok
      state -> do_clean(state)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers – strategy implementations
  # ---------------------------------------------------------------------------

  defp do_clean(%{strategy: :transaction, repo: repo}) do
    try do
      repo.rollback()
      clear_state()
      :ok
    rescue
      e ->
        clear_state()
        {:error, Exception.message(e)}
    end
  end

  defp do_clean(%{strategy: :truncation, repo: repo, tables: tables}) do
    try do
      Enum.each(tables, fn table ->
        # Table names are validated against a strict allowlist in start/2, so
        # interpolation here is safe — no parameterised query possible for
        # SQL identifiers.
        sql = "TRUNCATE #{table} RESTART IDENTITY CASCADE"
        repo.query!(repo, sql, [])
      end)

      clear_state()
      :ok
    rescue
      e ->
        clear_state()
        {:error, Exception.message(e)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers – validation
  # ---------------------------------------------------------------------------

  # Allows letters, digits, and underscores; must start with a letter or _.
  # Rejects anything that could be used to inject SQL via the table name.
  @valid_identifier ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  defp validate_tables!(tables) when is_list(tables) do
    Enum.each(tables, fn
      table when is_binary(table) ->
        unless Regex.match?(@valid_identifier, table) do
          raise ArgumentError,
                "invalid table name #{inspect(table)}. " <>
                  "Table names must match /[a-zA-Z_][a-zA-Z0-9_]*/"
        end

      other ->
        raise ArgumentError,
              "expected table names to be strings, got: #{inspect(other)}"
    end)
  end

  defp validate_tables!(other) do
    raise ArgumentError, "expected :tables to be a list, got: #{inspect(other)}"
  end

  defp fetch_repo!(opts) do
    case Keyword.fetch(opts, :repo) do
      {:ok, repo} when is_atom(repo) ->
        repo

      {:ok, other} ->
        raise ArgumentError,
              "expected :repo to be an atom (Ecto repo module), got: #{inspect(other)}"

      :error ->
        raise ArgumentError, ":repo is required. Pass repo: MyApp.Repo in opts"
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers – process-dictionary state management
  # ---------------------------------------------------------------------------

  defp put_state(state), do: Process.put(@state_key, state)
  defp get_state, do: Process.get(@state_key)
  defp clear_state, do: Process.delete(@state_key)
end
```
