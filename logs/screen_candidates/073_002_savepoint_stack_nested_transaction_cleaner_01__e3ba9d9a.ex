defmodule DBCleaner do
  @moduledoc """
  Fine-grained, nested rollback control for integration tests using SQL savepoints.

  The `:savepoint` strategy wraps each test in a single outer database transaction and
  layers named SQL savepoints on top of it. Within one test you can:

    * open a named savepoint with `savepoint/1`;
    * undo only the writes made after a savepoint with `rollback_to/1`;
    * release a savepoint (and everything nested inside it) with `release/1`;
    * discard the whole test's writes with `clean/0`.

  All state lives in the calling process's dictionary, so no extra process is required.
  This means every call must happen in the same process that called `start/2` — which is
  the normal case for ExUnit `setup` / test body / `on_exit` running in the test process.

  ## Usage

      setup do
        {:ok, :savepoint} = DBCleaner.start(:savepoint, repo: MyApp.Repo)
        on_exit(&DBCleaner.clean/0)
        :ok
      end

      test "nested rollback" do
        {:ok, _} = DBCleaner.savepoint("before_users")
        MyApp.Repo.insert!(%User{name: "alice"})
        {:ok, _} = DBCleaner.rollback_to("before_users")
        # the insert is gone, but "before_users" is still active
        assert DBCleaner.active_savepoints() == ["before_users"]
      end

  ## Safety

  Savepoint names are interpolated into SQL, because SQL does not allow bind parameters
  for identifiers. Every name is therefore validated against `/[a-zA-Z_][a-zA-Z0-9_]*/`
  before it reaches the database, which rules out injection through the name.
  """

  @strategy_key {__MODULE__, :strategy}
  @repo_key {__MODULE__, :repo}
  @stack_key {__MODULE__, :stack}

  @identifier_regex ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  @typedoc "The cleaning strategy. Only `:savepoint` is supported by this module."
  @type strategy :: :savepoint

  @typedoc "A savepoint name; must be a valid SQL identifier."
  @type name :: String.t()

  @doc """
  Starts the savepoint cleaner for the calling process.

  Opens an outer transaction on the configured repo via `repo.begin_transaction/0` and
  initializes an empty savepoint stack. Intended to be called from a test's `setup` block.

  ## Options

    * `:repo` — required; the `Ecto.Repo` module to run the transaction against.

  Returns `{:ok, :savepoint}`.

  Raises `ArgumentError` if `:repo` is missing.
  """
  @spec start(strategy(), keyword()) :: {:ok, strategy()}
  def start(:savepoint, opts \\ []) do
    repo =
      case Keyword.fetch(opts, :repo) do
        {:ok, repo} when is_atom(repo) and not is_nil(repo) ->
          repo

        _other ->
          raise ArgumentError,
                "DBCleaner.start/2 requires a `:repo` option pointing at an Ecto repo module"
      end

    repo.begin_transaction()

    Process.put(@strategy_key, :savepoint)
    Process.put(@repo_key, repo)
    Process.put(@stack_key, [])

    {:ok, :savepoint}
  end

  @doc """
  Opens a new savepoint called `name` and pushes it onto the savepoint stack.

  Returns `{:ok, name}` on success, `{:error, :not_started}` when `start/2` was never
  called in this process, or `{:error, {:invalid_name, name}}` when `name` is not a valid
  SQL identifier.
  """
  @spec savepoint(name()) ::
          {:ok, name()} | {:error, :not_started} | {:error, {:invalid_name, term()}}
  def savepoint(name) do
    with {:ok, repo} <- fetch_repo(),
         :ok <- validate_name(name) do
      query!(repo, "SAVEPOINT #{name}")
      Process.put(@stack_key, stack() ++ [name])
      {:ok, name}
    end
  end

  @doc """
  Rolls back to the savepoint called `name`, undoing every write made after it.

  Per SQL semantics the savepoint itself survives the rollback and stays active, while
  every savepoint created after it is discarded; the stack is trimmed to match.

  Returns `{:ok, name}`, `{:error, :not_started}`, `{:error, {:invalid_name, name}}`, or
  `{:error, {:no_such_savepoint, name}}` when `name` is not currently active.
  """
  @spec rollback_to(name()) ::
          {:ok, name()}
          | {:error, :not_started}
          | {:error, {:invalid_name, term()}}
          | {:error, {:no_such_savepoint, name()}}
  def rollback_to(name) do
    with {:ok, repo} <- fetch_repo(),
         :ok <- validate_name(name),
         {:ok, index} <- find_index(name) do
      query!(repo, "ROLLBACK TO SAVEPOINT #{name}")
      Process.put(@stack_key, Enum.take(stack(), index + 1))
      {:ok, name}
    end
  end

  @doc """
  Releases the savepoint called `name` along with every savepoint created after it.

  Writes made since the savepoint are kept (they become part of the enclosing savepoint
  or the outer transaction); only the savepoint markers go away.

  Returns `{:ok, name}`, `{:error, :not_started}`, `{:error, {:invalid_name, name}}`, or
  `{:error, {:no_such_savepoint, name}}` when `name` is not currently active.
  """
  @spec release(name()) ::
          {:ok, name()}
          | {:error, :not_started}
          | {:error, {:invalid_name, term()}}
          | {:error, {:no_such_savepoint, name()}}
  def release(name) do
    with {:ok, repo} <- fetch_repo(),
         :ok <- validate_name(name),
         {:ok, index} <- find_index(name) do
      query!(repo, "RELEASE SAVEPOINT #{name}")
      Process.put(@stack_key, Enum.take(stack(), index))
      {:ok, name}
    end
  end

  @doc """
  Returns the currently-active savepoint names, oldest first.

  Returns an empty list when `start/2` was never called or no savepoints are open.
  """
  @spec active_savepoints() :: [name()]
  def active_savepoints, do: stack()

  @doc """
  Rolls back the outer transaction, discarding every write made during the test, and
  clears all cleaner state from the process dictionary.

  Intended to be called from `on_exit`. This is a safe no-op when `start/2` was never
  called in this process.
  """
  @spec clean() :: :ok
  def clean do
    case Process.get(@repo_key) do
      nil -> :ok
      repo -> repo.rollback()
    end

    Process.delete(@strategy_key)
    Process.delete(@repo_key)
    Process.delete(@stack_key)

    :ok
  end

  ## Internal helpers

  @spec fetch_repo() :: {:ok, module()} | {:error, :not_started}
  defp fetch_repo do
    case Process.get(@repo_key) do
      nil -> {:error, :not_started}
      repo -> {:ok, repo}
    end
  end

  @spec stack() :: [name()]
  defp stack, do: Process.get(@stack_key) || []

  @spec validate_name(term()) :: :ok | {:error, {:invalid_name, term()}}
  defp validate_name(name) when is_binary(name) do
    if Regex.match?(@identifier_regex, name) do
      :ok
    else
      {:error, {:invalid_name, name}}
    end
  end

  defp validate_name(name), do: {:error, {:invalid_name, name}}

  @spec find_index(name()) :: {:ok, non_neg_integer()} | {:error, {:no_such_savepoint, name()}}
  defp find_index(name) do
    case Enum.find_index(stack(), &(&1 == name)) do
      nil -> {:error, {:no_such_savepoint, name}}
      index -> {:ok, index}
    end
  end

  @spec query!(module(), String.t()) :: term()
  defp query!(repo, sql), do: repo.query!(repo, sql, [])
end