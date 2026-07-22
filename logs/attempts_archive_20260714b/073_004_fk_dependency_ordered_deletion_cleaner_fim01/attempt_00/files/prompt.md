Implement the private `kahn/4` function — the recursive core of the topological
sort (Kahn's algorithm) used by `deletion_order/1`.

It receives four arguments: `spec` (the normalized dependency map
`%{table => [dependency, ...]}`), `node_set` (a `MapSet` of every table name in
the spec), `indeg` (a map from each still-unprocessed table to its current
in-degree — how many not-yet-emitted tables still depend on it), and `acc` (the
tables emitted so far, in reverse order).

Each step must pick exactly one node deterministically:

- Compute the `ready` nodes: every entry in `indeg` whose in-degree is `0`.
  Sort them by name so ties break deterministically.
- If there are no ready nodes, the sort is finished: when `indeg` is empty every
  table was emitted, so return `{:ok, Enum.reverse(acc)}`. Otherwise the
  remaining nodes form a cycle, so return `{:error, {:cycle, remaining}}` where
  `remaining` is the sorted list of the keys still left in `indeg`.
- Otherwise take the first ready node `n` (the smallest by name). Remove it from
  `indeg`, then for each of its in-map dependencies (use `deps(spec, n,
  node_set)`) decrement that dependency's in-degree by one. Recurse with the
  updated in-degree map and `n` prepended to `acc`.

This emits children before the parents they reference (parents accumulate
in-degree from their children and only become ready once every child has been
emitted).

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
    # TODO
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