Implement the private `do_delete/2` recursive helper used by the public `delete/2`
function. It walks the trie along the graphemes of the word being removed and reports
back to `delete/2` whether the word was actually present, pruning any nodes that
become empty so that removing one word never disturbs another.

`do_delete/2` takes a node and a list of remaining graphemes and must return one of
two shapes: `:notfound` when the exact word is not stored in the trie, or
`{updated_node, :ok}` carrying the rewritten subtree when the word was found and
removed.

There are two clauses to implement:

- Base case (empty grapheme list): the current node is the end of the word. If its
  `weight` is `0`, the word was never stored here, so return `:notfound`. Otherwise
  clear the word by setting `weight` to `0` and return `{node_with_zero_weight, :ok}`.

- Recursive case (`[char | rest]`): look up `char` in the node's `children`. If there
  is no such child, return `:notfound`. If there is a child, recurse into it with
  `rest`. Propagate a `:notfound` result unchanged. On `{new_child, :ok}`, decide
  whether to prune: if the returned child now has `weight == 0` **and** no children of
  its own, drop it from this node's `children` with `Map.delete/2`; otherwise store the
  updated child back with `Map.put/3`. Either way, return `{updated_node, :ok}`.

Deleting "car" must leave "card" intact, and deleting an absent word must surface as
`:notfound` so `delete/2` can treat it as a no-op.

```elixir
defmodule AutocompleteTrie do
  @moduledoc """
  A pure functional, frequency-weighted prefix tree for autocomplete.

  Every stored word carries an accumulated integer weight; `suggest/3` returns
  the top-K words for a prefix ranked by descending weight (ties broken
  lexicographically). Every operation returns a new trie — nothing is mutated.

  ## Node structure

      %{children: %{char => node}, weight: non_neg_integer}

  A positive `weight` marks the end of a word. The struct tracks the distinct
  word count so `size/1` is O(1).
  """

  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  @type node_t :: %{children: %{String.t() => node_t}, weight: non_neg_integer}
  @type t :: %__MODULE__{root: node_t, size: non_neg_integer}

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc "Returns an empty trie."
  @spec new() :: t
  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, weight: 0}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  @doc """
  Inserts `word` with `weight` (default 1). Re-inserting a word adds to its
  accumulated weight. Returns the updated trie.
  """
  @spec insert(t, String.t(), pos_integer) :: t
  def insert(%__MODULE__{root: root, size: size}, word, weight \\ 1)
      when is_binary(word) and is_integer(weight) and weight > 0 do
    {new_root, delta} = do_insert(root, String.graphemes(word), weight)
    %__MODULE__{root: new_root, size: size + delta}
  end

  defp do_insert(node, [], weight) do
    delta = if node.weight == 0, do: 1, else: 0
    {%{node | weight: node.weight + weight}, delta}
  end

  defp do_insert(node, [char | rest], weight) do
    child = Map.get(node.children, char, new_node())
    {new_child, delta} = do_insert(child, rest, weight)
    {%{node | children: Map.put(node.children, char, new_child)}, delta}
  end

  # ---------------------------------------------------------------------------
  # Weight / Membership
  # ---------------------------------------------------------------------------

  @doc "Returns the accumulated weight of `word`, or 0 if absent."
  @spec weight(t, String.t()) :: non_neg_integer
  def weight(%__MODULE__{root: root}, word) when is_binary(word) do
    case descend(root, String.graphemes(word)) do
      nil -> 0
      node -> node.weight
    end
  end

  @doc "Returns `true` if the exact `word` has a positive weight."
  @spec member?(t, String.t()) :: boolean
  def member?(%__MODULE__{} = trie, word) when is_binary(word), do: weight(trie, word) > 0

  defp descend(node, []), do: node

  defp descend(node, [char | rest]) do
    case Map.fetch(node.children, char) do
      {:ok, child} -> descend(child, rest)
      :error -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Ranked suggestions
  # ---------------------------------------------------------------------------

  @doc """
  Returns up to `k` words starting with `prefix`, ranked by descending weight
  with lexicographic tie-breaking.
  """
  @spec suggest(t, String.t(), non_neg_integer) :: [String.t()]
  def suggest(%__MODULE__{root: root}, prefix, k)
      when is_binary(prefix) and is_integer(k) and k >= 0 do
    case descend(root, String.graphemes(prefix)) do
      nil ->
        []

      node ->
        node
        |> collect(prefix)
        |> Enum.sort_by(fn {word, weight} -> {-weight, word} end)
        |> Enum.take(k)
        |> Enum.map(fn {word, _weight} -> word end)
    end
  end

  defp collect(node, prefix) do
    base = if node.weight > 0, do: [{prefix, node.weight}], else: []

    Enum.reduce(node.children, base, fn {char, child}, acc ->
      collect(child, prefix <> char) ++ acc
    end)
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  @doc "Removes `word` entirely. Deleting an absent word is a no-op."
  @spec delete(t, String.t()) :: t
  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    case do_delete(root, String.graphemes(word)) do
      :notfound -> trie
      {new_root, :ok} -> %__MODULE__{root: new_root, size: size - 1}
    end
  end

  defp do_delete(node, []) do
    # TODO
  end

  defp do_delete(node, [char | rest]) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Size / Words
  # ---------------------------------------------------------------------------

  @doc "Returns the number of distinct words. O(1)."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns a sorted list of every word in the trie."
  @spec words(t) :: [String.t()]
  def words(%__MODULE__{root: root}) do
    root |> collect("") |> Enum.map(fn {word, _weight} -> word end) |> Enum.sort()
  end
end
```