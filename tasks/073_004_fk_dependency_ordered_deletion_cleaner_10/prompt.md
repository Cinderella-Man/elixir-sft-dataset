# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `get_state` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `DBCleaner` that cleans integration-test tables using ordered `DELETE FROM` statements that respect **foreign-key dependencies**, rather than `TRUNCATE ... CASCADE`.

`TRUNCATE ... CASCADE` is a blunt instrument — it can silently wipe tables you didn't list, and some setups disallow it. I want a cleaner that deletes rows in dependency order: a child table (one holding a foreign key) is emptied *before* the parent table it references, so no FK constraint is ever violated. That order must be derived by topologically sorting a dependency spec.

I need this public API:

- `DBCleaner.start(:deletion, opts \\ [])` — called in `setup`. `opts` must include `:repo` (an Ecto repo module) and `:tables`, a list describing the tables and their dependencies. Each entry is either a plain table-name string `"users"` (no dependencies) or a tuple `{"comments", ["posts"]}` meaning the `comments` table has a foreign key into `posts` (so `comments` must be deleted first). Validate every table/dependency name against `/[a-zA-Z_][a-zA-Z0-9_]*/` (raise `ArgumentError` on a bad name). This function issues no SQL; it just stores the normalized spec in the process dictionary. Returns `{:ok, :deletion}`.

- `DBCleaner.deletion_order(spec)` — a pure helper that takes a normalized spec map `%{table => [dependency, ...]}` and returns `{:ok, ordered_tables}` where each table precedes the tables it depends on (children first, parents last). Dependencies that reference tables not in the map are ignored for ordering. If the dependencies contain a cycle, return `{:error, {:cycle, remaining_tables}}` where `remaining_tables` is the sorted list of the tables still involved in the cycle. The order must be deterministic (break ties by sorting names).

- `DBCleaner.clean()` — called in `on_exit`. Compute the deletion order, then issue `DELETE FROM <table>` via `repo.query!(repo, sql, [])` for each table in that order. On success return `:ok` (not the ordered table list). On a cycle, issue no queries and return `{:error, {:cycle, ...}}`. Safe no-op returning `:ok` if `start/2` was never called.

Keep it self-contained in one file (no dependencies beyond Ecto), store state in the process dictionary, and implement the topological sort yourself (e.g. Kahn's algorithm). Guard against SQL injection via the identifier allowlist.

Give me the complete module in a single file.

## The module with `get_state` missing

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

  defp get_state do
    # TODO
  end

  defp clear_state, do: Process.delete(@state_key)
end
```

Give me only the complete implementation of `get_state` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
