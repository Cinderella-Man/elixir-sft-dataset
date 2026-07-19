# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `count_nodes` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Build me a **compressed radix trie** (a Patricia-style prefix tree) in an Elixir module called `RadixTrie`. Unlike a plain character-per-node trie, this one must **path-compress**: any chain of single-child nodes is collapsed into one edge labeled with a multi-character string. This keeps the tree shallow and the node count small, which is the whole point of the exercise.

Keep it purely functional — no GenServer, no ETS. Just a struct and functions that return new tries.

API I need:

- `RadixTrie.new()` returns an empty trie.
- `RadixTrie.insert(trie, word)` inserts a word (string) and returns the updated trie. Inserting a word that shares a prefix with an existing edge must **split** that edge as needed so the compression invariant holds.
- `RadixTrie.member?(trie, word)` returns `true` only if the exact word was inserted. A stored word "car" must NOT make `member?("ca")` return `true` unless "ca" was inserted on its own.
- `RadixTrie.search(trie, prefix)` returns a sorted list of every word that starts with `prefix` (including `prefix` itself if it was inserted). The prefix may end in the *middle* of a compressed edge — that must still work. An empty prefix matches every stored word.
- `RadixTrie.delete(trie, word)` removes a word and returns the updated trie. Deleting "car" must not affect "card". After a deletion, if a node is left with a single child, **re-merge** the edges so the compression invariant is restored. Deleting an absent word is a no-op.
- `RadixTrie.size(trie)` returns the count of words currently stored (O(1)).
- `RadixTrie.words(trie)` returns a sorted list of all words.
- `RadixTrie.node_count(trie)` returns the total number of nodes in the tree, including the root. An empty trie has exactly 1 node (the root); a trie holding a single word has 2 (the root plus one leaf). Because of compression, this count must be much smaller than the total character count when words share prefixes.

Suggested node shape: `%{edges: %{first_char => %{label: binary, child: node}, ...}, terminal: boolean}`, with the struct also tracking the word count so `size/1` is O(1). Every operation returns a new trie without mutating the original.

No external dependencies. Single file with the `RadixTrie` module.

## The module with `count_nodes` missing

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
    if node.terminal, do: {node, 0}, else: {%{node | terminal: true}, 1}
  end

  defp do_insert(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        leaf = %{edges: %{}, terminal: true}
        edge = %{label: word, child: leaf}
        {%{node | edges: Map.put(node.edges, key, edge)}, 1}

      {:ok, %{label: label, child: child} = edge} ->
        cp = common_prefix(label, word)
        plen = String.length(cp)
        llen = String.length(label)
        wlen = String.length(word)

        cond do
          # whole edge label is consumed — descend into the child
          plen == llen ->
            {new_child, added} = do_insert(child, drop(word, plen))
            new_edge = %{edge | child: new_child}
            {%{node | edges: Map.put(node.edges, key, new_edge)}, added}

          # the word is a proper prefix of the edge label — split the edge
          plen == wlen ->
            suffix = drop(label, plen)
            old_edge = %{label: suffix, child: child}
            mid = %{edges: %{String.first(suffix) => old_edge}, terminal: true}
            {%{node | edges: Map.put(node.edges, key, %{label: cp, child: mid})}, 1}

          # partial overlap — branch into a fresh intermediate node
          true ->
            label_suffix = drop(label, plen)
            word_suffix = drop(word, plen)
            old_edge = %{label: label_suffix, child: child}
            new_leaf = %{edges: %{}, terminal: true}
            new_edge = %{label: word_suffix, child: new_leaf}

            mid = %{
              edges: %{
                String.first(label_suffix) => old_edge,
                String.first(word_suffix) => new_edge
              },
              terminal: false
            }

            {%{node | edges: Map.put(node.edges, key, %{label: cp, child: mid})}, 1}
        end
    end
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
    # TODO
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

Give me only the complete implementation of `count_nodes` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
