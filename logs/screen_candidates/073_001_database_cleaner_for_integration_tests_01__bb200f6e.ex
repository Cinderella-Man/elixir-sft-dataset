defmodule DBCleaner do
  @moduledoc """
  Ensures database isolation between integration tests by cleaning up state
  between test runs.

  `DBCleaner` supports two strategies for keeping the database clean:

    * `:transaction` — begins a database transaction in `start/2` and rolls it
      back in `clean/0`, so no data written during the test persists. This is
      fast but only works with synchronous tests (`async: false`).

    * `:truncation` — performs no database work in `start/2` (it only validates
      and stashes the table names), then issues a
      `TRUNCATE <table> RESTART IDENTITY CASCADE` statement for every configured
      table in `clean/0`. This is slower but works with any test configuration.

  State is carried between `start/2` and `clean/0` using the process dictionary,
  so no extra process is required. Each `start/2` call fully replaces any
  previously stored state, so consecutive start/clean cycles in the same process
  never bleed into each other.
  """

  @typedoc "The supported cleanup strategies."
  @type strategy :: :transaction | :truncation

  @state_key :db_cleaner_state

  @doc """
  Begins a cleanup cycle for the given `strategy`.

  Intended to be called in a test's `setup` block. The `opts` keyword list
  accepts:

    * `:repo` — an Ecto repo module (e.g. `MyApp.Repo`).
    * `:tables` — a list of table name strings to truncate
      (e.g. `["users", "posts"]`), used only by the `:truncation` strategy.

  For `:transaction`, a database transaction is begun eagerly (during this call)
  by invoking `repo.begin_transaction()`.

  For `:truncation`, no database work is performed; the table names are validated
  and the options are stashed for later use by `clean/0`.

  Any previously stored strategy state is fully replaced.
  """
  @spec start(strategy(), keyword()) :: :ok
  def start(strategy, opts \\ [])

  def start(:transaction, opts) do
    repo = Keyword.fetch!(opts, :repo)
    {:ok, _ref} = repo.begin_transaction()
    Process.put(@state_key, %{strategy: :transaction, repo: repo})
    :ok
  end

  def start(:truncation, opts) do
    repo = Keyword.fetch!(opts, :repo)
    tables = validate_tables(Keyword.get(opts, :tables, []))
    Process.put(@state_key, %{strategy: :truncation, repo: repo, tables: tables})
    :ok
  end

  @doc """
  Performs the cleanup for whichever strategy was started.

  Intended to be called from `on_exit`.

    * `:transaction` — rolls back the transaction begun in `start/2` by calling
      `repo.rollback()`. No SQL is issued and the `:tables` option is ignored.

    * `:truncation` — issues exactly one
      `TRUNCATE <table> RESTART IDENTITY CASCADE` statement per configured table
      via `repo.query!(repo, sql, [])`.

  If `start/2` was never called, this is a safe no-op that returns `:ok`.
  """
  @spec clean() :: :ok
  def clean do
    case Process.get(@state_key) do
      %{strategy: :transaction, repo: repo} ->
        repo.rollback()
        Process.delete(@state_key)
        :ok

      %{strategy: :truncation, repo: repo, tables: tables} ->
        Enum.each(tables, fn table ->
          sql = "TRUNCATE #{table} RESTART IDENTITY CASCADE"
          repo.query!(repo, sql, [])
        end)

        Process.delete(@state_key)
        :ok

      _other ->
        :ok
    end
  end

  @spec validate_tables(list()) :: [String.t()]
  defp validate_tables(tables) when is_list(tables) do
    Enum.map(tables, fn
      table when is_binary(table) and byte_size(table) > 0 ->
        table

      other ->
        raise ArgumentError,
              "expected table names to be non-empty strings, got: #{inspect(other)}"
    end)
  end
end