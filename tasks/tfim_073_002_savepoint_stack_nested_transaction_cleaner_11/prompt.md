# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  defp put_state(state), do: Process.put(@state_key, state)
  defp get_state, do: Process.get(@state_key)
  defp clear_state, do: Process.delete(@state_key)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DBCleanerTest do
  use ExUnit.Case, async: false

  defmodule FakeRepo do
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)
    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)

    def query!(_repo, sql, _params) do
      Agent.update(__MODULE__, &[{:query, sql} | &1])
      %{rows: [], num_rows: 0}
    end

    def begin_transaction do
      Agent.update(__MODULE__, &[{:begin} | &1])
      {:ok, make_ref()}
    end

    def rollback do
      Agent.update(__MODULE__, &[{:rollback} | &1])
      :ok
    end
  end

  setup do
    start_supervised!(FakeRepo)
    FakeRepo.reset()
    :ok
  end

  defp sqls do
    Enum.flat_map(FakeRepo.calls(), fn
      {:query, sql} -> [sql]
      _ -> []
    end)
  end

  test "start/2 begins an outer transaction and empty stack" do
    assert {:ok, :savepoint} = DBCleaner.start(:savepoint, repo: FakeRepo)
    assert {:begin} in FakeRepo.calls()
    assert DBCleaner.active_savepoints() == []
  end

  test "savepoint/1 issues SAVEPOINT and tracks the stack" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    assert {:ok, "a"} = DBCleaner.savepoint("a")
    assert {:ok, "b"} = DBCleaner.savepoint("b")

    assert DBCleaner.active_savepoints() == ["a", "b"]
    assert Enum.any?(sqls(), &(&1 == "SAVEPOINT a"))
    assert Enum.any?(sqls(), &(&1 == "SAVEPOINT b"))
  end

  test "rollback_to/1 issues ROLLBACK TO and trims newer savepoints" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")
    DBCleaner.savepoint("c")

    assert {:ok, "b"} = DBCleaner.rollback_to("b")
    assert DBCleaner.active_savepoints() == ["a", "b"]
    assert Enum.any?(sqls(), &(&1 == "ROLLBACK TO SAVEPOINT b"))
  end

  test "rollback_to/1 on an unknown savepoint returns an error" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    assert {:error, {:no_such_savepoint, "z"}} = DBCleaner.rollback_to("z")
  end

  test "release/1 releases the savepoint and any created after it" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")
    DBCleaner.savepoint("c")

    assert {:ok, "b"} = DBCleaner.release("b")
    assert DBCleaner.active_savepoints() == ["a"]
    assert Enum.any?(sqls(), &(&1 == "RELEASE SAVEPOINT b"))
  end

  test "release/1 on an unknown savepoint returns an error and keeps the stack" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")

    assert {:error, {:no_such_savepoint, "z"}} = DBCleaner.release("z")
    assert DBCleaner.active_savepoints() == ["a", "b"]
  end

  test "savepoint/1 before start returns :not_started" do
    assert {:error, :not_started} = DBCleaner.savepoint("a")
  end

  test "savepoint/1 rejects invalid identifiers without issuing SQL" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    FakeRepo.reset()

    assert {:error, {:invalid_name, "a; DROP TABLE users"}} =
             DBCleaner.savepoint("a; DROP TABLE users")

    assert sqls() == []
  end

  test "clean/0 rolls back the outer transaction and clears state" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    FakeRepo.reset()

    assert :ok = DBCleaner.clean()
    assert {:rollback} in FakeRepo.calls()
    assert DBCleaner.active_savepoints() == []
  end

  test "clean/0 without a prior start is a safe no-op" do
    assert :ok = DBCleaner.clean()
    assert FakeRepo.calls() == []
  end

  test "state does not bleed across sequential start/clean cycles" do
    # TODO
  end

  # A savepoint name must be an identifier string; anything that is not a
  # string is a bad identifier, so it is refused and no SQL reaches the repo.
  test "savepoint/1 rejects a non-string name as an invalid identifier" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    FakeRepo.reset()

    assert {:error, {:invalid_name, :users}} = DBCleaner.savepoint(:users)
    assert {:error, {:invalid_name, 42}} = DBCleaner.savepoint(42)

    assert sqls() == []
    assert DBCleaner.active_savepoints() == []
  end

  # With no outer transaction open there are no active savepoints, so naming
  # one for rollback or release cannot succeed and no SQL is issued.
  test "rollback_to/1 and release/1 before start fail instead of reporting success" do
    assert DBCleaner.active_savepoints() == []

    assert {:error, _} = DBCleaner.rollback_to("a")
    assert {:error, _} = DBCleaner.release("a")

    assert FakeRepo.calls() == []
    assert DBCleaner.active_savepoints() == []
  end
end
```
