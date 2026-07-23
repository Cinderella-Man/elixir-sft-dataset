# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

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

## New specification

# `DBCleaner` — savepoint-based nested rollback control for integration tests

Implement an Elixir module `DBCleaner` providing **fine-grained, nested** rollback control for integration tests, using SQL savepoints layered on top of a single outer transaction. The base "transaction" cleaner can only roll back the whole test; this variant must allow, within one test, opening named savepoints, rolling back to a specific savepoint (undoing only writes made after it), releasing savepoints, and discarding everything at test end.

**`DBCleaner.start(:savepoint, opts \\ [])`**
- Called from a test's `setup` block.
- `opts` must include a `:repo` key (an Ecto repo module, e.g. `MyApp.Repo`).
- Begins an outer database transaction via `repo.begin_transaction/0`.
- Initializes an empty savepoint stack.
- Stores all state in the calling process's dictionary.
- Returns `{:ok, :savepoint}`.

**`DBCleaner.savepoint(name)`**
- Issues `SAVEPOINT <name>` via `repo.query!(repo, sql, [])`.
- Pushes `name` onto the stack.
- `name` must be a valid SQL identifier string (`/[a-zA-Z_][a-zA-Z0-9_]*/`).
- Returns `{:ok, name}`.
- Returns `{:error, :not_started}` if `start/2` was never called.
- Returns `{:error, {:invalid_name, name}}` for a bad identifier.

**`DBCleaner.rollback_to(name)`**
- Issues `ROLLBACK TO SAVEPOINT <name>`.
- Per SQL semantics the savepoint itself survives while every savepoint created **after** it is discarded; trim the stack to keep `name` and everything older.
- Returns `{:ok, name}`.
- Returns `{:error, {:no_such_savepoint, name}}` if `name` isn't on the stack.

**`DBCleaner.release(name)`**
- Issues `RELEASE SAVEPOINT <name>`, releasing that savepoint and all savepoints created after it; pop them off the stack.
- Returns `{:ok, name}`.
- Returns `{:error, {:no_such_savepoint, name}}`.

**`DBCleaner.active_savepoints()`**
- Returns the list of currently-active savepoint names, oldest first.

**`DBCleaner.clean()`**
- Called from `on_exit`.
- Rolls back the outer transaction via `repo.rollback/0`, discarding all test writes, and clears state.
- Safe no-op if `start/2` was never called.

**Implementation constraints**
- Everything self-contained in a single file.
- No dependencies beyond Ecto.
- Use the process dictionary (`Process.put/get`) to carry state between calls, so no extra process is required.
- Guard against SQL injection through savepoint names by validating identifiers.

**Deliverable**
- The complete module in a single file.
