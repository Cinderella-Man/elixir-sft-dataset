defmodule RadixTrie do
  @moduledoc """
  A purely functional compressed radix trie (Patricia-style prefix tree).

  Unlike a plain trie that stores one character per node, this implementation
  path-compresses: any chain of single-child nodes is collapsed into a single
  edge labeled with a multi-character binary. This keeps the tree shallow and
  the node count proportional to the number of branch points rather than to the
  total number of characters stored.

  Each node has the shape:

      %{edges: %{first_char => %{label: binary, child: node}}, terminal: boolean}

  Edges are keyed by the first character (a one-byte binary) of their label,
  which guarantees that at most one edge of a node can share a prefix with any
  given search string.

  The struct itself tracks the word count, so `size/1` is O(1). Every operation
  returns a new trie; no data is ever mutated in place.

      iex> trie = RadixTrie.new() |> RadixTrie.insert("car") |> RadixTrie.insert("card")
      iex> RadixTrie.member?(trie, "car")
      true
      iex> RadixTrie.member?(trie, "ca")
      false
      iex> RadixTrie.search(trie, "ca")
      ["car", "card"]
  """

  @typedoc "An edge: a compressed label plus the node it points at."
  @type edge :: %{label: binary(), child: node_t()}

  @typedoc "A trie node: edges keyed by their label's first character, plus a terminal flag."
  @type node_t :: %{edges: %{optional(binary()) => edge()}, terminal: boolean()}

  @typedoc "A compressed radix trie."
  @type t :: %__MODULE__{root: node_t(), size: non_neg_integer()}

  defstruct root: %{edges: %{}, terminal: false}, size: 0

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Returns a new, empty trie.

  ## Examples

      iex> RadixTrie.size(RadixTrie.new())
      0
  """
  @spec new() :: t()
  def new, do: %__MODULE__{root: empty_node(), size: 0}

  @doc """
  Inserts `word` into `trie` and returns the updated trie.

  Inserting a word that shares a partial prefix with an existing edge splits
  that edge so the compression invariant is preserved. Inserting a word that is
  already present is a no-op (the size does not change). The empty string is a
  valid word and simply marks the root as terminal.

  ## Examples

      iex> RadixTrie.new() |> RadixTrie.insert("car") |> RadixTrie.insert("cat")
      ...> |> RadixTrie.words()
      ["car", "cat"]
  """
  @spec insert(t(), binary()) :: t()
  def insert(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    {new_root, added?} = do_insert(root, word)
    %__MODULE__{trie | root: new_root, size: if(added?, do: size + 1, else: size)}
  end

  @doc """
  Returns `true` only if the exact `word` was inserted.

  A stored word `"car"` does not make `member?(trie, "ca")` return `true`, since
  `"ca"` ends in the middle of a compressed edge and was never marked terminal.

  ## Examples

      iex> trie = RadixTrie.insert(RadixTrie.new(), "car")
      iex> {RadixTrie.member?(trie, "car"), RadixTrie.member?(trie, "ca")}
      {true, false}
  """
  @spec member?(t(), binary()) :: boolean()
  def member?(%__MODULE__{root: root}, word) when is_binary(word) do
    case locate(root, word) do
      {:exact, node} -> node.terminal
      _other -> false
    end
  end

  @doc """
  Returns a sorted list of every stored word that starts with `prefix`.

  The result includes `prefix` itself when it was inserted. The prefix may end
  in the middle of a compressed edge; matching still works, because the search
  descends into that edge and reconstructs the full words below it. Searching
  with `""` returns every stored word.

  ## Examples

      iex> trie = Enum.reduce(~w(car card cat dog), RadixTrie.new(), &RadixTrie.insert(&2, &1))
      iex> RadixTrie.search(trie, "car")
      ["car", "card"]
      iex> RadixTrie.search(trie, "ca")
      ["car", "card", "cat"]
      iex> RadixTrie.search(trie, "z")
      []
  """
  @spec search(t(), binary()) :: [binary()]
  def search(%__MODULE__{root: root}, prefix) when is_binary(prefix) do
    case locate(root, prefix) do
      {:exact, node} -> node |> collect(prefix, []) |> Enum.sort()
      {:partial, node, remainder} -> node |> collect(prefix <> remainder, []) |> Enum.sort()
      :miss -> []
    end
  end

  @doc """
  Removes `word` from `trie` and returns the updated trie.

  Deleting a word never affects words that extend it: deleting `"car"` leaves
  `"card"` intact. After a removal, any node left with exactly one child and no
  terminal flag of its own is merged back into its parent edge, restoring the
  path-compression invariant. Deleting an absent word is a no-op.

  ## Examples

      iex> trie = RadixTrie.new() |> RadixTrie.insert("car") |> RadixTrie.insert("card")
      iex> trie = RadixTrie.delete(trie, "car")
      iex> {RadixTrie.words(trie), RadixTrie.size(trie)}
      {["card"], 1}
  """
  @spec delete(t(), binary()) :: t()
  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    case do_delete(root, word) do
      {new_root, true} -> %__MODULE__{trie | root: new_root, size: size - 1}
      {_node, false} -> trie
    end
  end

  @doc """
  Returns the number of words currently stored, in O(1).

  ## Examples

      iex> RadixTrie.new() |> RadixTrie.insert("a") |> RadixTrie.insert("a") |> RadixTrie.size()
      1
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc """
  Returns a sorted list of all words stored in the trie.

  ## Examples

      iex> RadixTrie.new() |> RadixTrie.insert("b") |> RadixTrie.insert("a") |> RadixTrie.words()
      ["a", "b"]
  """
  @spec words(t()) :: [binary()]
  def words(%__MODULE__{root: root}), do: root |> collect("", []) |> Enum.sort()

  @doc """
  Returns the total number of nodes in the tree, including the root.

  Thanks to path compression this stays far below the total character count
  whenever words share prefixes: `"romane"` and `"romanus"` occupy four nodes
  (root, the shared `"roman"` branch, and one leaf each) rather than thirteen.

  ## Examples

      iex> RadixTrie.node_count(RadixTrie.new())
      1
      iex> RadixTrie.new() |> RadixTrie.insert("romane") |> RadixTrie.insert("romanus")
      ...> |> RadixTrie.node_count()
      4
  """
  @spec node_count(t()) :: pos_integer()
  def node_count(%__MODULE__{root: root}), do: count_nodes(root)

  # ----------------------------------------------------------------------------
  # Insert
  # ----------------------------------------------------------------------------

  # Returns {new_node, added?} where added? is true when a new word was stored.
  @spec do_insert(node_t(), binary()) :: {node_t(), boolean()}
  defp do_insert(node, "") do
    if node.terminal, do: {node, false}, else: {%{node | terminal: true}, true}
  end

  defp do_insert(node, word) do
    key = head_key(word)

    case Map.fetch(node.edges, key) do
      :error ->
        edge = %{label: word, child: %{empty_node() | terminal: true}}
        {%{node | edges: Map.put(node.edges, key, edge)}, true}

      {:ok, %{label: label} = edge} ->
        common = common_prefix_length(label, word)
        insert_along(node, key, edge, label, word, common)
    end
  end

  # The whole edge label is consumed: recurse into the child with the rest.
  @spec insert_along(node_t(), binary(), edge(), binary(), binary(), pos_integer()) ::
          {node_t(), boolean()}
  defp insert_along(node, key, edge, label, word, common) when common == byte_size(label) do
    rest = binary_part(word, common, byte_size(word) - common)
    {new_child, added?} = do_insert(edge.child, rest)
    {put_edge(node, key, %{edge | child: new_child}), added?}
  end

  # Only part of the edge label matches: split the edge at the divergence point.
  defp insert_along(node, key, edge, label, word, common) do
    label_rest = binary_part(label, common, byte_size(label) - common)
    word_rest = binary_part(word, common, byte_size(word) - common)
    shared = binary_part(label, 0, common)

    lower = %{
      edges: %{head_key(label_rest) => %{label: label_rest, child: edge.child}},
      terminal: false
    }

    {branch, added?} = do_insert(lower, word_rest)
    {put_edge(node, key, %{label: shared, child: branch}), added?}
  end

  # ----------------------------------------------------------------------------
  # Delete
  # ----------------------------------------------------------------------------

  # Returns {new_node, removed?} where removed? is true when a word was dropped.
  @spec do_delete(node_t(), binary()) :: {node_t(), boolean()}
  defp do_delete(node, "") do
    if node.terminal, do: {compress(%{node | terminal: false}), true}, else: {node, false}
  end

  defp do_delete(node, word) do
    key = head_key(word)

    with {:ok, %{label: label} = edge} <- Map.fetch(node.edges, key),
         true <- prefix?(word, label) do
      rest = binary_part(word, byte_size(label), byte_size(word) - byte_size(label))

      case do_delete(edge.child, rest) do
        {_child, false} ->
          {node, false}

        {child, true} ->
          {prune(node, key, %{edge | label: label, child: child}), true}
      end
    else
      _other -> {node, false}
    end
  end

  # Drops an edge whose child became empty, otherwise re-merges compressible chains.
  @spec prune(node_t(), binary(), edge()) :: node_t()
  defp prune(node, key, %{child: child} = edge) do
    if child.terminal or map_size(child.edges) > 0 do
      node
      |> put_edge(key, merge(edge))
      |> compress()
    else
      %{node | edges: Map.delete(node.edges, key)}
      |> compress()
    end
  end

  # A non-terminal child with exactly one child of its own collapses into this edge.
  @spec merge(edge()) :: edge()
  defp merge(%{label: label, child: child} = edge) do
    case {child.terminal, map_size(child.edges)} do
      {false, 1} ->
        [%{label: sub_label, child: grandchild}] = Map.values(child.edges)
        %{label: label <> sub_label, child: grandchild}

      _other ->
        edge
    end
  end

  # Re-merges this node's own single remaining edge chain, keeping the tree compressed.
  @spec compress(node_t()) :: node_t()
  defp compress(%{edges: edges} = node) when map_size(edges) == 1 do
    [{key, edge}] = Map.to_list(edges)
    merged = merge(edge)
    if merged == edge, do: node, else: %{node | edges: %{key => merged}}
  end

  defp compress(node), do: node

  # ----------------------------------------------------------------------------
  # Lookup
  # ----------------------------------------------------------------------------

  # Walks `string` down the tree. Returns:
  #   {:exact, node}                -> the string ended exactly at `node`
  #   {:partial, node, remainder}   -> the string ended mid-edge; `remainder` is
  #                                    the rest of that edge's label
  #   :miss                         -> the string is not a prefix of anything stored
  @spec locate(node_t(), binary()) :: {:exact, node_t()} | {:partial, node_t(), binary()} | :miss
  defp locate(node, ""), do: {:exact, node}

  defp locate(node, string) do
    case Map.fetch(node.edges, head_key(string)) do
      :error ->
        :miss

      {:ok, %{label: label, child: child}} ->
        cond do
          prefix?(string, label) ->
            locate(child, binary_part(string, byte_size(label), byte_size(string) - byte_size(label)))

          prefix?(label, string) ->
            remainder = binary_part(label, byte_size(string), byte_size(label) - byte_size(string))
            {:partial, child, remainder}

          true ->
            :miss
        end
    end
  end

  # ----------------------------------------------------------------------------
  # Traversal helpers
  # ----------------------------------------------------------------------------

  @spec collect(node_t(), binary(), [binary()]) :: [binary()]
  defp collect(node, acc_word, acc) do
    acc = if node.terminal, do: [acc_word | acc], else: acc

    Enum.reduce(node.edges, acc, fn {_key, %{label: label, child: child}}, inner ->
      collect(child, acc_word <> label, inner)
    end)
  end

  @spec count_nodes(node_t()) :: pos_integer()
  defp count_nodes(node) do
    Enum.reduce(node.edges, 1, fn {_key, %{child: child}}, acc -> acc + count_nodes(child) end)
  end

  # ----------------------------------------------------------------------------
  # Small utilities
  # ----------------------------------------------------------------------------

  @spec empty_node() :: node_t()
  defp empty_node, do: %{edges: %{}, terminal: false}

  @spec put_edge(node_t(), binary(), edge()) :: node_t()
  defp put_edge(node, key, edge), do: %{node | edges: Map.put(node.edges, key, edge)}

  @spec head_key(binary()) :: binary()
  defp head_key(<<char::binary-size(1), _rest::binary>>), do: char

  @spec prefix?(binary(), binary()) :: boolean()
  defp prefix?(string, candidate), do: :binary.longest_common_prefix([string, candidate]) ==
                                        byte_size(candidate)

  @spec common_prefix_length(binary(), binary()) :: non_neg_integer()
  defp common_prefix_length(a, b), do: :binary.longest_common_prefix([a, b])
end