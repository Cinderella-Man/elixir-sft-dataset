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
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("car", 2)
      |> AutocompleteTrie.insert("card", 3)
      |> AutocompleteTrie.delete("car")

    assert AutocompleteTrie.member?(t, "car") == false
    assert AutocompleteTrie.member?(t, "card") == true
    assert AutocompleteTrie.weight(t, "card") == 3
    assert AutocompleteTrie.size(t) == 1
    assert AutocompleteTrie.suggest(t, "ca", 5) == ["card"]
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
end
