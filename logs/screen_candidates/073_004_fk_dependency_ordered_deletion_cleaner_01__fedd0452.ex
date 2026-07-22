defmodule DBCleaner do
  @moduledoc """
  Cleans integration-test tables with ordered `DELETE FROM` statements.

  Instead of `TRUNCATE ... CASCADE` — which can silently empty tables that were never
  listed, and which some database setups disallow outright — this module derives a safe
  deletion order from an explicit dependency spec and issues one `DELETE FROM` per table.

  A table that holds a foreign key (a *child*) is deleted before the table it references
  (its *parent*), so no foreign-key constraint is ever violated.

  ## Usage

      setup do
        DBCleaner.start(:deletion,
          repo: MyApp.Repo,
          tables: [
            "users",
            {"posts", ["users"]},
            {"comments", ["posts", "users"]}
          ]
        )

        on_exit(&DBCleaner.clean/0)
      end

  The example above deletes `comments`, then `posts`, then `users`.

  ## Table specs

  Each entry of `:tables` is either:

    * a plain string — `"users"` — a table with no dependencies; or
    * a `{table, dependencies}` tuple — `{"comments", ["posts"]}` — meaning `comments`
      holds a foreign key into `posts`, so `comments` must be deleted first.

  ## State

  The normalized spec is kept in the process dictionary, so it lives and dies with the
  test process. `start/2` issues no SQL at all; every query happens in `clean/0`.

  ## Safety

  Table identifiers cannot be parameterized in SQL, so every name — whether a table or a
  dependency — is validated against `#{inspect(~r/[a-zA-Z_][a-zA-Z0-9_]*/)}` at `start/2`
  time and rejected with an `ArgumentError` otherwise. Only names from that allowlist ever
  reach the interpolated statement.
  """

  @typedoc "A validated SQL table identifier."
  @type table :: String.t()

  @typedoc "A normalized dependency spec: each table mapped to the tables it references."
  @type spec :: %{optional(table()) => [table()]}

  @typedoc "An entry accepted by the `:tables` option of `start/2`."
  @type table_spec :: table() | {table(), [table()]}

  @pdict_key :db_cleaner_state
  @identifier_regex ~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  @doc """
  Stores a normalized deletion spec for the current process.

  Call this from `setup`. It performs no database work; it only validates and records the
  spec that `clean/0` will later act on.

  ## Options

    * `:repo` — required. The `Ecto.Repo` module used to run the deletes.
    * `:tables` — required. A list of `t:table_spec/0` entries.

  Raises `ArgumentError` if an option is missing, if an entry is malformed, or if any
  table or dependency name is not a valid SQL identifier.

  ## Examples

      iex> DBCleaner.start(:deletion, repo: MyApp.Repo, tables: ["users"])
      {:ok, :deletion}
  """
  @spec start(:deletion, keyword()) :: {:ok, :deletion}
  def start(:deletion, opts \\ []) do
    repo = fetch_required!(opts, :repo)
    tables = fetch_required!(opts, :tables)

    unless is_atom(repo) do
      raise ArgumentError, "expected :repo to be an Ecto repo module, got: #{inspect(repo)}"
    end

    unless is_list(tables) do
      raise ArgumentError, "expected :tables to be a list, got: #{inspect(tables)}"
    end

    spec = normalize_tables!(tables)
    Process.put(@pdict_key, %{strategy: :deletion, repo: repo, spec: spec})

    {:ok, :deletion}
  end

  @doc """
  Returns the tables of `spec` in a safe deletion order.

  Each table precedes every table it depends on: children first, parents last. Dependencies
  naming tables absent from `spec` are ignored for ordering purposes. Ties are broken by
  sorting table names, so the result is deterministic for a given spec.

  Returns `{:error, {:cycle, remaining}}` when the dependencies contain a cycle, where
  `remaining` is the sorted list of tables that could not be ordered.

  ## Examples

      iex> DBCleaner.deletion_order(%{"users" => [], "posts" => ["users"]})
      {:ok, ["posts", "users"]}

      iex> DBCleaner.deletion_order(%{"a" => ["b"], "b" => ["a"]})
      {:error, {:cycle, ["a", "b"]}}
  """
  @spec deletion_order(spec()) :: {:ok, [table()]} | {:error, {:cycle, [table()]}}
  def deletion_order(spec) when is_map(spec) do
    tables = spec |> Map.keys() |> Enum.sort()
    known = MapSet.new(tables)

    # Edge child -> parent: the child must be emitted first, so a table's "in-degree" is
    # the number of known children pointing at it. Parents drain only once every child of
    # theirs has been emitted.
    edges =
      Map.new(tables, fn table ->
        parents =
          spec
          |> Map.fetch!(table)
          |> Enum.filter(&MapSet.member?(known, &1))
          |> Enum.reject(&(&1 == table))
          |> Enum.uniq()

        {table, parents}
      end)

    in_degrees =
      Enum.reduce(edges, Map.new(tables, &{&1, 0}), fn {_child, parents}, acc ->
        Enum.reduce(parents, acc, fn parent, inner ->
          Map.update!(inner, parent, &(&1 + 1))
        end)
      end)

    ready = tables |> Enum.filter(&(Map.fetch!(in_degrees, &1) == 0)) |> Enum.sort()

    kahn(ready, in_degrees, edges, [])
  end

  @doc """
  Deletes every configured table, children before parents.

  Call this from `on_exit`. It computes the deletion order from the spec recorded by
  `start/2` and issues `DELETE FROM <table>` for each table via `repo.query!/3`.

  Returns `{:ok, deleted_tables}` on success, `{:error, {:cycle, remaining}}` — without
  issuing any query — when the spec is cyclic, and `:ok` when `start/2` was never called.

  ## Examples

      iex> DBCleaner.clean()
      {:ok, ["comments", "posts", "users"]}
  """
  @spec clean() :: {:ok, [table()]} | {:error, {:cycle, [table()]}} | :ok
  def clean do
    case Process.get(@pdict_key) do
      nil ->
        :ok

      %{repo: repo, spec: spec} ->
        case deletion_order(spec) do
          {:ok, ordered} ->
            Enum.each(ordered, fn table ->
              repo.query!(repo, ~s(DELETE FROM #{table}), [])
            end)

            {:ok, ordered}

          {:error, _reason} = error ->
            error
        end
    end
  end

  # -- internals ------------------------------------------------------------------------

  @spec kahn([table()], %{optional(table()) => non_neg_integer()}, spec(), [table()]) ::
          {:ok, [table()]} | {:error, {:cycle, [table()]}}
  defp kahn([], in_degrees, _edges, acc) do
    case in_degrees |> Map.keys() |> Enum.sort() do
      [] -> {:ok, Enum.reverse(acc)}
      remaining -> {:error, {:cycle, remaining}}
    end
  end

  defp kahn([table | rest], in_degrees, edges, acc) do
    in_degrees = Map.delete(in_degrees, table)
    parents = Map.fetch!(edges, table)

    {in_degrees, freed} =
      Enum.reduce(parents, {in_degrees, []}, fn parent, {degrees, freed} ->
        case Map.fetch(degrees, parent) do
          {:ok, 1} -> {Map.put(degrees, parent, 0), [parent | freed]}
          {:ok, n} -> {Map.put(degrees, parent, n - 1), freed}
          :error -> {degrees, freed}
        end
      end)

    ready = Enum.sort(rest ++ freed)

    kahn(ready, in_degrees, edges, [table | acc])
  end

  @spec normalize_tables!([table_spec()]) :: spec()
  defp normalize_tables!(tables) do
    Enum.reduce(tables, %{}, fn entry, acc ->
      {table, deps} = normalize_entry!(entry)
      Map.update(acc, table, deps, &Enum.uniq(&1 ++ deps))
    end)
  end

  @spec normalize_entry!(table_spec()) :: {table(), [table()]}
  defp normalize_entry!(table) when is_binary(table), do: {validate_name!(table), []}

  defp normalize_entry!({table, deps}) when is_binary(table) and is_list(deps) do
    {validate_name!(table), deps |> Enum.map(&validate_name!/1) |> Enum.uniq()}
  end

  defp normalize_entry!(other) do
    raise ArgumentError,
          "expected a table name or a {table, dependencies} tuple, got: #{inspect(other)}"
  end

  @spec validate_name!(term()) :: table()
  defp validate_name!(name) when is_binary(name) do
    if Regex.match?(@identifier_regex, name) do
      name
    else
      raise ArgumentError, "invalid SQL identifier: #{inspect(name)}"
    end
  end

  defp validate_name!(other) do
    raise ArgumentError, "expected a table name as a string, got: #{inspect(other)}"
  end

  @spec fetch_required!(keyword(), atom()) :: term()
  defp fetch_required!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "missing required option #{inspect(key)}"
    end
  end
end