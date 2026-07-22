defmodule DBCleaner do
  @moduledoc """
  Cleans integration-test tables with ordered `DELETE FROM` statements.

  Instead of reaching for `TRUNCATE ... CASCADE` — which can silently wipe tables that were
  never listed, and which some database setups disallow outright — this module deletes rows
  in dependency order. A child table (one that holds a foreign key) is emptied *before* the
  parent table it references, so no foreign-key constraint is ever violated.

  The order is derived by topologically sorting a dependency spec supplied at `start/2`.

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

  The spec above yields the deletion order `["comments", "posts", "users"]`: comments hold
  foreign keys into posts and users, so they go first; users are referenced by everything, so
  they go last.

  ## State

  All state lives in the process dictionary, so a cleaner started in a test process is scoped
  to that process and needs no supervision tree or named server.

  ## Safety

  Table and dependency names are validated against `#{inspect(~r/[a-zA-Z_][a-zA-Z0-9_]*/)}`
  at `start/2` time, before any name is ever interpolated into SQL. Anything else raises
  `ArgumentError`. This allowlist is the only defence against SQL injection through
  identifiers, and it is deliberately strict.
  """

  @state_key :db_cleaner_state

  @identifier_regex ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/

  @typedoc "A normalized dependency spec: table name => list of table names it depends on."
  @type spec :: %{optional(String.t()) => [String.t()]}

  @typedoc "A single entry of the `:tables` option."
  @type table_entry :: String.t() | {String.t(), [String.t()]}

  @doc """
  Registers the deletion strategy and its table dependency spec for the current process.

  Issues no SQL — it only normalizes and stores the spec, so it is cheap to call from
  `setup`.

  ## Options

    * `:repo` — required. An Ecto repo module used later by `clean/0`.
    * `:tables` — required. A list where each entry is either a plain table name
      (`"users"`, meaning no dependencies) or a `{table, dependencies}` tuple
      (`{"comments", ["posts"]}`, meaning `comments` holds a foreign key into `posts`
      and must therefore be deleted first).

  Duplicate entries for the same table are merged: their dependency lists are unioned.

  Raises `ArgumentError` if `:repo` or `:tables` is missing, if an entry is malformed, or
  if any table or dependency name is not a valid SQL identifier.

  Returns `{:ok, :deletion}`.

  ## Examples

      iex> DBCleaner.start(:deletion, repo: MyApp.Repo, tables: ["users", {"posts", ["users"]}])
      {:ok, :deletion}
  """
  @spec start(:deletion, keyword()) :: {:ok, :deletion}
  def start(:deletion, opts \\ []) do
    repo = fetch_required!(opts, :repo)
    tables = fetch_required!(opts, :tables)

    unless is_list(tables) do
      raise ArgumentError, "expected :tables to be a list, got: #{inspect(tables)}"
    end

    spec = normalize_tables(tables)

    Process.put(@state_key, %{strategy: :deletion, repo: repo, spec: spec})

    {:ok, :deletion}
  end

  @doc """
  Computes the deletion order for a normalized dependency spec.

  Takes a map of `%{table => [dependency, ...]}` and returns `{:ok, ordered_tables}` where
  every table precedes the tables it depends on — children first, parents last. Deleting in
  this order never violates a foreign-key constraint.

  Dependencies naming tables absent from the spec are ignored for ordering purposes: they
  cannot be deleted anyway, so they impose no constraint.

  The order is deterministic — ties are broken by sorting table names — so repeated runs on
  the same spec always produce the same sequence.

  If the dependencies contain a cycle, returns `{:error, {:cycle, remaining_tables}}` where
  `remaining_tables` is the sorted list of tables that could not be ordered.

  ## Examples

      iex> DBCleaner.deletion_order(%{"users" => [], "posts" => ["users"]})
      {:ok, ["posts", "users"]}

      iex> DBCleaner.deletion_order(%{"a" => ["b"], "b" => ["a"]})
      {:error, {:cycle, ["a", "b"]}}
  """
  @spec deletion_order(spec()) :: {:ok, [String.t()]} | {:error, {:cycle, [String.t()]}}
  def deletion_order(spec) when is_map(spec) do
    # Edge direction: table -> dependency ("delete `table` before `dependency`").
    # Kahn's algorithm emits nodes with no unmet *incoming* edges first. We want children
    # (tables that depend on others) emitted first, so we count, for each table, how many
    # other tables depend on *it* — its in-degree as a parent.
    deps = Map.new(spec, fn {table, dependencies} -> {table, known_deps(dependencies, spec)} end)

    dependents = build_dependents(deps)
    in_degree = Map.new(deps, fn {table, dependencies} -> {table, length(dependencies)} end)

    ready = for {table, 0} <- in_degree, do: table

    kahn(Enum.sort(ready), dependents, in_degree, [])
  end

  @doc """
  Deletes all rows from the registered tables, in dependency order.

  Computes the deletion order from the spec stored by `start/2`, then issues
  `DELETE FROM <table>` for each table via `repo.query!(repo, sql, [])`.

  Returns:

    * `:ok` on success.
    * `{:error, {:cycle, remaining_tables}}` if the spec is cyclic — no queries are issued.
    * `:ok` if `start/2` was never called in this process (a safe no-op), which makes it
      harmless to register unconditionally with `on_exit/1`.
  """
  @spec clean() :: :ok | {:error, {:cycle, [String.t()]}}
  def clean do
    case Process.get(@state_key) do
      nil ->
        :ok

      %{strategy: :deletion, repo: repo, spec: spec} ->
        case deletion_order(spec) do
          {:ok, ordered} ->
            Enum.each(ordered, fn table -> repo.query!(repo, "DELETE FROM #{table}", []) end)
            :ok

          {:error, _reason} = error ->
            error
        end
    end
  end

  # -- spec normalization ------------------------------------------------------------------

  @spec fetch_required!(keyword(), atom()) :: term()
  defp fetch_required!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "expected #{inspect(key)} option to be given"
    end
  end

  @spec normalize_tables([table_entry()]) :: spec()
  defp normalize_tables(tables) do
    Enum.reduce(tables, %{}, fn entry, acc ->
      {table, dependencies} = normalize_entry(entry)
      Map.update(acc, table, dependencies, &Enum.uniq(&1 ++ dependencies))
    end)
  end

  @spec normalize_entry(table_entry()) :: {String.t(), [String.t()]}
  defp normalize_entry(table) when is_binary(table) do
    {validate_identifier!(table), []}
  end

  defp normalize_entry({table, dependencies}) when is_binary(table) and is_list(dependencies) do
    {validate_identifier!(table), dependencies |> Enum.map(&validate_identifier!/1) |> Enum.uniq()}
  end

  defp normalize_entry(other) do
    raise ArgumentError,
          "expected a table name or a {table, dependencies} tuple, got: #{inspect(other)}"
  end

  @spec validate_identifier!(term()) :: String.t()
  defp validate_identifier!(name) when is_binary(name) do
    if Regex.match?(@identifier_regex, name) do
      name
    else
      raise ArgumentError, "invalid table name: #{inspect(name)}"
    end
  end

  defp validate_identifier!(name) do
    raise ArgumentError, "expected a table name as a string, got: #{inspect(name)}"
  end

  # -- topological sort (Kahn's algorithm) -------------------------------------------------

  @spec known_deps([String.t()], spec()) :: [String.t()]
  defp known_deps(dependencies, spec) do
    Enum.filter(dependencies, fn dependency ->
      Map.has_key?(spec, dependency) and dependency != nil
    end)
  end

  # Maps each dependency to the tables that depend on it, so that emitting a table can
  # decrement the in-degree of everything it points at.
  @spec build_dependents(spec()) :: %{optional(String.t()) => [String.t()]}
  defp build_dependents(deps) do
    Enum.reduce(deps, %{}, fn {table, dependencies}, acc ->
      Enum.reduce(dependencies, acc, fn dependency, inner ->
        Map.update(inner, dependency, [table], &[table | &1])
      end)
    end)
  end

  @spec kahn([String.t()], %{optional(String.t()) => [String.t()]}, %{
          optional(String.t()) => non_neg_integer()
        }, [String.t()]) :: {:ok, [String.t()]} | {:error, {:cycle, [String.t()]}}
  defp kahn([], _dependents, in_degree, acc) do
    remaining = for {table, degree} <- in_degree, degree > 0, do: table

    case remaining do
      [] -> {:ok, Enum.reverse(acc)}
      tables -> {:error, {:cycle, Enum.sort(tables)}}
    end
  end

  defp kahn([table | rest], dependents, in_degree, acc) do
    in_degree = Map.put(in_degree, table, -1)

    {in_degree, newly_ready} =
      dependents
      |> Map.get(table, [])
      |> Enum.reduce({in_degree, []}, fn dependent, {degrees, ready} ->
        degrees = Map.update!(degrees, dependent, &(&1 - 1))

        case Map.fetch!(degrees, dependent) do
          0 -> {degrees, [dependent | ready]}
          _ -> {degrees, ready}
        end
      end)

    # `newly_ready` is merged and re-sorted so ties always break the same way, regardless of
    # the order in which tables happened to become ready.
    next = Enum.sort(rest ++ newly_ready)

    kahn(next, dependents, in_degree, [table | acc])
  end
end