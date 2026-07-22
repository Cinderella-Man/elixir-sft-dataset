defmodule TreeBuilder do
  @moduledoc """
  Builds nested tree structures (a forest) from a flat list of maps.

  Each input item is a map containing at least an `:id` key (any term) and a
  `:parent_id` key (the id of its parent, or `nil` for a root node).

  `build/2` returns `{:ok, forest}` where `forest` is the list of root nodes.
  Every node is the original input map with an extra `:children` key holding
  its child nodes, recursively built the same way. Leaves have `children: []`.

  Order is preserved: root nodes appear in the order they occurred in the input
  list, and so do the children beneath any given parent.

  Error cases are reported as tagged tuples rather than exceptions:

    * `{:error, {:duplicate_ids, ids}}` — one or more ids appeared more than once
    * `{:error, {:cycle_detected, ids}}` — the parent links form a cycle

  Nodes whose `:parent_id` refers to an id that is absent from the input are
  "orphans"; the `:orphan_strategy` option decides their fate.
  """

  @type id :: term()
  @type item :: %{required(:id) => id(), required(:parent_id) => id() | nil, optional(any()) => any()}
  @type node_map :: map()
  @type forest :: [node_map()]
  @type orphan_strategy :: :discard | :raise_to_root
  @type option :: {:orphan_strategy, orphan_strategy()}
  @type error ::
          {:cycle_detected, [id()]}
          | {:duplicate_ids, [id()]}
          | {:invalid_option, term()}

  @default_orphan_strategy :discard

  @doc """
  Converts a flat list of maps into a nested forest.

  ## Options

    * `:orphan_strategy` — what to do with a node whose `:parent_id` points at an
      id that does not exist in `items`:
      * `:discard` (default) — the orphan (and its whole subtree) is dropped
      * `:raise_to_root` — the orphan is treated as a root node

  ## Examples

      iex> items = [
      ...>   %{id: 1, parent_id: nil, name: "root"},
      ...>   %{id: 2, parent_id: 1, name: "child"}
      ...> ]
      iex> TreeBuilder.build(items)
      {:ok,
       [
         %{
           id: 1,
           parent_id: nil,
           name: "root",
           children: [%{id: 2, parent_id: 1, name: "child", children: []}]
         }
       ]}

      iex> TreeBuilder.build([])
      {:ok, []}

      iex> TreeBuilder.build([%{id: :a, parent_id: :b}, %{id: :b, parent_id: :a}])
      {:error, {:cycle_detected, [:a, :b]}}

      iex> TreeBuilder.build([%{id: 1, parent_id: 99}], orphan_strategy: :raise_to_root)
      {:ok, [%{id: 1, parent_id: 99, children: []}]}

  """
  @spec build([item()], [option()]) :: {:ok, forest()} | {:error, error()}
  def build(items, opts \\ [])

  def build([], _opts), do: {:ok, []}

  def build(items, opts) when is_list(items) and is_list(opts) do
    with {:ok, strategy} <- fetch_orphan_strategy(opts),
         :ok <- check_duplicates(items),
         index = build_index(items),
         :ok <- check_cycles(items, index) do
      {:ok, assemble(items, index, strategy)}
    end
  end

  @doc """
  Same as `build/2` but returns the forest directly and raises on error.

  Raises `ArgumentError` when the input contains duplicate ids, a cycle, or when
  an invalid option is given.

  ## Examples

      iex> TreeBuilder.build!([%{id: 1, parent_id: nil}])
      [%{id: 1, parent_id: nil, children: []}]

  """
  @spec build!([item()], [option()]) :: forest()
  def build!(items, opts \\ []) do
    case build(items, opts) do
      {:ok, forest} -> forest
      {:error, reason} -> raise ArgumentError, "TreeBuilder.build!/2 failed: #{inspect(reason)}"
    end
  end

  # ----------------------------------------------------------------------------
  # Options
  # ----------------------------------------------------------------------------

  @spec fetch_orphan_strategy([option()]) :: {:ok, orphan_strategy()} | {:error, error()}
  defp fetch_orphan_strategy(opts) do
    case Keyword.get(opts, :orphan_strategy, @default_orphan_strategy) do
      :discard -> {:ok, :discard}
      :raise_to_root -> {:ok, :raise_to_root}
      other -> {:error, {:invalid_option, {:orphan_strategy, other}}}
    end
  end

  # ----------------------------------------------------------------------------
  # Validation
  # ----------------------------------------------------------------------------

  # Collects ids seen more than once, preserving first-seen order of the dupes.
  @spec check_duplicates([item()]) :: :ok | {:error, error()}
  defp check_duplicates(items) do
    {dupes, _seen} =
      Enum.reduce(items, {[], MapSet.new()}, fn item, {dupes, seen} ->
        id = Map.fetch!(item, :id)

        cond do
          not MapSet.member?(seen, id) -> {dupes, MapSet.put(seen, id)}
          id in dupes -> {dupes, seen}
          true -> {[id | dupes], seen}
        end
      end)

    case Enum.reverse(dupes) do
      [] -> :ok
      ids -> {:error, {:duplicate_ids, ids}}
    end
  end

  # id => item, for O(1) parent lookups.
  @spec build_index([item()]) :: %{optional(id()) => item()}
  defp build_index(items) do
    Map.new(items, fn item -> {Map.fetch!(item, :id), item} end)
  end

  # ----------------------------------------------------------------------------
  # Cycle detection
  # ----------------------------------------------------------------------------

  # Each node has at most one parent, so the parent graph is a functional graph:
  # walking upwards from any node either terminates (root / orphan) or revisits a
  # node. We walk from every node, memoising nodes already proven acyclic.
  @spec check_cycles([item()], %{optional(id()) => item()}) :: :ok | {:error, error()}
  defp check_cycles(items, index) do
    Enum.reduce_while(items, MapSet.new(), fn item, safe ->
      case walk_up(Map.fetch!(item, :id), index, safe, [], MapSet.new()) do
        {:ok, safe} -> {:cont, safe}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      %MapSet{} -> :ok
    end
  end

  # `path` is the reversed chain of ids visited in this walk; `on_path` is the
  # same set for O(1) membership tests. `safe` accumulates ids known to be
  # cycle-free across walks so the whole check stays linear.
  @spec walk_up(id(), %{optional(id()) => item()}, MapSet.t(), [id()], MapSet.t()) ::
          {:ok, MapSet.t()} | {:error, error()}
  defp walk_up(id, index, safe, path, on_path) do
    cond do
      MapSet.member?(on_path, id) ->
        {:error, {:cycle_detected, extract_cycle(path, id)}}

      MapSet.member?(safe, id) ->
        {:ok, mark_safe(safe, path)}

      true ->
        case Map.fetch(index, id) do
          # Root or orphan: the chain terminates, everything on it is safe.
          {:ok, %{parent_id: nil}} ->
            {:ok, mark_safe(safe, [id | path])}

          {:ok, %{parent_id: parent_id}} ->
            walk_up(parent_id, index, safe, [id | path], MapSet.put(on_path, id))

          # Unknown parent id: orphan boundary, the chain terminates here too.
          :error ->
            {:ok, mark_safe(safe, path)}
        end
    end
  end

  @spec mark_safe(MapSet.t(), [id()]) :: MapSet.t()
  defp mark_safe(safe, path), do: Enum.reduce(path, safe, &MapSet.put(&2, &1))

  # `path` is newest-first; the cycle is the prefix up to and including `id`.
  @spec extract_cycle([id()], id()) :: [id()]
  defp extract_cycle(path, id) do
    path
    |> Enum.take_while(&(&1 != id))
    |> then(&[id | Enum.reverse(&1)])
  end

  # ----------------------------------------------------------------------------
  # Assembly
  # ----------------------------------------------------------------------------

  @spec assemble([item()], %{optional(id()) => item()}, orphan_strategy()) :: forest()
  defp assemble(items, index, strategy) do
    children_by_parent = group_children(items, index, strategy)

    items
    |> Enum.filter(&root?(&1, index, strategy))
    |> Enum.map(&attach(&1, children_by_parent))
  end

  # parent_id => [child item, ...] in original input order.
  @spec group_children([item()], %{optional(id()) => item()}, orphan_strategy()) ::
          %{optional(id()) => [item()]}
  defp group_children(items, index, strategy) do
    items
    |> Enum.reject(&root?(&1, index, strategy))
    |> Enum.reject(&orphan?(&1, index))
    |> Enum.group_by(&Map.fetch!(&1, :parent_id))
  end

  # A node is a root when it has no parent, or when it is an orphan that the
  # `:raise_to_root` strategy promotes.
  @spec root?(item(), %{optional(id()) => item()}, orphan_strategy()) :: boolean()
  defp root?(item, index, strategy) do
    case Map.fetch!(item, :parent_id) do
      nil -> true
      _parent_id -> strategy == :raise_to_root and orphan?(item, index)
    end
  end

  @spec orphan?(item(), %{optional(id()) => item()}) :: boolean()
  defp orphan?(item, index) do
    case Map.fetch!(item, :parent_id) do
      nil -> false
      parent_id -> not Map.has_key?(index, parent_id)
    end
  end

  # Recursively builds a node. Discarded orphans never appear in
  # `children_by_parent`, so their subtrees are dropped along with them.
  @spec attach(item(), %{optional(id()) => [item()]}) :: node_map()
  defp attach(item, children_by_parent) do
    children =
      children_by_parent
      |> Map.get(Map.fetch!(item, :id), [])
      |> Enum.map(&attach(&1, children_by_parent))

    Map.put(item, :children, children)
  end
end