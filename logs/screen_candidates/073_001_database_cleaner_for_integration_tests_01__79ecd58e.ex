defmodule DBCleaner do
  @moduledoc """
  Ensures database isolation between integration tests by cleaning up state
  between test runs.

  `DBCleaner` supports two cleanup strategies:

    * `:transaction` — wraps the test in a database transaction that is rolled
      back during cleanup, so no data persists. This strategy is fast but only
      works with synchronous tests (`async: false`).

    * `:truncation` — issues a `TRUNCATE ... RESTART IDENTITY CASCADE` command
      for each configured table during cleanup. This strategy is slower but
      works with any test configuration.

  Typical usage inside an `ExUnit` test module:

      setup do
        DBCleaner.start(:transaction, repo: MyApp.Repo)
        on_exit(fn -> DBCleaner.clean() end)
        :ok
      end

  State is carried between `start/2` and `clean/0` using the process
  dictionary, so no additional process is required.
  """

  @typedoc "Supported cleanup strategies."
  @type strategy :: :transaction | :truncation

  @state_key :db_cleaner_state

  @doc """
  Prepares database cleanup for the given `strategy`.

  Should be called inside a test's `setup` block. The `opts` keyword list
  accepts:

    * `:repo` — an `Ecto` repo module (e.g. `MyApp.Repo`). Required.
    * `:tables` — a list of table name strings to truncate (e.g.
      `["users", "posts"]`). Required for the `:truncation` strategy.

  For `:transaction`, a database transaction is started immediately and its
  reference is stashed for later rollback. For `:truncation`, no database work
  is performed; the table names are validated and the options are stashed for
  use in `clean/0`.
  """
  @spec start(strategy(), keyword()) :: :ok
  def start(strategy, opts \\ [])

  def start(:transaction, opts) do
    repo = fetch_repo!(opts)
    tx = Ecto.Adapters.SQL.begin_transaction(repo)
    Process.put(@state_key, {:transaction, repo, tx})
    :ok
  end

  def start(:truncation, opts) do
    repo = fetch_repo!(opts)
    tables = fetch_tables!(opts)
    Process.put(@state_key, {:truncation, repo, tables})
    :ok
  end

  @doc """
  Performs the cleanup configured by the most recent call to `start/2`.

  Should be called inside `on_exit`. For the `:transaction` strategy, the
  transaction started in `start/2` is rolled back so no data persists. For the
  `:truncation` strategy, a `TRUNCATE <table> RESTART IDENTITY CASCADE`
  statement is executed for every configured table.

  Returns `:ok`. If `start/2` was never called, this is a no-op.
  """
  @spec clean() :: :ok
  def clean do
    case Process.get(@state_key) do
      {:transaction, repo, tx} ->
        Ecto.Adapters.SQL.rollback_transaction(repo, tx)
        Process.delete(@state_key)
        :ok

      {:truncation, repo, tables} ->
        Enum.each(tables, fn table ->
          Ecto.Adapters.SQL.query!(
            repo,
            "TRUNCATE #{table} RESTART IDENTITY CASCADE",
            []
          )
        end)

        Process.delete(@state_key)
        :ok

      nil ->
        :ok
    end
  end

  @spec fetch_repo!(keyword()) :: module()
  defp fetch_repo!(opts) do
    case Keyword.fetch(opts, :repo) do
      {:ok, repo} when is_atom(repo) ->
        repo

      _other ->
        raise ArgumentError, "expected a :repo module in opts, got: #{inspect(opts)}"
    end
  end

  @spec fetch_tables!(keyword()) :: [String.t()]
  defp fetch_tables!(opts) do
    case Keyword.fetch(opts, :tables) do
      {:ok, tables} when is_list(tables) ->
        Enum.each(tables, &validate_table!/1)
        tables

      _other ->
        raise ArgumentError,
              "expected a :tables list of strings in opts, got: #{inspect(opts)}"
    end
  end

  @spec validate_table!(term()) :: :ok
  defp validate_table!(table) when is_binary(table) do
    if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_.]*\z/, table) do
      :ok
    else
      raise ArgumentError, "invalid table name: #{inspect(table)}"
    end
  end

  defp validate_table!(table) do
    raise ArgumentError, "expected a table name string, got: #{inspect(table)}"
  end
end