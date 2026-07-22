# Task: Implement `validate_tables!/1`

Implement the private `validate_tables!/1` function for the `DBCleaner` module below.

This function guards the `:truncation` strategy against SQL injection through table
names. Because table names are SQL identifiers, they cannot be passed as query
parameters and are interpolated directly into the `TRUNCATE` statement — so every
name must be validated up front.

`validate_tables!/1` must:

- Accept the `:tables` value passed to `start/2`. When it is **not a list**, raise an
  `ArgumentError` explaining that `:tables` must be a list and showing the offending
  value via `inspect/1`.
- When it **is a list**, check every element:
  - A **binary** table name must match the module attribute `@valid_identifier`
    (`~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/`). If it does not match, raise an `ArgumentError`
    naming the invalid table (via `inspect/1`) and stating that names must match
    `/[a-zA-Z_][a-zA-Z0-9_]*/`.
  - A **non-binary** element must raise an `ArgumentError` explaining that table names
    are expected to be strings and showing the offending value via `inspect/1`.
- Return value is unimportant (it is called only for its validating side effect); on
  success it should simply finish without raising.

The function is used only for its side effect: `start(:truncation, ...)` calls
`validate_tables!(tables)` before storing state, so any bad input aborts the setup
with a clear error.

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
  `{:error, reason}` on failure.
  """
  @spec start(:transaction | :truncation, keyword()) ::
          {:ok, :transaction | :truncation} | {:error, term()}
  def start(strategy, opts \\ [])

  def start(:transaction, opts) do
    repo = fetch_repo!(opts)

    try do
      {:ok, _ref} = repo.begin_transaction()
      put_state(%{strategy: :transaction, repo: repo})
      {:ok, :transaction}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  def start(:truncation, opts) do
    repo   = fetch_repo!(opts)
    tables = Keyword.get(opts, :tables, [])

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
      nil   -> :ok
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

  defp validate_tables!(tables) do
    # TODO
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
  defp get_state,        do: Process.get(@state_key)
  defp clear_state,      do: Process.delete(@state_key)
end
```