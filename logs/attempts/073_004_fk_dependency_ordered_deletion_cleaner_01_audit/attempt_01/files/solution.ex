defmodule DBCleaner do
  @moduledoc """
  Foreign-key-aware integration-test cleaner.

  Instead of `TRUNCATE ... CASCADE`, `clean/0` issues `DELETE FROM <table>` in
  an order derived by topologically sorting a dependency spec: a child table
  (one holding a foreign key) is emptied before the parent it references, so no
  FK constraint is violated and no unlisted table is ever touched.

  State lives in the calling process's dictionary under `{DBCleaner, :state}`
  and persists until `start/2` is called again, so `clean/0` is repeatable.
  """

  @state_key {__MODULE__, :state}
  @valid_identifier ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  @doc """
  Register the `:deletion` strategy for the calling process.

  `opts` must contain `:repo` (an Ecto repo module) and may contain `:tables`,
  a list whose entries are either a plain table name (`"users"`) or a tuple
  `{"comments", ["posts"]}` declaring that `comments` holds a foreign key into
  `posts`. Every identifier is validated against `/[a-zA-Z_][a-zA-Z0-9_]*/` and
  an `ArgumentError` is raised on a bad name. No SQL is issued here.
  """
  @spec start(atom(), keyword()) :: {:ok, :deletion} | {:error, term()}
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

  @doc """
  Delete every registered table in dependency order.

  Safe no-op when `start/2` was never called. On a cycle no query is issued and
  `{:error, {:cycle, tables}}` is returned. The stored spec is kept, so calling
  `clean/0` again re-issues the same deletes.
  """
  @spec clean() :: :ok | {:error, term()}
  def clean do
    case get_state() do
      nil ->
        :ok

      %{repo: repo, spec: spec} ->
        with {:ok, order} <- deletion_order(spec) do
          run_deletes(repo, order)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # SQL execution
  # ---------------------------------------------------------------------------

  defp run_deletes(repo, order) do
    Enum.each(order, fn table ->
      repo.query!(repo, "DELETE FROM #{table}", [])
    end)

    :ok
  rescue
    e -> {:error, Exception.message(e)}
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
    if Regex.match?(@valid_identifier, name) do
      :ok
    else
      raise ArgumentError,
            "invalid identifier #{inspect(name)}. Must match /[a-zA-Z_][a-zA-Z0-9_]*/"
    end
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
end
