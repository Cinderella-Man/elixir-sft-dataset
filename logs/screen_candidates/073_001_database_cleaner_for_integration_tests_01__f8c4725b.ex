defmodule DBCleaner do
  @moduledoc """
  Database isolation helper for integration tests.

  `DBCleaner` cleans up database state between test runs using one of two
  strategies:

    * `:transaction` — wraps the test in a database transaction that is rolled
      back during cleanup. Fast, but only safe for synchronous tests
      (`async: false`).

    * `:truncation` — issues a `TRUNCATE ... RESTART IDENTITY CASCADE` statement
      for each configured table during cleanup. Slower, but works with any test
      configuration.

  State is carried between `start/2` and `clean/0` through the process
  dictionary, so no extra process is required.

  ## Example

      setup do
        DBCleaner.start(:truncation, repo: MyApp.Repo, tables: ["users", "posts"])
        on_exit(&DBCleaner.clean/0)
      end
  """

  @state_key {__MODULE__, :state}

  @typedoc "Supported cleanup strategies."
  @type strategy :: :transaction | :truncation

  @doc """
  Starts a cleanup strategy for the current process.

  Accepts `:repo` (an Ecto repo module) and `:tables` (a list of table name
  strings). The `:tables` option is only meaningful for the `:truncation`
  strategy; it is accepted but ignored by `:transaction`.

  For `:transaction`, the transaction is begun eagerly by calling
  `repo.begin_transaction()`. For `:truncation`, no database work is performed.

  Returns `{:ok, strategy}` on success, or `{:error, message}` if the strategy
  is unknown, the options are invalid, or beginning the transaction raised.
  Any previously stored state is replaced.
  """
  @spec start(strategy() | atom(), keyword()) :: {:ok, strategy()} | {:error, String.t()}
  def start(strategy, opts \\ [])

  def start(:transaction, opts) do
    Process.delete(@state_key)

    with {:ok, repo} <- fetch_repo(opts) do
      try do
        repo.begin_transaction()
      rescue
        exception -> {:error, Exception.message(exception)}
      else
        _result ->
          Process.put(@state_key, %{strategy: :transaction, repo: repo})
          {:ok, :transaction}
      end
    end
  end

  def start(:truncation, opts) do
    Process.delete(@state_key)

    with {:ok, repo} <- fetch_repo(opts),
         {:ok, tables} <- fetch_tables(opts) do
      Process.put(@state_key, %{strategy: :truncation, repo: repo, tables: tables})
      {:ok, :truncation}
    end
  end

  def start(other, _opts) do
    Process.delete(@state_key)
    {:error, "unknown strategy: #{inspect(other)}, expected :transaction or :truncation"}
  end

  @doc """
  Performs the cleanup for the strategy started by `start/2`.

  For `:transaction`, calls `repo.rollback()` and issues no SQL. For
  `:truncation`, issues exactly one `TRUNCATE <table> RESTART IDENTITY CASCADE`
  statement per configured table via `repo.query!/3`.

  The stored state is discarded once cleanup succeeds, so calling `clean/0`
  again without an intervening `start/2` is a safe no-op. Calling `clean/0`
  when `start/2` was never called is also a safe no-op.

  Returns `:ok` on success, or `{:error, message}` if the database call raised.
  """
  @spec clean() :: :ok | {:error, String.t()}
  def clean do
    case Process.get(@state_key) do
      nil -> :ok
      state -> do_clean(state)
    end
  end

  @spec do_clean(map()) :: :ok | {:error, String.t()}
  defp do_clean(%{strategy: :transaction, repo: repo}) do
    repo.rollback()
  rescue
    exception -> {:error, Exception.message(exception)}
  else
    _result ->
      Process.delete(@state_key)
      :ok
  end

  defp do_clean(%{strategy: :truncation, repo: repo, tables: tables}) do
    Enum.each(tables, fn table ->
      repo.query!(repo, "TRUNCATE #{table} RESTART IDENTITY CASCADE", [])
    end)
  rescue
    exception -> {:error, Exception.message(exception)}
  else
    _result ->
      Process.delete(@state_key)
      :ok
  end

  @spec fetch_repo(keyword()) :: {:ok, module()} | {:error, String.t()}
  defp fetch_repo(opts) do
    case Keyword.get(opts, :repo) do
      repo when is_atom(repo) and not is_nil(repo) -> {:ok, repo}
      nil -> {:error, "missing required option :repo"}
      other -> {:error, "invalid :repo option: #{inspect(other)}, expected a module"}
    end
  end

  @spec fetch_tables(keyword()) :: {:ok, [String.t()]} | {:error, String.t()}
  defp fetch_tables(opts) do
    tables = Keyword.get(opts, :tables, [])

    cond do
      not is_list(tables) ->
        {:error, "invalid :tables option: #{inspect(tables)}, expected a list of strings"}

      Enum.all?(tables, &valid_table_name?/1) ->
        {:ok, tables}

      true ->
        {:error, "invalid table name in :tables: #{inspect(tables)}"}
    end
  end

  @spec valid_table_name?(term()) :: boolean()
  defp valid_table_name?(table) when is_binary(table) do
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_$]*(\.[A-Za-z_][A-Za-z0-9_$]*)?$/, table)
  end

  defp valid_table_name?(_table), do: false
end