# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule WildcardTrie do
  @moduledoc """
  A pure functional prefix tree that supports wildcard pattern search.

  `matches?/2` and `matching/2` interpret a `.` in the query as a wildcard for
  exactly one character; `member?/2` is a strict literal lookup. A pattern only
  matches words of the same length. Every operation returns a new trie —
  nothing is mutated.

  ## Node structure

      %{children: %{char => node}, terminal: boolean}

  The struct tracks the word count so `size/1` is O(1).
  """

  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  @wildcard "."

  @type node_t :: %{children: %{String.t() => node_t}, terminal: boolean}
  @type t :: %__MODULE__{root: node_t, size: non_neg_integer}

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc "Returns an empty trie."
  @spec new() :: t
  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, terminal: false}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  @doc "Inserts `word` into the trie. Returns the updated trie."
  @spec insert(t, String.t()) :: t
  def insert(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if exact?(root, chars) do
      trie
    else
      %__MODULE__{root: do_insert(root, chars), size: size + 1}
    end
  end

  defp do_insert(node, []), do: %{node | terminal: true}

  defp do_insert(node, [char | rest]) do
    child = Map.get(node.children, char, new_node())
    %{node | children: Map.put(node.children, char, do_insert(child, rest))}
  end

  # ---------------------------------------------------------------------------
  # Exact membership
  # ---------------------------------------------------------------------------

  @doc "Returns `true` only if the exact literal `word` was inserted."
  @spec member?(t, String.t()) :: boolean
  def member?(%__MODULE__{root: root}, word) when is_binary(word) do
    exact?(root, String.graphemes(word))
  end

  defp exact?(%{terminal: terminal}, []), do: terminal

  defp exact?(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> exact?(child, rest)
      :error -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Wildcard matching
  # ---------------------------------------------------------------------------

  @doc "Returns `true` if any stored word matches `pattern` (`.` = any char)."
  @spec matches?(t, String.t()) :: boolean
  def matches?(%__MODULE__{root: root}, pattern) when is_binary(pattern) do
    do_matches?(root, String.graphemes(pattern))
  end

  defp do_matches?(%{terminal: terminal}, []), do: terminal

  defp do_matches?(%{children: children}, [@wildcard | rest]) do
    Enum.any?(children, fn {_char, child} -> do_matches?(child, rest) end)
  end

  defp do_matches?(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> do_matches?(child, rest)
      :error -> false
    end
  end

  @doc "Returns a sorted list of every stored word matching `pattern`."
  @spec matching(t, String.t()) :: [String.t()]
  def matching(%__MODULE__{root: root}, pattern) when is_binary(pattern) do
    root |> do_matching(String.graphemes(pattern), "") |> Enum.sort()
  end

  defp do_matching(%{terminal: terminal}, [], acc) do
    if terminal, do: [acc], else: []
  end

  defp do_matching(%{children: children}, [@wildcard | rest], acc) do
    Enum.flat_map(children, fn {char, child} -> do_matching(child, rest, acc <> char) end)
  end

  defp do_matching(%{children: children}, [char | rest], acc) do
    case Map.fetch(children, char) do
      {:ok, child} -> do_matching(child, rest, acc <> char)
      :error -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  @doc "Removes the exact `word`. Deleting an absent word is a no-op."
  @spec delete(t, String.t()) :: t
  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if exact?(root, chars) do
      %__MODULE__{root: do_delete(root, chars), size: size - 1}
    else
      trie
    end
  end

  defp do_delete(node, []), do: %{node | terminal: false}

  defp do_delete(node, [char | rest]) do
    child = Map.fetch!(node.children, char)
    new_child = do_delete(child, rest)

    if not new_child.terminal and map_size(new_child.children) == 0 do
      %{node | children: Map.delete(node.children, char)}
    else
      %{node | children: Map.put(node.children, char, new_child)}
    end
  end

  # ---------------------------------------------------------------------------
  # Size / Words
  # ---------------------------------------------------------------------------

  @doc "Returns the number of words in the trie. O(1)."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns a sorted list of every word in the trie."
  @spec words(t) :: [String.t()]
  def words(%__MODULE__{root: root}), do: root |> collect("") |> Enum.sort()

  defp collect(%{terminal: terminal, children: children}, acc) do
    base = if terminal, do: [acc], else: []

    Enum.reduce(children, base, fn {char, child}, words ->
      collect(child, acc <> char) ++ words
    end)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule WildcardTrieTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction and exact membership
  # -------------------------------------------------------

  test "new trie is empty" do
    t = WildcardTrie.new()
    assert WildcardTrie.size(t) == 0
    assert WildcardTrie.words(t) == []
    assert WildcardTrie.matches?(t, "a") == false
    assert WildcardTrie.matching(t, "a") == []
  end

  test "insert and exact member?" do
    # TODO
  end

  test "member? does not interpret dots as wildcards" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")

    # "." here is a literal, so no stored word equals "bad" via wildcard
    assert WildcardTrie.member?(t, ".ad") == false
    assert WildcardTrie.member?(t, "bad") == true
  end

  test "size and words" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("mad")
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")

    assert WildcardTrie.size(t) == 3
    assert WildcardTrie.words(t) == ["bad", "dad", "mad"]
  end

  test "inserting the same word twice doesn't grow size" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("bad")

    assert WildcardTrie.size(t) == 1
  end

  # -------------------------------------------------------
  # Wildcard matching — boolean
  # -------------------------------------------------------

  test "matches? with a leading wildcard" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")
      |> WildcardTrie.insert("mad")

    assert WildcardTrie.matches?(t, ".ad") == true
    assert WildcardTrie.matches?(t, "b..") == true
    assert WildcardTrie.matches?(t, "...") == true
    assert WildcardTrie.matches?(t, "..d") == true
  end

  test "matches? respects length exactly" do
    t = WildcardTrie.new() |> WildcardTrie.insert("bad")

    assert WildcardTrie.matches?(t, "..") == false
    assert WildcardTrie.matches?(t, "....") == false
    assert WildcardTrie.matches?(t, "...") == true
  end

  test "matches? with no wildcard behaves like exact lookup" do
    t = WildcardTrie.new() |> WildcardTrie.insert("bad")
    assert WildcardTrie.matches?(t, "bad") == true
    assert WildcardTrie.matches?(t, "bat") == false
  end

  test "matches? returns false when nothing matches" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")

    assert WildcardTrie.matches?(t, ".at") == false
    assert WildcardTrie.matches?(t, "x..") == false
  end

  # -------------------------------------------------------
  # Wildcard matching — collecting words
  # -------------------------------------------------------

  test "matching returns all matches sorted" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")
      |> WildcardTrie.insert("mad")
      |> WildcardTrie.insert("pad")
      |> WildcardTrie.insert("pat")

    assert WildcardTrie.matching(t, ".ad") == ["bad", "dad", "mad", "pad"]
    assert WildcardTrie.matching(t, "pa.") == ["pad", "pat"]
    assert WildcardTrie.matching(t, "p..") == ["pad", "pat"]
    assert WildcardTrie.matching(t, "...") == ["bad", "dad", "mad", "pad", "pat"]
  end

  test "matching with no wildcard returns at most the exact word" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("dad")
      |> WildcardTrie.insert("dot")

    assert WildcardTrie.matching(t, "dad") == ["dad"]
    assert WildcardTrie.matching(t, "dab") == []
  end

  test "matching across mixed lengths only returns same-length words" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("go")
      |> WildcardTrie.insert("god")
      |> WildcardTrie.insert("gods")

    assert WildcardTrie.matching(t, "g..") == ["god"]
    assert WildcardTrie.matching(t, "g.") == ["go"]
    assert WildcardTrie.matching(t, "g...") == ["gods"]
  end

  # -------------------------------------------------------
  # Deletion
  # -------------------------------------------------------

  test "delete removes an exact word" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.delete("bad")

    assert WildcardTrie.member?(t, "bad") == false
    assert WildcardTrie.size(t) == 0
    assert WildcardTrie.matches?(t, ".ad") == false
  end

  test "delete of a word doesn't affect same-length siblings" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")
      |> WildcardTrie.insert("mad")
      |> WildcardTrie.delete("bad")

    assert WildcardTrie.matching(t, ".ad") == ["dad", "mad"]
    assert WildcardTrie.size(t) == 2
  end

  test "delete of a prefix word doesn't affect longer words" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("go")
      |> WildcardTrie.insert("god")
      |> WildcardTrie.delete("go")

    assert WildcardTrie.member?(t, "go") == false
    assert WildcardTrie.member?(t, "god") == true
    assert WildcardTrie.matching(t, "g..") == ["god"]
    assert WildcardTrie.size(t) == 1
  end

  test "deleting a non-existent word changes nothing" do
    t = WildcardTrie.new() |> WildcardTrie.insert("bad")
    t2 = WildcardTrie.delete(t, "mad")

    assert WildcardTrie.member?(t2, "bad") == true
    assert WildcardTrie.size(t2) == 1
  end

  test "deleting from empty trie returns empty trie" do
    t = WildcardTrie.new() |> WildcardTrie.delete("anything")
    assert WildcardTrie.size(t) == 0
  end

  # -------------------------------------------------------
  # Immutability
  # -------------------------------------------------------

  test "insert returns a new trie, original is unchanged" do
    t1 = WildcardTrie.new()
    t2 = WildcardTrie.insert(t1, "bad")

    assert WildcardTrie.size(t1) == 0
    assert WildcardTrie.member?(t1, "bad") == false
    assert WildcardTrie.member?(t2, "bad") == true
  end

  test "delete returns a new trie, original is unchanged" do
    t1 = WildcardTrie.new() |> WildcardTrie.insert("bad")
    t2 = WildcardTrie.delete(t1, "bad")

    assert WildcardTrie.member?(t1, "bad") == true
    assert WildcardTrie.member?(t2, "bad") == false
  end

  # -------------------------------------------------------
  # Larger dataset
  # -------------------------------------------------------

  test "larger dataset — wildcard queries over 100 words" do
    words = for i <- 1..100, do: "w#{String.pad_leading("#{i}", 3, "0")}"

    t = Enum.reduce(words, WildcardTrie.new(), &WildcardTrie.insert(&2, &1))

    assert WildcardTrie.size(t) == 100
    # every word has form "w" + 3 digits => "w..." matches all
    assert length(WildcardTrie.matching(t, "w...")) == 100
    # "w00." matches w001..w009
    assert WildcardTrie.matching(t, "w00.") ==
             for(i <- 1..9, do: "w00#{i}")

    assert WildcardTrie.matches?(t, "w050") == true
    assert WildcardTrie.matches?(t, "w101") == false
    assert WildcardTrie.words(t) == Enum.sort(words)
  end

  test "member? finds a stored word that contains a literal dot" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("b.d")
      |> WildcardTrie.insert("bad")

    assert WildcardTrie.member?(t, "b.d") == true
    assert WildcardTrie.member?(t, "bad") == true
    assert WildcardTrie.size(t) == 2

    only_dot = WildcardTrie.new() |> WildcardTrie.insert("b.d")
    assert WildcardTrie.member?(only_dot, "b.d") == true
    assert WildcardTrie.member?(only_dot, "bad") == false
  end

  test "wildcard pattern also matches a stored literal dot character" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("b.d")
      |> WildcardTrie.insert("bad")

    assert WildcardTrie.matches?(t, "b.d") == true
    assert WildcardTrie.matching(t, "b.d") == ["b.d", "bad"]
    assert WildcardTrie.matching(t, "...") == ["b.d", "bad"]
    assert WildcardTrie.matching(t, ".a.") == ["bad"]
  end

  test "deleting the same word twice leaves the trie empty and size at zero" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.delete("bad")
      |> WildcardTrie.delete("bad")

    assert WildcardTrie.size(t) == 0
    assert WildcardTrie.words(t) == []
    assert WildcardTrie.member?(t, "bad") == false
    assert WildcardTrie.matches?(t, "...") == false
  end

  test "deleting car leaves card fully intact" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("car")
      |> WildcardTrie.insert("card")
      |> WildcardTrie.delete("car")

    assert WildcardTrie.member?(t, "car") == false
    assert WildcardTrie.member?(t, "card") == true
    assert WildcardTrie.matching(t, "car.") == ["card"]
    assert WildcardTrie.matching(t, "...") == []
    assert WildcardTrie.words(t) == ["card"]
    assert WildcardTrie.size(t) == 1
  end

  test "empty string is storable and retrievable like any other word" do
    t = WildcardTrie.new() |> WildcardTrie.insert("")

    assert WildcardTrie.member?(t, "") == true
    assert WildcardTrie.size(t) == 1
    assert WildcardTrie.words(t) == [""]
    assert WildcardTrie.matches?(t, "") == true
    assert WildcardTrie.matching(t, "") == [""]

    t2 = WildcardTrie.delete(t, "")
    assert WildcardTrie.member?(t2, "") == false
    assert WildcardTrie.size(t2) == 0
  end
end
```
