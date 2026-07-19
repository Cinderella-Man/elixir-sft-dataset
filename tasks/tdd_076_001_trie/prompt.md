# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    words = for i <- 1..100, do: "word#{String.pad_leading("#{i}", 3, "0")}"

    t = Enum.reduce(words, Trie.new(), &Trie.insert(&2, &1))

    assert Trie.size(t) == 100
    assert Trie.member?(t, "word001") == true
    assert Trie.member?(t, "word100") == true
    assert Trie.member?(t, "word101") == false

    # Prefix search for "word0" should return word001..word099
    results = Trie.search(t, "word0")
    assert length(results) == 99

    # All words sorted
    all = Trie.words(t)
    assert all == Enum.sort(words)
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
