# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule RadixTrieTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction and basic membership
  # -------------------------------------------------------

  test "new trie is empty" do
    t = RadixTrie.new()
    assert RadixTrie.size(t) == 0
    assert RadixTrie.words(t) == []
    assert RadixTrie.node_count(t) == 1
  end

  test "insert and member? for a single word" do
    t = RadixTrie.new() |> RadixTrie.insert("hello")
    assert RadixTrie.member?(t, "hello") == true
    assert RadixTrie.member?(t, "hell") == false
    assert RadixTrie.member?(t, "helloo") == false
    assert RadixTrie.member?(t, "") == false
    # one edge "hello" => root + leaf
    assert RadixTrie.node_count(t) == 2
  end

  test "insert multiple words with shared prefix" do
    # TODO
  end

  test "size tracks inserted words" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("a")
      |> RadixTrie.insert("ab")
      |> RadixTrie.insert("abc")

    assert RadixTrie.size(t) == 3
  end

  test "inserting the same word twice doesn't increase size" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("hello")
      |> RadixTrie.insert("hello")

    assert RadixTrie.size(t) == 1
    assert RadixTrie.node_count(t) == 2
  end

  # -------------------------------------------------------
  # Compression invariant
  # -------------------------------------------------------

  test "path compression keeps node count small" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("care")
      |> RadixTrie.insert("cat")
      |> RadixTrie.insert("dog")

    # root, "ca" node, "car" node, "card" leaf, "care" leaf, "cat" leaf, "dog" leaf
    assert RadixTrie.node_count(t) == 7
  end

  test "edge splitting on partial overlap" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("test")
      |> RadixTrie.insert("team")

    assert RadixTrie.member?(t, "test") == true
    assert RadixTrie.member?(t, "team") == true
    assert RadixTrie.member?(t, "te") == false
    # root, "te" branch, "st" leaf, "am" leaf
    assert RadixTrie.node_count(t) == 4
  end

  # -------------------------------------------------------
  # Prefix search
  # -------------------------------------------------------

  test "search returns all words with the given prefix, sorted" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("care")
      |> RadixTrie.insert("careful")
      |> RadixTrie.insert("cat")
      |> RadixTrie.insert("dog")

    assert RadixTrie.search(t, "car") == ["car", "card", "care", "careful"]
    assert RadixTrie.search(t, "care") == ["care", "careful"]
    assert RadixTrie.search(t, "cat") == ["cat"]
    assert RadixTrie.search(t, "d") == ["dog"]
  end

  test "search where prefix ends in the middle of a compressed edge" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("cat")

    # "ca" is not a stored word, but a stored edge is "ca"
    assert RadixTrie.member?(t, "ca") == false
    assert RadixTrie.search(t, "ca") == ["car", "card", "cat"]
    assert RadixTrie.search(t, "c") == ["car", "card", "cat"]
  end

  test "search with empty prefix returns all words sorted" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("banana")
      |> RadixTrie.insert("apple")
      |> RadixTrie.insert("cherry")

    assert RadixTrie.search(t, "") == ["apple", "banana", "cherry"]
  end

  test "search with prefix that matches nothing returns empty list" do
    t = RadixTrie.new() |> RadixTrie.insert("hello")
    assert RadixTrie.search(t, "xyz") == []
    assert RadixTrie.search(t, "help") == []
  end

  test "search on empty trie returns empty list" do
    assert RadixTrie.search(RadixTrie.new(), "a") == []
  end

  # -------------------------------------------------------
  # words/1
  # -------------------------------------------------------

  test "words returns all inserted words sorted" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("zebra")
      |> RadixTrie.insert("apple")
      |> RadixTrie.insert("mango")
      |> RadixTrie.insert("apricot")

    assert RadixTrie.words(t) == ["apple", "apricot", "mango", "zebra"]
  end

  # -------------------------------------------------------
  # Deletion
  # -------------------------------------------------------

  test "delete removes a word" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("hello")
      |> RadixTrie.delete("hello")

    assert RadixTrie.member?(t, "hello") == false
    assert RadixTrie.size(t) == 0
  end

  test "delete of a prefix word doesn't affect longer words" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.delete("car")

    assert RadixTrie.member?(t, "car") == false
    assert RadixTrie.member?(t, "card") == true
    assert RadixTrie.size(t) == 1
  end

  test "delete re-merges edges to restore compression" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("care")
      |> RadixTrie.insert("cat")
      |> RadixTrie.insert("dog")

    assert RadixTrie.node_count(t) == 7

    t2 = RadixTrie.delete(t, "cat")
    assert RadixTrie.member?(t2, "cat") == false
    assert RadixTrie.search(t2, "car") == ["car", "card", "care"]
    # dropping "cat" leaves "ca" with one child ("r..."), which re-merges
    assert RadixTrie.node_count(t2) == 5
  end

  test "deleting a non-existent word changes nothing" do
    t = RadixTrie.new() |> RadixTrie.insert("hello")
    t2 = RadixTrie.delete(t, "world")

    assert RadixTrie.member?(t2, "hello") == true
    assert RadixTrie.size(t2) == 1
  end

  test "deleting from empty trie returns empty trie" do
    t = RadixTrie.new() |> RadixTrie.delete("anything")
    assert RadixTrie.size(t) == 0
  end

  # -------------------------------------------------------
  # Immutability
  # -------------------------------------------------------

  test "insert returns a new trie, original is unchanged" do
    t1 = RadixTrie.new()
    t2 = RadixTrie.insert(t1, "hello")

    assert RadixTrie.size(t1) == 0
    assert RadixTrie.member?(t1, "hello") == false
    assert RadixTrie.size(t2) == 1
    assert RadixTrie.member?(t2, "hello") == true
  end

  test "delete returns a new trie, original is unchanged" do
    t1 = RadixTrie.new() |> RadixTrie.insert("hello")
    t2 = RadixTrie.delete(t1, "hello")

    assert RadixTrie.member?(t1, "hello") == true
    assert RadixTrie.member?(t2, "hello") == false
  end

  # -------------------------------------------------------
  # Larger dataset
  # -------------------------------------------------------

  test "larger dataset — 100 words" do
    words = for i <- 1..100, do: "word#{String.pad_leading("#{i}", 3, "0")}"

    t = Enum.reduce(words, RadixTrie.new(), &RadixTrie.insert(&2, &1))

    assert RadixTrie.size(t) == 100
    assert RadixTrie.member?(t, "word001") == true
    assert RadixTrie.member?(t, "word100") == true
    assert RadixTrie.member?(t, "word101") == false

    results = RadixTrie.search(t, "word0")
    assert length(results) == 99

    assert RadixTrie.words(t) == Enum.sort(words)
    # compression: far fewer nodes than the ~700 characters stored
    assert RadixTrie.node_count(t) < 200
  end
end
```
