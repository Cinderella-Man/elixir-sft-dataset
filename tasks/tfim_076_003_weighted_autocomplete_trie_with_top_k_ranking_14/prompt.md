# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
    if node.weight == 0, do: :notfound, else: {%{node | weight: 0}, :ok}
  end

  defp do_delete(node, [char | rest]) do
    case Map.fetch(node.children, char) do
      :error ->
        :notfound

      {:ok, child} ->
        case do_delete(child, rest) do
          :notfound ->
            :notfound

          {new_child, :ok} ->
            if new_child.weight == 0 and map_size(new_child.children) == 0 do
              {%{node | children: Map.delete(node.children, char)}, :ok}
            else
              {%{node | children: Map.put(node.children, char, new_child)}, :ok}
            end
        end
    end
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

## Test harness — implement the `# TODO` test

```elixir
defmodule AutocompleteTrieTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction and basic membership
  # -------------------------------------------------------

  test "new trie is empty" do
    t = AutocompleteTrie.new()
    assert AutocompleteTrie.size(t) == 0
    assert AutocompleteTrie.words(t) == []
    assert AutocompleteTrie.suggest(t, "", 5) == []
  end

  test "insert with default weight and member?" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello")
    assert AutocompleteTrie.member?(t, "hello") == true
    assert AutocompleteTrie.member?(t, "hell") == false
    assert AutocompleteTrie.member?(t, "helloo") == false
    assert AutocompleteTrie.member?(t, "") == false
    assert AutocompleteTrie.weight(t, "hello") == 1
  end

  test "weight of an absent word is 0" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello")
    assert AutocompleteTrie.weight(t, "world") == 0
    assert AutocompleteTrie.weight(t, "hell") == 0
  end

  # -------------------------------------------------------
  # Weight accumulation
  # -------------------------------------------------------

  test "inserting the same word accumulates weight without growing size" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("apple", 3)
      |> AutocompleteTrie.insert("apple", 5)

    assert AutocompleteTrie.weight(t, "apple") == 8
    assert AutocompleteTrie.size(t) == 1
  end

  test "custom weights are respected" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("a", 10)
      |> AutocompleteTrie.insert("b", 2)

    assert AutocompleteTrie.weight(t, "a") == 10
    assert AutocompleteTrie.weight(t, "b") == 2
    assert AutocompleteTrie.size(t) == 2
  end

  # -------------------------------------------------------
  # Ranked suggestions
  # -------------------------------------------------------

  test "suggest ranks by descending weight then lexicographically" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("apple", 5)
      |> AutocompleteTrie.insert("app", 3)
      |> AutocompleteTrie.insert("apply", 5)
      |> AutocompleteTrie.insert("apricot", 2)
      |> AutocompleteTrie.insert("banana", 10)

    # among "ap*": apple(5), apply(5), app(3), apricot(2)
    assert AutocompleteTrie.suggest(t, "ap", 3) == ["apple", "apply", "app"]
    assert AutocompleteTrie.suggest(t, "ap", 10) == ["apple", "apply", "app", "apricot"]
  end

  test "suggest respects k and returns [] for k = 0" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("cat", 1)
      |> AutocompleteTrie.insert("car", 2)
      |> AutocompleteTrie.insert("card", 3)

    assert AutocompleteTrie.suggest(t, "ca", 0) == []
    assert AutocompleteTrie.suggest(t, "ca", 1) == ["card"]
    assert AutocompleteTrie.suggest(t, "ca", 2) == ["card", "car"]
  end

  test "suggest includes the prefix itself when inserted" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("go", 4)
      |> AutocompleteTrie.insert("gopher", 1)

    assert AutocompleteTrie.suggest(t, "go", 5) == ["go", "gopher"]
  end

  test "suggest with a prefix that matches nothing returns []" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello", 1)
    assert AutocompleteTrie.suggest(t, "xyz", 5) == []
  end

  test "suggest with empty prefix ranks the whole trie" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("low", 1)
      |> AutocompleteTrie.insert("mid", 5)
      |> AutocompleteTrie.insert("high", 9)

    assert AutocompleteTrie.suggest(t, "", 2) == ["high", "mid"]
  end

  # -------------------------------------------------------
  # words/1 and size/1
  # -------------------------------------------------------

  test "words returns all words sorted" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("zebra", 1)
      |> AutocompleteTrie.insert("apple", 1)
      |> AutocompleteTrie.insert("mango", 1)

    assert AutocompleteTrie.words(t) == ["apple", "mango", "zebra"]
    assert AutocompleteTrie.size(t) == 3
  end

  # -------------------------------------------------------
  # Deletion
  # -------------------------------------------------------

  test "delete removes a word entirely" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("hello", 7)
      |> AutocompleteTrie.delete("hello")

    assert AutocompleteTrie.member?(t, "hello") == false
    assert AutocompleteTrie.weight(t, "hello") == 0
    assert AutocompleteTrie.size(t) == 0
  end

  test "delete of a prefix word doesn't affect longer words" do
    # TODO
  end

  test "deleting a non-existent word changes nothing" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello", 1)
    t2 = AutocompleteTrie.delete(t, "world")

    assert AutocompleteTrie.member?(t2, "hello") == true
    assert AutocompleteTrie.size(t2) == 1
  end

  test "deleting from empty trie returns empty trie" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.delete("anything")
    assert AutocompleteTrie.size(t) == 0
  end

  # -------------------------------------------------------
  # Immutability
  # -------------------------------------------------------

  test "insert returns a new trie, original is unchanged" do
    t1 = AutocompleteTrie.new()
    t2 = AutocompleteTrie.insert(t1, "hello", 4)

    assert AutocompleteTrie.size(t1) == 0
    assert AutocompleteTrie.weight(t1, "hello") == 0
    assert AutocompleteTrie.weight(t2, "hello") == 4
  end

  test "delete returns a new trie, original is unchanged" do
    t1 = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello", 1)
    t2 = AutocompleteTrie.delete(t1, "hello")

    assert AutocompleteTrie.member?(t1, "hello") == true
    assert AutocompleteTrie.member?(t2, "hello") == false
  end

  # -------------------------------------------------------
  # Larger dataset
  # -------------------------------------------------------

  test "larger dataset — ranking across 50 words" do
    t =
      Enum.reduce(1..50, AutocompleteTrie.new(), fn i, acc ->
        AutocompleteTrie.insert(acc, "term#{String.pad_leading("#{i}", 2, "0")}", i)
      end)

    assert AutocompleteTrie.size(t) == 50
    # highest weights first: term50 (50) down to term41 (41)
    top = AutocompleteTrie.suggest(t, "term", 3)
    assert top == ["term50", "term49", "term48"]
    assert AutocompleteTrie.weight(t, "term25") == 25
  end

  test "re-inserting after delete starts weight fresh rather than resurrecting the old weight" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("apple", 9)
      |> AutocompleteTrie.delete("apple")
      |> AutocompleteTrie.insert("apple", 2)

    assert AutocompleteTrie.weight(t, "apple") == 2
    assert AutocompleteTrie.size(t) == 1
    assert AutocompleteTrie.suggest(t, "ap", 5) == ["apple"]
  end

  test "deleting a prefix that exists only as a path is a no-op" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("card", 3)
    t2 = AutocompleteTrie.delete(t, "car")

    assert AutocompleteTrie.size(t2) == 1
    assert AutocompleteTrie.member?(t2, "card") == true
    assert AutocompleteTrie.weight(t2, "card") == 3
    assert AutocompleteTrie.words(t2) == ["card"]
    assert AutocompleteTrie.suggest(t2, "ca", 5) == ["card"]
  end

  test "insert rejects non-positive and non-integer weights" do
    t = AutocompleteTrie.new()

    assert_raise FunctionClauseError, fn -> AutocompleteTrie.insert(t, "a", 0) end
    assert_raise FunctionClauseError, fn -> AutocompleteTrie.insert(t, "a", -5) end
    assert_raise FunctionClauseError, fn -> AutocompleteTrie.insert(t, "a", 1.5) end
  end

  test "suggest rejects a negative k" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("cat", 1)

    assert_raise FunctionClauseError, fn -> AutocompleteTrie.suggest(t, "ca", -1) end
    assert AutocompleteTrie.suggest(t, "ca", 0) == []
  end

  test "accumulated weight drives suggest ranking ahead of a heavier single insert" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("aa", 3)
      |> AutocompleteTrie.insert("ab", 5)
      |> AutocompleteTrie.insert("aa", 4)

    assert AutocompleteTrie.weight(t, "aa") == 7
    assert AutocompleteTrie.size(t) == 2
    assert AutocompleteTrie.suggest(t, "a", 2) == ["aa", "ab"]
  end

  # -------------------------------------------------------
  # The empty string as a stored word
  # -------------------------------------------------------

  test "an inserted empty string is a full-fledged word with accumulating weight" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("", 3)
      |> AutocompleteTrie.insert("", 4)

    assert AutocompleteTrie.member?(t, "") == true
    assert AutocompleteTrie.weight(t, "") == 7
    assert AutocompleteTrie.size(t) == 1
    assert AutocompleteTrie.words(t) == [""]
    assert AutocompleteTrie.suggest(t, "", 5) == [""]
  end

  test "stored empty string ranks with other words and matches only the empty prefix" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("", 5)
      |> AutocompleteTrie.insert("apple", 5)
      |> AutocompleteTrie.insert("ant", 9)

    assert AutocompleteTrie.size(t) == 3
    assert AutocompleteTrie.words(t) == ["", "ant", "apple"]
    # ant(9) leads; "" and "apple" tie at 5, so "" wins lexicographically
    assert AutocompleteTrie.suggest(t, "", 3) == ["ant", "", "apple"]
    assert AutocompleteTrie.suggest(t, "a", 5) == ["ant", "apple"]
  end

  test "deleting the empty string leaves other words intact and allows a fresh re-insert" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("", 8)
      |> AutocompleteTrie.insert("cat", 2)

    t2 = AutocompleteTrie.delete(t, "")

    assert AutocompleteTrie.member?(t2, "") == false
    assert AutocompleteTrie.weight(t2, "") == 0
    assert AutocompleteTrie.size(t2) == 1
    assert AutocompleteTrie.words(t2) == ["cat"]
    assert AutocompleteTrie.member?(t, "") == true

    t3 = AutocompleteTrie.insert(t2, "", 1)
    assert AutocompleteTrie.weight(t3, "") == 1
    assert AutocompleteTrie.size(t3) == 2
  end
end
```
