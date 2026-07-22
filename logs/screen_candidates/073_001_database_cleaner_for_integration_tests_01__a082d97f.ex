defmodule DBCleaner do
  @moduledoc """
  Database isolation helper for integration tests.

  `DBCleaner` keeps test runs from leaking state into one another. A test's
  `setup` block calls `start/2` with a strategy, and the matching `on_exit`
  callback calls `clean/0` to undo whatever the test wrote.

  Two strategies are supported:

    * `:transaction` — a database transaction is opened eagerly in `start/2`
      and rolled back in `clean/0`, so nothing the test wrote is ever
      committed. This is the fast path, but it requires synchronous tests
      (`async: false`) because the transaction is bound to a single
      connection.

    * `:truncation` — `start/2` performs no database work at all; it merely
      validates the requested table names. `clean/0` then issues one
      `TRUNCATE <table> RESTART IDENTITY CASCADE` statement per table. This
      is slower, but works with any test configuration.

  All state travels between `start/2` and `clean/0` through the process
  dictionary, so no supervisor, Agent, or other extra process is needed. Each
  `start/2` call fully replaces any previously stored state, which means
  consecutive start/clean cycles in the same process cannot bleed into one
  another.

  ## Example

      setup do
        {:ok, :truncation} =
          DBCleaner.start(:truncation, repo: MyApp.Repo, tables: ["users", "posts"])

        on_exit(&DBCleaner.clean/0)
        :ok
      end

  """

  @state_key :db_cleaner_state

  @typedoc "The isolation strategy to use for a test."
  @type strategy :: :transaction | :truncation

  @typedoc "Return value of `start/2`."
  @type start_result :: {:ok, strategy()} | {:error, String.t()}

  @typedoc "Return value of `clean/0`."
  @type clean_result :: :ok | {:error, String.t()}

  @doc """
  Starts database isolation for the current test process.

  `strategy` must be either `:transaction` or `:truncation`. `opts` accepts:

    * `:repo` — the Ecto repo module to operate on (required).
    * `:tables` — a list of table name strings. Required (and validated) for
      the `:truncation` strategy; accepted but completely ignored by the
      `:transaction` strategy.

  For `:transaction`, the transaction is begun immediately by calling
  `repo.begin_transaction()`. For `:truncation`, no database work happens
  here — the options are simply validated and stashed for `clean/0`.

  Returns `{:ok, strategy}` on success. Any problem — an unknown strategy,
  missing or malformed options, or an exception raised while beginning the
  transaction — is reported as `{:error, message}` rather than raised.

  ## Examples

      iex> DBCleaner.start(:teleportation, repo: MyApp.Repo)
      {:error, "unknown strategy :teleportation, expected :transaction or :truncation"}

  """
  @spec start(strategy() | any(), keyword()) :: start_result()
  def start(strategy, opts \\ [])

  def start(:transaction, opts) do
    clear_state()

    with {:ok, repo} <- fetch_repo(opts),
         {:ok, _ref} <- begin_transaction(repo) do
      put_state(%{strategy: :transaction, repo: repo})
      {:ok, :transaction}
    end
  end

  def start(:truncation, opts) do
    clear_state()

    with {:ok, repo} <- fetch_repo(opts),
         {:ok, tables} <- fetch_tables(opts) do
      put_state(%{strategy: :truncation, repo: repo, tables: tables})
      {:ok, :truncation}
    end
  end

  def start(strategy, _opts) do
    clear_state()

    {:error,
     "unknown strategy #{inspect(strategy)}, expected :transaction or :truncation"}
  end

  @doc """
  Cleans up the database state created since the matching `start/2` call.

  Under the `:transaction` strategy this rolls the open transaction back via
  `repo.rollback()` and issues no SQL of its own. Under the `:truncation`
  strategy it issues exactly one

      TRUNCATE <table> RESTART IDENTITY CASCADE

  statement per configured table, through `repo.query!/3`.

  Calling `clean/0` without a preceding successful `start/2` is a safe no-op
  that returns `:ok`. The stored state is always discarded, so a second call
  never repeats the cleanup.

  Returns `:ok` on success, or `{:error, message}` if the underlying repo call
  raised — the exception is rescued rather than propagated.

  ## Examples

      iex> DBCleaner.clean()
      :ok

  """
  @spec clean() :: clean_result()
  def clean do
    case take_state() do
      %{strategy: :transaction, repo: repo} -> rollback(repo)
      %{strategy: :truncation, repo: repo, tables: tables} -> truncate(repo, tables)
      nil -> :ok
    end
  end

  # -- Strategy implementations ---------------------------------------------

  @spec begin_transaction(module()) :: {:ok, any()} | {:error, String.t()}
  defp begin_transaction(repo) do
    case repo.begin_transaction() do
      {:ok, ref} -> {:ok, ref}
      other -> {:ok, other}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @spec rollback(module()) :: clean_result()
  defp rollback(repo) do
    _ = repo.rollback()
    :ok
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @spec truncate(module(), [String.t()]) :: clean_result()
  defp truncate(repo, tables) do
    Enum.each(tables, fn table ->
      repo.query!(repo, "TRUNCATE #{table} RESTART IDENTITY CASCADE", [])
    end)

    :ok
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  # -- Option validation ----------------------------------------------------

  @spec fetch_repo(keyword()) :: {:ok, module()} | {:error, String.t()}
  defp fetch_repo(opts) when is_list(opts) do
    case Keyword.get(opts, :repo) do
      repo when is_atom(repo) and not is_nil(repo) -> {:ok, repo}
      nil -> {:error, "missing required option :repo (an Ecto repo module)"}
      other -> {:error, "invalid :repo option #{inspect(other)}, expected a module"}
    end
  end

  defp fetch_repo(other) do
    {:error, "invalid options #{inspect(other)}, expected a keyword list"}
  end

  @spec fetch_tables(keyword()) :: {:ok, [String.t()]} | {:error, String.t()}
  defp fetch_tables(opts) do
    case Keyword.get(opts, :tables) do
      tables when is_list(tables) -> validate_tables(tables)
      nil -> {:error, "missing required option :tables for the :truncation strategy"}
      other -> {:error, "invalid :tables option #{inspect(other)}, expected a list"}
    end
  end

  @spec validate_tables([any()]) :: {:ok, [String.t()]} | {:error, String.t()}
  defp validate_tables(tables) do
    case Enum.reject(tables, &valid_table_name?/1) do
      [] -> {:ok, tables}
      [bad | _] -> {:error, "invalid table name #{inspect(bad)}, expected a table name string"}
    end
  end

  @spec valid_table_name?(any()) :: boolean()
  defp valid_table_name?(table) when is_binary(table) do
    table != "" and Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_$]*(\.[A-Za-z_][A-Za-z0-9_$]*)?$/, table)
  end

  defp valid_table_name?(_table), do: false

  # -- Process dictionary state ---------------------------------------------

  @spec put_state(map()) :: :ok
  defp put_state(state) do
    Process.put(@state_key, state)
    :ok
  end

  @spec take_state() :: map() | nil
  defp take_state do
    Process.delete(@state_key)
  end

  @spec clear_state() :: :ok
  defp clear_state do
    Process.delete(@state_key)
    :ok
  end
end