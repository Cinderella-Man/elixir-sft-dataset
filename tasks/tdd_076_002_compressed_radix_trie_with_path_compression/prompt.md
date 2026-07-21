# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("care")
      |> RadixTrie.insert("cat")

    assert RadixTrie.member?(t, "car") == true
    assert RadixTrie.member?(t, "card") == true
    assert RadixTrie.member?(t, "care") == true
    assert RadixTrie.member?(t, "cat") == true
    assert RadixTrie.member?(t, "ca") == false
    assert RadixTrie.member?(t, "cars") == false
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

  test "inserting a word that is a proper prefix of an existing edge splits it" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("car")

    # the shorter word becomes a terminal mid-node; the longer word survives
    assert RadixTrie.member?(t, "car") == true
    assert RadixTrie.member?(t, "card") == true
    assert RadixTrie.member?(t, "ca") == false
    assert RadixTrie.size(t) == 2
    assert RadixTrie.search(t, "car") == ["car", "card"]
    # "card" edge splits into a terminal "car" node re-hanging the "d" suffix
    assert RadixTrie.node_count(t) == 3
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
