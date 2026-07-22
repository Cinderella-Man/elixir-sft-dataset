Implement the private `do_insert/2` function (the recursive workhorse behind
`insert/2`). It takes a trie `node` and the remaining `word` (a binary) still to
be inserted, and returns a `{new_node, added}` tuple where `added` is `1` if a
brand-new word was stored and `0` if the word was already present.

It has two clauses:

1. When `word` is `""`, the whole word has been consumed and this node marks its
   end. If the node is already `terminal`, the word existed — return `{node, 0}`.
   Otherwise flip `terminal` to `true` and return `{updated_node, 1}`.

2. Otherwise, take `key = String.first(word)` and look up the matching edge in
   `node.edges`:

   - If there is **no** edge for `key` (`:error`), create a leaf node
     (`%{edges: %{}, terminal: true}`), attach it under an edge whose `label` is
     the entire `word`, put that edge in `node.edges` under `key`, and return
     `{updated_node, 1}`.

   - If an edge `%{label: label, child: child}` exists, compute the common prefix
     of `label` and `word` via `common_prefix/2`, and let `plen`, `llen`, `wlen`
     be the grapheme lengths of the common prefix, the label, and the word. Then
     branch on three cases:

     - **`plen == llen`** — the edge label is fully shared, so descend: recurse
       with `do_insert(child, drop(word, plen))`, rebuild the edge with the new
       child, reinsert it under `key`, and propagate the `added` count.

     - **`plen == wlen`** — the word is a proper prefix of the label, so split the
       edge. The label's remaining suffix (`drop(label, plen)`) becomes an edge to
       the original `child`, held by a new **terminal** intermediate node whose
       single edge is keyed by that suffix's first character. Replace the original
       edge with `%{label: common_prefix, child: mid}` and return `{updated, 1}`.

     - **otherwise** (partial overlap) — branch into a fresh **non-terminal**
       intermediate node holding two edges: one for the label's suffix pointing at
       the original `child`, and one for the word's suffix pointing at a new
       terminal leaf, each keyed by its suffix's first character. Replace the
       original edge with `%{label: common_prefix, child: mid}` and return
       `{updated, 1}`.

Every branch returns a new node without mutating the original.

```elixir
defmodule RadixTrie do
  @moduledoc """
  A pure functional, path-compressed radix trie (Patricia trie).

  Chains of single-child nodes are collapsed into one edge labeled with a
  multi-character string, keeping the tree shallow. Every operation returns a
  new trie — nothing is mutated.

  ## Node structure

      %{edges: %{first_char => %{label: binary, child: node}}, terminal: boolean}

  The struct wraps the root node and tracks the total word count so `size/1`
  is O(1).
  """

  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  @type node_t :: %{
          edges: %{String.t() => %{label: String.t(), child: node_t}},
          terminal: boolean
        }
  @type t :: %__MODULE__{root: node_t, size: non_neg_integer}

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc "Returns an empty trie."
  @spec new() :: t
  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{edges: %{}, terminal: false}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  @doc "Inserts `word` into the trie. Returns the updated trie."
  @spec insert(t, String.t()) :: t
  def insert(%__MODULE__{root: root, size: size}, word) when is_binary(word) do
    {new_root, added} = do_insert(root, word)
    %__MODULE__{root: new_root, size: size + added}
  end

  defp do_insert(node, "") do
    # TODO
  end

  defp do_insert(node, word) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  @doc "Returns `true` only if the exact `word` was inserted."
  @spec member?(t, String.t()) :: boolean
  def member?(%__MODULE__{root: root}, word) when is_binary(word), do: do_member(root, word)

  defp do_member(node, ""), do: node.terminal

  defp do_member(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        false

      {:ok, %{label: label, child: child}} ->
        if String.starts_with?(word, label) do
          do_member(child, drop(word, String.length(label)))
        else
          false
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Prefix search
  # ---------------------------------------------------------------------------

  @doc """
  Returns a sorted list of every word that starts with `prefix`.

  The prefix may end in the middle of a compressed edge.
  """
  @spec search(t, String.t()) :: [String.t()]
  def search(%__MODULE__{root: root}, prefix) when is_binary(prefix) do
    case locate(root, prefix, "") do
      :nomatch -> []
      {node, path} -> collect(node, path) |> Enum.sort()
    end
  end

  # Walk down consuming `prefix`; `acc` is the actual path string to `node`.
  defp locate(node, "", acc), do: {node, acc}

  defp locate(node, prefix, acc) do
    key = String.first(prefix)

    case Map.fetch(node.edges, key) do
      :error ->
        :nomatch

      {:ok, %{label: label, child: child}} ->
        cond do
          String.starts_with?(prefix, label) ->
            locate(child, drop(prefix, String.length(label)), acc <> label)

          String.starts_with?(label, prefix) ->
            {child, acc <> label}

          true ->
            :nomatch
        end
    end
  end

  defp collect(node, path) do
    base = if node.terminal, do: [path], else: []

    Enum.reduce(node.edges, base, fn {_key, %{label: label, child: child}}, acc ->
      collect(child, path <> label) ++ acc
    end)
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  @doc """
  Removes `word`. Restores the compression invariant by re-merging any node
  left with a single child. Deleting an absent word is a no-op.
  """
  @spec delete(t, String.t()) :: t
  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    case do_delete(root, word) do
      :notfound -> trie
      {new_root, :ok} -> %__MODULE__{root: new_root, size: size - 1}
    end
  end

  defp do_delete(node, "") do
    if node.terminal, do: {%{node | terminal: false}, :ok}, else: :notfound
  end

  defp do_delete(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        :notfound

      {:ok, %{label: label, child: child} = edge} ->
        if String.starts_with?(word, label) do
          case do_delete(child, drop(word, String.length(label))) do
            :notfound -> :notfound
            {new_child, :ok} -> {cleanup_edge(node, key, edge, new_child), :ok}
          end
        else
          :notfound
        end
    end
  end

  defp cleanup_edge(node, key, edge, new_child) do
    cond do
      # dead-end leaf — prune it
      not new_child.terminal and map_size(new_child.edges) == 0 ->
        %{node | edges: Map.delete(node.edges, key)}

      # single non-terminal child — re-merge the labels
      not new_child.terminal and map_size(new_child.edges) == 1 ->
        [{_k, grand}] = Map.to_list(new_child.edges)
        merged = %{edge | label: edge.label <> grand.label, child: grand.child}
        %{node | edges: Map.put(node.edges, key, merged)}

      true ->
        %{node | edges: Map.put(node.edges, key, %{edge | child: new_child})}
    end
  end

  # ---------------------------------------------------------------------------
  # Size / Words / Node count
  # ---------------------------------------------------------------------------

  @doc "Returns the number of words in the trie. O(1)."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns a sorted list of every word in the trie."
  @spec words(t) :: [String.t()]
  def words(%__MODULE__{root: root}), do: collect(root, "") |> Enum.sort()

  @doc "Returns the total number of nodes, including the root."
  @spec node_count(t) :: pos_integer
  def node_count(%__MODULE__{root: root}), do: count_nodes(root)

  defp count_nodes(node) do
    Enum.reduce(node.edges, 1, fn {_key, %{child: child}}, acc -> acc + count_nodes(child) end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp drop(str, n), do: String.slice(str, n, String.length(str))

  defp common_prefix(a, b), do: do_common(String.graphemes(a), String.graphemes(b), [])

  defp do_common([x | xs], [x | ys], acc), do: do_common(xs, ys, [x | acc])
  defp do_common(_, _, acc), do: acc |> Enum.reverse() |> Enum.join()
end
```