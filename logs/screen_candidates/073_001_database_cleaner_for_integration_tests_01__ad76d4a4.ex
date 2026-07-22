defmodule DBCleaner do
  @moduledoc """
  Ensures database isolation between integration tests by cleaning up state
  between runs.

  `DBCleaner` supports two cleanup strategies:

    * `:transaction` — begins a database transaction in `start/2` and rolls it
      back in `clean/0`, so any data written during the test is discarded. This
      is fast but only works with synchronous tests (`async: false`) because a
      single connection is checked out for the duration of the test.

    * `:truncation` — performs no database work in `start/2`; it merely validates
      and stashes the `:repo` and `:tables` options. In `clean/0` it issues a
      `TRUNCATE ... RESTART IDENTITY CASCADE` statement for each table. This is
      slower but works with any test configuration.

  State is carried between `start/2` and `clean/0` via the process dictionary,
  so no extra process is required. Typical usage:

      setup do
        DBCleaner.start(:truncation, repo: MyApp.Repo, tables: ["users", "posts"])
        on_exit(fn -> DBCleaner.clean() end)
      end
  """

  @state_key {__MODULE__, :state}

  @typedoc "The supported cleanup strategies."
  @type strategy :: :transaction | :truncation

  @doc """
  Prepares cleanup for the given `strategy`, storing whatever state `clean/0`
  needs in the process dictionary.

  Options:

    * `:repo` — an Ecto repo module (e.g. `MyApp.Repo`). Required.
    * `:tables` — a list of table name strings to truncate (only used by the
      `:truncation` strategy).

  For `:transaction`, a transaction is opened on the repo's connection and left
  open until `clean/0` rolls it back. For `:truncation`, no database work is
  done here; the table names are validated and stashed for later.
  """
  @spec start(strategy(), keyword()) :: :ok
  def start(strategy, opts \\ [])

  def start(:transaction, opts) do
    repo = fetch_repo!(opts)
    Ecto.Adapters.SQL.Sandbox.checkout(repo)
    Process.put(@state_key, {:transaction, repo})
    :ok
  end

  def start(:truncation, opts) do
    repo = fetch_repo!(opts)
    tables = validate_tables!(Keyword.get(opts, :tables, []))
    Process.put(@state_key, {:truncation, repo, tables})
    :ok
  end

  @doc """
  Performs the cleanup for the strategy previously configured via `start/2`.

  For `:transaction`, the open transaction is rolled back (the sandbox
  connection is checked back in), discarding any changes. For `:truncation`, a
  `TRUNCATE <table> RESTART IDENTITY CASCADE` statement is executed for each
  configured table.

  Returns `:ok`. If no strategy was started in this process, this is a no-op.
  """
  @spec clean() :: :ok
  def clean do
    case Process.get(@state_key) do
      {:transaction, repo} ->
        Ecto.Adapters.SQL.Sandbox.checkin(repo)
        Process.delete(@state_key)
        :ok

      {:truncation, repo, tables} ->
        Enum.each(tables, fn table ->
          repo.query!(repo, "TRUNCATE #{table} RESTART IDENTITY CASCADE", [])
        end)

        Process.delete(@state_key)
        :ok

      nil ->
        :ok
    end
  end

  @spec fetch_repo!(keyword()) :: module()
  defp fetch_repo!(opts) do
    case Keyword.get(opts, :repo) do
      repo when is_atom(repo) and not is_nil(repo) ->
        repo

      other ->
        raise ArgumentError,
              "expected :repo to be an Ecto repo module, got: #{inspect(other)}"
    end
  end

  @spec validate_tables!(term()) :: [String.t()]
  defp validate_tables!(tables) when is_list(tables) do
    Enum.each(tables, fn table ->
      unless is_binary(table) and table != "" do
        raise ArgumentError,
              "expected :tables to be a list of non-empty strings, got: #{inspect(table)}"
      end
    end)

    tables
  end

  defp validate_tables!(other) do
    raise ArgumentError,
          "expected :tables to be a list of strings, got: #{inspect(other)}"
  end
end