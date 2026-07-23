# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `fetch_repo!` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `fetch_repo!` missing

```elixir
defmodule DBCleaner do
  @moduledoc """
  Fine-grained integration-test cleaner built on SQL savepoints layered over a
  single outer transaction.

  `start/2` opens the outer transaction; `savepoint/1`, `rollback_to/1` and
  `release/1` manipulate a stack of named savepoints; `clean/0` rolls back the
  outer transaction, discarding everything.

  All state lives in the calling process's dictionary under
  `{DBCleaner, :state}`, so no extra process is required. Use `async: false`.
  """

  @state_key {__MODULE__, :state}
  @valid_identifier ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  @spec start(:savepoint, keyword()) :: {:ok, :savepoint} | {:error, term()}
  def start(strategy, opts \\ [])

  def start(:savepoint, opts) do
    repo = fetch_repo!(opts)

    try do
      {:ok, _ref} = repo.begin_transaction()
      put_state(%{repo: repo, stack: []})
      {:ok, :savepoint}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  def start(unknown, _opts) do
    {:error, "unknown strategy #{inspect(unknown)}. Expected :savepoint"}
  end

  @doc "Open a named savepoint; pushes it onto the stack."
  @spec savepoint(String.t()) :: {:ok, String.t()} | {:error, term()}
  def savepoint(name) when is_binary(name) do
    if Regex.match?(@valid_identifier, name) do
      case get_state() do
        nil ->
          {:error, :not_started}

        %{repo: repo, stack: stack} = state ->
          try do
            repo.query!(repo, "SAVEPOINT #{name}", [])
            put_state(%{state | stack: [name | stack]})
            {:ok, name}
          rescue
            e -> {:error, Exception.message(e)}
          end
      end
    else
      {:error, {:invalid_name, name}}
    end
  end

  def savepoint(other), do: {:error, {:invalid_name, other}}

  @doc """
  Roll back to `name`. The savepoint survives; every savepoint created after it
  is discarded from the stack.
  """
  @spec rollback_to(String.t()) :: {:ok, String.t()} | {:error, term()}
  def rollback_to(name) when is_binary(name) do
    case get_state() do
      nil ->
        {:error, :not_started}

      %{repo: repo, stack: stack} = state ->
        if name in stack do
          try do
            repo.query!(repo, "ROLLBACK TO SAVEPOINT #{name}", [])
            new_stack = Enum.drop_while(stack, fn n -> n != name end)
            put_state(%{state | stack: new_stack})
            {:ok, name}
          rescue
            e -> {:error, Exception.message(e)}
          end
        else
          {:error, {:no_such_savepoint, name}}
        end
    end
  end

  @doc "Release `name` and any savepoints created after it."
  @spec release(String.t()) :: {:ok, String.t()} | {:error, term()}
  def release(name) when is_binary(name) do
    case get_state() do
      nil ->
        {:error, :not_started}

      %{repo: repo, stack: stack} = state ->
        if name in stack do
          try do
            repo.query!(repo, "RELEASE SAVEPOINT #{name}", [])
            new_stack = stack |> Enum.drop_while(fn n -> n != name end) |> tl()
            put_state(%{state | stack: new_stack})
            {:ok, name}
          rescue
            e -> {:error, Exception.message(e)}
          end
        else
          {:error, {:no_such_savepoint, name}}
        end
    end
  end

  @doc "Currently-active savepoint names, oldest first."
  @spec active_savepoints() :: [String.t()]
  def active_savepoints do
    case get_state() do
      nil -> []
      %{stack: stack} -> Enum.reverse(stack)
    end
  end

  @doc "Roll back the outer transaction, discarding all writes."
  @spec clean() :: :ok | {:error, term()}
  def clean do
    case get_state() do
      nil ->
        :ok

      %{repo: repo} ->
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
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fetch_repo!(opts) do
    # TODO
  end

  defp put_state(state), do: Process.put(@state_key, state)
  defp get_state, do: Process.get(@state_key)
  defp clear_state, do: Process.delete(@state_key)
end
```

Give me only the complete implementation of `fetch_repo!` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
