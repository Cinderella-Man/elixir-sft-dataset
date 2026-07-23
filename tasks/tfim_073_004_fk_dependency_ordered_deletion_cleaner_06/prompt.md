# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule DBCleaner do
  @moduledoc """
  Foreign-key-aware integration-test cleaner.

  Instead of `TRUNCATE ... CASCADE`, `clean/0` issues `DELETE FROM <table>` in
  an order derived by topologically sorting a dependency spec: a child table
  (one holding a foreign key) is emptied before the parent it references, so no
  FK constraint is violated and no unlisted table is ever touched.

  State lives in the calling process's dictionary under `{DBCleaner, :state}`.
  """

  @state_key {__MODULE__, :state}
  @valid_identifier ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  @spec start(:deletion, keyword()) :: {:ok, :deletion} | {:error, term()}
  def start(strategy, opts \\ [])

  def start(:deletion, opts) do
    repo = fetch_repo!(opts)
    entries = Keyword.get(opts, :tables, [])
    spec = normalize_spec!(entries)

    put_state(%{repo: repo, spec: spec})
    {:ok, :deletion}
  end

  def start(unknown, _opts) do
    {:error, "unknown strategy #{inspect(unknown)}. Expected :deletion"}
  end

  @doc """
  Topologically sort a normalized spec (`%{table => [dependency, ...]}`) so each
  table precedes the tables it depends on. Deterministic; `{:error, {:cycle, _}}`
  on a dependency cycle.
  """
  @spec deletion_order(map()) :: {:ok, [String.t()]} | {:error, {:cycle, [String.t()]}}
  def deletion_order(spec) when is_map(spec) do
    nodes = Map.keys(spec)
    node_set = MapSet.new(nodes)

    indeg =
      Enum.reduce(nodes, Map.new(nodes, &{&1, 0}), fn a, acc ->
        Enum.reduce(deps(spec, a, node_set), acc, fn b, acc2 ->
          Map.update!(acc2, b, &(&1 + 1))
        end)
      end)

    kahn(spec, node_set, indeg, [])
  end

  @doc "Delete every registered table in dependency order."
  @spec clean() :: :ok | {:error, term()}
  def clean do
    case get_state() do
      nil ->
        :ok

      %{repo: repo, spec: spec} ->
        case deletion_order(spec) do
          {:ok, order} ->
            try do
              Enum.each(order, fn table ->
                repo.query!(repo, "DELETE FROM #{table}", [])
              end)

              clear_state()
              :ok
            rescue
              e ->
                clear_state()
                {:error, Exception.message(e)}
            end

          {:error, reason} ->
            clear_state()
            {:error, reason}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Topological sort (Kahn's algorithm, one deterministic node per step)
  # ---------------------------------------------------------------------------

  defp kahn(spec, node_set, indeg, acc) do
    ready =
      indeg
      |> Enum.filter(fn {_n, d} -> d == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case ready do
      [] ->
        if map_size(indeg) == 0 do
          {:ok, Enum.reverse(acc)}
        else
          {:error, {:cycle, indeg |> Map.keys() |> Enum.sort()}}
        end

      [n | _] ->
        indeg2 = Map.delete(indeg, n)

        indeg3 =
          Enum.reduce(deps(spec, n, node_set), indeg2, fn b, acc2 ->
            Map.update!(acc2, b, &(&1 - 1))
          end)

        kahn(spec, node_set, indeg3, [n | acc])
    end
  end

  defp deps(spec, node, node_set) do
    spec
    |> Map.get(node, [])
    |> Enum.filter(&MapSet.member?(node_set, &1))
  end

  # ---------------------------------------------------------------------------
  # Validation / normalization
  # ---------------------------------------------------------------------------

  defp normalize_spec!(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      {table, table_deps} =
        case entry do
          t when is_binary(t) ->
            {t, []}

          {t, ds} when is_binary(t) and is_list(ds) ->
            {t, ds}

          other ->
            raise ArgumentError, "invalid table spec entry: #{inspect(other)}"
        end

      validate_identifier!(table)
      Enum.each(table_deps, &validate_identifier!/1)
      Map.put(acc, table, table_deps)
    end)
  end

  defp normalize_spec!(other) do
    raise ArgumentError, "expected :tables to be a list, got: #{inspect(other)}"
  end

  defp validate_identifier!(name) when is_binary(name) do
    unless Regex.match?(@valid_identifier, name) do
      raise ArgumentError,
            "invalid identifier #{inspect(name)}. Must match /[a-zA-Z_][a-zA-Z0-9_]*/"
    end

    :ok
  end

  defp validate_identifier!(other) do
    raise ArgumentError, "expected identifier to be a string, got: #{inspect(other)}"
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
  end

  setup do
    start_supervised!(FakeRepo)
    FakeRepo.reset()
    :ok
  end

  defp deleted_tables do
    Enum.flat_map(FakeRepo.calls(), fn
      {:query, "DELETE FROM " <> table} -> [table]
      _ -> []
    end)
  end

  test "start/2 issues no SQL" do
    assert {:ok, :deletion} =
             DBCleaner.start(:deletion,
               repo: FakeRepo,
               tables: [{"comments", ["posts"]}, {"posts", ["users"]}, "users"]
             )

    assert FakeRepo.calls() == []
  end

  test "clean/0 deletes children before the parents they reference" do
    DBCleaner.start(:deletion,
      repo: FakeRepo,
      tables: [{"comments", ["posts"]}, {"posts", ["users"]}, "users"]
    )

    assert :ok = DBCleaner.clean()
    assert deleted_tables() == ["comments", "posts", "users"]
  end

  test "deletion_order/1 orders children first, parents last" do
    spec = %{"comments" => ["posts"], "posts" => ["users"], "users" => []}
    assert {:ok, ["comments", "posts", "users"]} = DBCleaner.deletion_order(spec)
  end

  test "deletion_order/1 breaks ties deterministically by name" do
    spec = %{"zebra" => [], "alpha" => [], "mango" => []}
    assert {:ok, ["alpha", "mango", "zebra"]} = DBCleaner.deletion_order(spec)
  end

  test "deletion_order/1 ignores dependencies on unlisted tables" do
    # TODO
  end

  test "deletion_order/1 reports a cycle" do
    spec = %{"a" => ["b"], "b" => ["a"]}
    assert {:error, {:cycle, ["a", "b"]}} = DBCleaner.deletion_order(spec)
  end

  test "clean/0 with a cyclic spec issues no queries and returns an error" do
    DBCleaner.start(:deletion,
      repo: FakeRepo,
      tables: [{"a", ["b"]}, {"b", ["a"]}]
    )

    assert {:error, {:cycle, ["a", "b"]}} = DBCleaner.clean()
    assert deleted_tables() == []
  end

  test "clean/0 without a prior start is a safe no-op" do
    assert :ok = DBCleaner.clean()
    assert FakeRepo.calls() == []
  end

  test "start/2 raises on an invalid table identifier" do
    assert_raise ArgumentError, fn ->
      DBCleaner.start(:deletion, repo: FakeRepo, tables: ["users; DROP TABLE x"])
    end
  end

  test "plain string entries with no dependencies delete in sorted order" do
    DBCleaner.start(:deletion, repo: FakeRepo, tables: ["orders", "carts", "items"])
    DBCleaner.clean()
    assert deleted_tables() == ["carts", "items", "orders"]
  end
end
```
