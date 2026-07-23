# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule Trie do
  @moduledoc """
  A pure functional prefix tree (trie) backed by nested maps.

  Every operation returns a new trie — nothing is mutated.

  ## Node structure

      %{children: %{char => node}, end_of_word: boolean}

  The top-level trie is simply the root node wrapped in a struct that also
  tracks the total word count so `size/1` is O(1).
  """

  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  @type trie_node :: %{children: %{String.t() => trie_node}, end_of_word: boolean}
  @type t :: %__MODULE__{root: trie_node, size: non_neg_integer}

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc "Returns an empty trie."
  @spec new() :: t
  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, end_of_word: false}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  @doc "Inserts `word` into the trie. Returns the updated trie."
  @spec insert(t, String.t()) :: t
  def insert(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if word_exists?(root, chars) do
      trie
    else
      %__MODULE__{root: do_insert(root, chars), size: size + 1}
    end
  end

  defp do_insert(node, []) do
    %{node | end_of_word: true}
  end

  defp do_insert(node, [char | rest]) do
    child = Map.get(node.children, char, new_node())
    updated_child = do_insert(child, rest)
    %{node | children: Map.put(node.children, char, updated_child)}
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  @doc """
  Returns `true` if `word` was explicitly inserted, `false` otherwise.

  A prefix that was never inserted on its own will return `false`.
  """
  @spec member?(t, String.t()) :: boolean
  def member?(%__MODULE__{root: root}, word) when is_binary(word) do
    word_exists?(root, String.graphemes(word))
  end

  defp word_exists?(_node, _chars)

  defp word_exists?(%{end_of_word: eow}, []), do: eow

  defp word_exists?(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> word_exists?(child, rest)
      :error -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Prefix search
  # ---------------------------------------------------------------------------

  @doc """
  Returns a sorted list of every word that starts with `prefix`.

  If `prefix` itself was inserted as a word it is included in the result.
  """
  @spec search(t, String.t()) :: [String.t()]
  def search(%__MODULE__{root: root}, prefix) when is_binary(prefix) do
    chars = String.graphemes(prefix)

    case descend(root, chars) do
      nil -> []
      node -> collect(node, prefix) |> Enum.sort()
    end
  end

  # Walk down the trie following `chars`, returning the subtree or nil.
  defp descend(node, []), do: node

  defp descend(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> descend(child, rest)
      :error -> nil
    end
  end

  # Depth-first collection of all complete words beneath `node`.
  defp collect(%{end_of_word: eow, children: children}, acc) do
    current = if eow, do: [acc], else: []

    children
    |> Enum.reduce(current, fn {char, child}, words ->
      collect(child, acc <> char) ++ words
    end)
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  @doc """
  Removes `word` from the trie. Returns the updated trie.

  Only the end-of-word marker is cleared; shared prefix nodes that are still
  needed by other words are left intact. Orphaned branch nodes are pruned.

  Deleting a word that isn't present is a no-op.
  """
  @spec delete(t, String.t()) :: t
  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if word_exists?(root, chars) do
      %__MODULE__{root: do_delete(root, chars), size: size - 1}
    else
      trie
    end
  end

  defp do_delete(node, []) do
    %{node | end_of_word: false}
  end

  defp do_delete(node, [char | rest]) do
    child = Map.fetch!(node.children, char)
    updated_child = do_delete(child, rest)

    if not updated_child.end_of_word and map_size(updated_child.children) == 0 do
      # The child is now a dead-end leaf — prune it.
      %{node | children: Map.delete(node.children, char)}
    else
      %{node | children: Map.put(node.children, char, updated_child)}
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
  def words(%__MODULE__{root: root}) do
    collect(root, "") |> Enum.sort()
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule TrieTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Construction and basic membership
  # -------------------------------------------------------

  test "new trie is empty" do
    t = Trie.new()
    assert Trie.size(t) == 0
    assert Trie.words(t) == []
  end

  test "insert and member? for a single word" do
    t = Trie.new() |> Trie.insert("hello")
    assert Trie.member?(t, "hello") == true
    assert Trie.member?(t, "hell") == false
    assert Trie.member?(t, "helloo") == false
    assert Trie.member?(t, "") == false
  end

  test "insert multiple words" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.insert("care")
      |> Trie.insert("cat")

    assert Trie.member?(t, "car") == true
    assert Trie.member?(t, "card") == true
    assert Trie.member?(t, "care") == true
    assert Trie.member?(t, "cat") == true
    assert Trie.member?(t, "ca") == false
    assert Trie.member?(t, "cars") == false
  end

  test "size tracks inserted words" do
    t =
      Trie.new()
      |> Trie.insert("a")
      |> Trie.insert("ab")
      |> Trie.insert("abc")

    assert Trie.size(t) == 3
  end

  test "inserting the same word twice doesn't increase size" do
    t =
      Trie.new()
      |> Trie.insert("hello")
      |> Trie.insert("hello")

    assert Trie.size(t) == 1
  end

  # -------------------------------------------------------
  # Prefix search
  # -------------------------------------------------------

  test "search returns all words with the given prefix, sorted" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.insert("care")
      |> Trie.insert("careful")
      |> Trie.insert("cat")
      |> Trie.insert("dog")

    assert Trie.search(t, "car") == ["car", "card", "care", "careful"]
    assert Trie.search(t, "care") == ["care", "careful"]
    assert Trie.search(t, "cat") == ["cat"]
    assert Trie.search(t, "d") == ["dog"]
  end

  test "search with empty prefix returns all words sorted" do
    t =
      Trie.new()
      |> Trie.insert("banana")
      |> Trie.insert("apple")
      |> Trie.insert("cherry")

    assert Trie.search(t, "") == ["apple", "banana", "cherry"]
  end

  test "search with prefix that matches nothing returns empty list" do
    t = Trie.new() |> Trie.insert("hello")
    assert Trie.search(t, "xyz") == []
  end

  test "search on empty trie returns empty list" do
    assert Trie.search(Trie.new(), "a") == []
  end

  # -------------------------------------------------------
  # words/1
  # -------------------------------------------------------

  test "words returns all inserted words sorted" do
    t =
      Trie.new()
      |> Trie.insert("zebra")
      |> Trie.insert("apple")
      |> Trie.insert("mango")
      |> Trie.insert("apricot")

    assert Trie.words(t) == ["apple", "apricot", "mango", "zebra"]
  end

  # -------------------------------------------------------
  # Deletion
  # -------------------------------------------------------

  test "delete removes a word" do
    t =
      Trie.new()
      |> Trie.insert("hello")
      |> Trie.delete("hello")

    assert Trie.member?(t, "hello") == false
    assert Trie.size(t) == 0
  end

  test "delete of a prefix word doesn't affect longer words" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.delete("car")

    assert Trie.member?(t, "car") == false
    assert Trie.member?(t, "card") == true
    assert Trie.size(t) == 1
  end

  test "delete of a longer word doesn't affect its prefix" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.delete("card")

    assert Trie.member?(t, "car") == true
    assert Trie.member?(t, "card") == false
    assert Trie.size(t) == 1
  end

  test "deleting a non-existent word changes nothing" do
    t = Trie.new() |> Trie.insert("hello")
    t2 = Trie.delete(t, "world")

    assert Trie.member?(t2, "hello") == true
    assert Trie.size(t2) == 1
  end

  test "deleting from empty trie returns empty trie" do
    t = Trie.new() |> Trie.delete("anything")
    assert Trie.size(t) == 0
  end

  # -------------------------------------------------------
  # Immutability
  # -------------------------------------------------------

  test "insert returns a new trie, original is unchanged" do
    t1 = Trie.new()
    t2 = Trie.insert(t1, "hello")

    assert Trie.size(t1) == 0
    assert Trie.member?(t1, "hello") == false

    assert Trie.size(t2) == 1
    assert Trie.member?(t2, "hello") == true
  end

  test "delete returns a new trie, original is unchanged" do
    t1 = Trie.new() |> Trie.insert("hello")
    t2 = Trie.delete(t1, "hello")

    assert Trie.member?(t1, "hello") == true
    assert Trie.member?(t2, "hello") == false
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "single character words" do
    t =
      Trie.new()
      |> Trie.insert("a")
      |> Trie.insert("b")
      |> Trie.insert("c")

    assert Trie.size(t) == 3
    assert Trie.member?(t, "a") == true
    assert Trie.search(t, "a") == ["a"]
  end

  test "words that are prefixes of each other" do
    t =
      Trie.new()
      |> Trie.insert("a")
      |> Trie.insert("ab")
      |> Trie.insert("abc")
      |> Trie.insert("abcd")

    assert Trie.size(t) == 4
    assert Trie.search(t, "ab") == ["ab", "abc", "abcd"]

    t2 = Trie.delete(t, "ab")
    assert Trie.member?(t2, "ab") == false
    assert Trie.member?(t2, "abc") == true
    assert Trie.search(t2, "ab") == ["abc", "abcd"]
  end

  test "larger dataset — 100 words" do
    # TODO
  end

  test "deleting the same word twice leaves the count at zero" do
    t =
      Trie.new()
      |> Trie.insert("hello")
      |> Trie.delete("hello")
      |> Trie.delete("hello")

    assert Trie.size(t) == 0
    assert Trie.member?(t, "hello") == false
    assert Trie.words(t) == []
  end

  test "re-inserting a word after it was deleted restores it" do
    t =
      Trie.new()
      |> Trie.insert("car")
      |> Trie.insert("card")
      |> Trie.delete("card")
      |> Trie.insert("card")

    assert Trie.member?(t, "card") == true
    assert Trie.member?(t, "car") == true
    assert Trie.size(t) == 2
    assert Trie.search(t, "car") == ["car", "card"]
  end

  test "a duplicate insert appears only once in words and search" do
    t =
      Trie.new()
      |> Trie.insert("apple")
      |> Trie.insert("apple")
      |> Trie.insert("apply")

    assert Trie.words(t) == ["apple", "apply"]
    assert Trie.search(t, "appl") == ["apple", "apply"]
    assert Trie.size(t) == 2
  end

  test "search for a prefix that runs past a stored word returns no words" do
    t =
      Trie.new()
      |> Trie.insert("hello")
      |> Trie.insert("help")

    assert Trie.search(t, "helloworld") == []
    assert Trie.search(t, "hell") == ["hello"]
    assert Trie.search(t, "hel") == ["hello", "help"]
  end

  test "the empty string is a member only when inserted as a word" do
    t = Trie.new() |> Trie.insert("") |> Trie.insert("a")

    assert Trie.member?(t, "") == true
    assert Trie.size(t) == 2
    assert Trie.words(t) == ["", "a"]

    t2 = Trie.delete(t, "")
    assert Trie.member?(t2, "") == false
    assert Trie.member?(t2, "a") == true
    assert Trie.size(t2) == 1
  end
end
```
