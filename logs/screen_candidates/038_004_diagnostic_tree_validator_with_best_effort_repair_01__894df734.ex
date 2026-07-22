defmodule TreeValidator do
  @moduledoc """
  Builds a nested tree (forest) from a flat list of node maps using
  collect-all diagnostics and best-effort repair semantics.

  Instead of failing on the first structural problem, `build/1` gathers every
  issue in the input, repairs what it can, and returns the best forest it can
  construct from the healthy remainder.

  Each input node is a map with a unique `:id`. The `:parent_id` key is
  optional; when present it holds the parent's id or `nil` for a root.

  Detected issue types, each reported as `%{type: atom(), ids: [term()]}`:

    * `:duplicate_id` — ids appearing more than once. Only the first occurrence
      of each id is kept.
    * `:missing_parent_id` — nodes without the `:parent_id` key. They are
      treated as roots.
    * `:orphan` — nodes whose `parent_id` names an unknown id. They are raised
      to roots.
    * `:cycle` — one entry per distinct cycle. All nodes on a cycle are removed
      from the forest; nodes that pointed into a removed cycle become orphans.

  Issues are ordered `:duplicate_id`, `:missing_parent_id`, `:orphan`, then one
  entry per cycle. Root and sibling order follow the deduplicated input order.
  """

  @typedoc "A raw input node: a map with at least an `:id` key."
  @type item :: %{required(:id) => term(), optional(:parent_id) => term(), optional(any()) => any()}

  @typedoc "A node in the resulting forest: the original map plus `:children`."
  @type tree_node :: map()

  @typedoc "A single structural diagnostic."
  @type issue :: %{type: atom(), ids: [term()]}

  @doc """
  Converts a flat list of node maps into a nested forest.

  Returns `{:ok, forest}` when the input is structurally sound, or
  `{:issues, forest, issues}` when at least one problem was found — where
  `forest` is the best-effort tree and `issues` is a non-empty list of
  `%{type: atom(), ids: [term()]}` maps.

  ## Examples

      iex> TreeValidator.build([%{id: 1, parent_id: nil}, %{id: 2, parent_id: 1}])
      {:ok, [%{id: 1, parent_id: nil, children: [%{id: 2, parent_id: 1, children: []}]}]}

      iex> TreeValidator.build([%{id: 1, parent_id: 99}])
      {:issues, [%{id: 1, parent_id: 99, children: []}], [%{type: :orphan, ids: [1]}]}

  """
  @spec build([item()]) :: {:ok, [tree_node()]} | {:issues, [tree_node()], [issue()]}
  def build([]), do: {:ok, []}

  def build(items) when is_list(items) do
    {unique, duplicate_ids} = dedup(items)
    missing_ids = missing_parent_key_ids(unique)

    id_set = MapSet.new(unique, & &1.id)
    parent_of = Map.new(unique, &{&1.id, effective_parent(&1, id_set)})

    {cycles, cycle_members} = detect_cycles(unique, parent_of)

    kept = Enum.reject(unique, &MapSet.member?(cycle_members, &1.id))
    kept_ids = MapSet.new(kept, & &1.id)

    orphan_ids =
      for node <- kept,
          parent = Map.fetch!(parent_of, node.id),
          parent != nil,
          not MapSet.member?(kept_ids, parent),
          do: node.id

    forest = assemble(kept, parent_of, kept_ids)

    issues =
      collect_issues(duplicate_ids, missing_ids, orphan_ids, cycles)

    case issues do
      [] -> {:ok, forest}
      _ -> {:issues, forest, issues}
    end
  end

  # --- deduplication -------------------------------------------------------

  @spec dedup([item()]) :: {[item()], [term()]}
  defp dedup(items) do
    {reversed, _seen, dup_reversed, _dup_seen} =
      Enum.reduce(items, {[], MapSet.new(), [], MapSet.new()}, fn item,
                                                                  {acc, seen, dups, dup_seen} ->
        id = item.id

        cond do
          not MapSet.member?(seen, id) ->
            {[item | acc], MapSet.put(seen, id), dups, dup_seen}

          MapSet.member?(dup_seen, id) ->
            {acc, seen, dups, dup_seen}

          true ->
            {acc, seen, [id | dups], MapSet.put(dup_seen, id)}
        end
      end)

    {Enum.reverse(reversed), Enum.reverse(dup_reversed)}
  end

  @spec missing_parent_key_ids([item()]) :: [term()]
  defp missing_parent_key_ids(items) do
    for item <- items, not Map.has_key?(item, :parent_id), do: item.id
  end

  # The parent used for structural analysis: `nil` means root. A node missing
  # the `:parent_id` key, or pointing at itself, is treated as a root.
  @spec effective_parent(item(), MapSet.t()) :: term()
  defp effective_parent(item, id_set) do
    case Map.fetch(item, :parent_id) do
      :error -> nil
      {:ok, nil} -> nil
      {:ok, parent} -> if MapSet.member?(id_set, parent), do: parent, else: parent
    end
  end

  # --- cycle detection -----------------------------------------------------

  # Each node has at most one parent, so following parent links from any node
  # either terminates (root/orphan) or loops. We walk each chain once, marking
  # visited nodes, and record the cycle when we meet a node already on the
  # current path.
  @spec detect_cycles([item()], map()) :: {[[term()]], MapSet.t()}
  defp detect_cycles(items, parent_of) do
    {cycles, _state} =
      Enum.reduce(items, {[], %{}}, fn item, {cycles, state} ->
        walk(item.id, parent_of, state, [], cycles)
      end)

    ordered = Enum.reverse(cycles)
    members = ordered |> List.flatten() |> MapSet.new()
    {ordered, members}
  end

  # `state` maps id => :done (fully resolved, not on an open path).
  # `path` is the current chain (most recent first).
  @spec walk(term(), map(), map(), [term()], [[term()]]) :: {[[term()]], map()}
  defp walk(id, parent_of, state, path, cycles) do
    cond do
      Map.get(state, id) == :done ->
        {cycles, finish(path, state)}

      id in path ->
        cycle = extract_cycle(path, id)
        {[cycle | cycles], finish(path, state)}

      true ->
        case Map.get(parent_of, id, :unknown) do
          nil -> {cycles, finish([id | path], state)}
          :unknown -> {cycles, finish([id | path], state)}
          parent -> walk(parent, parent_of, state, [id | path], cycles)
        end
    end
  end

  @spec finish([term()], map()) :: map()
  defp finish(path, state), do: Enum.reduce(path, state, &Map.put(&2, &1, :done))

  # `path` is [most_recent, ..., oldest]; the cycle is the prefix up to and
  # including `id`, returned in traversal (parent-link) order.
  @spec extract_cycle([term()], term()) :: [term()]
  defp extract_cycle(path, id) do
    path
    |> Enum.take_while(&(&1 != id))
    |> then(&(&1 ++ [id]))
    |> Enum.reverse()
  end

  # --- forest assembly -----------------------------------------------------

  @spec assemble([item()], map(), MapSet.t()) :: [tree_node()]
  defp assemble(items, parent_of, kept_ids) do
    children_index =
      Enum.reduce(items, %{}, fn item, acc ->
        key = root_or_parent(item, parent_of, kept_ids)
        Map.update(acc, key, [item], &[item | &1])
      end)

    children_index = Map.new(children_index, fn {k, v} -> {k, Enum.reverse(v)} end)

    children_index
    |> Map.get(:__root__, [])
    |> Enum.map(&expand(&1, children_index))
  end

  @spec root_or_parent(item(), map(), MapSet.t()) :: term()
  defp root_or_parent(item, parent_of, kept_ids) do
    case Map.fetch!(parent_of, item.id) do
      nil -> :__root__
      parent -> if MapSet.member?(kept_ids, parent), do: parent, else: :__root__
    end
  end

  @spec expand(item(), map()) :: tree_node()
  defp expand(item, children_index) do
    children =
      children_index
      |> Map.get(item.id, [])
      |> Enum.map(&expand(&1, children_index))

    Map.put(item, :children, children)
  end

  # --- issue collection ----------------------------------------------------

  @spec collect_issues([term()], [term()], [term()], [[term()]]) :: [issue()]
  defp collect_issues(duplicate_ids, missing_ids, orphan_ids, cycles) do
    []
    |> maybe_issue(:duplicate_id, duplicate_ids)
    |> maybe_issue(:missing_parent_id, missing_ids)
    |> maybe_issue(:orphan, orphan_ids)
    |> then(fn acc -> Enum.reduce(cycles, acc, &[%{type: :cycle, ids: &1} | &2]) end)
    |> Enum.reverse()
  end

  @spec maybe_issue([issue()], atom(), [term()]) :: [issue()]
  defp maybe_issue(acc, _type, []), do: acc
  defp maybe_issue(acc, type, ids), do: [%{type: type, ids: ids} | acc]
end