# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule ObjectStoreTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = ObjectStore.start_link([])
    %{store: pid}
  end

  defp sha1(content) do
    :crypto.hash(:sha, content) |> Base.encode16(case: :lower)
  end

  defp order_ok?(entries) do
    index =
      entries
      |> Enum.with_index()
      |> Map.new(fn {e, i} -> {e.hash, i} end)

    Enum.all?(entries, fn e ->
      Enum.all?(e.parents, fn p -> Map.get(index, p) > Map.get(index, e.hash) end)
    end)
  end

  # ---------------- store / retrieve ----------------

  test "store returns the lowercase SHA-1 hash of the content", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "hello world")
    assert hash == sha1("hello world")
    assert byte_size(hash) == 40
    assert hash =~ ~r/^[0-9a-f]{40}$/
  end

  test "retrieve returns content that was stored", %{store: s} do
    content = "some binary data \x00\x01\x02"
    {:ok, hash} = ObjectStore.store(s, content)
    assert {:ok, ^content} = ObjectStore.retrieve(s, hash)
  end

  test "retrieve returns error for unknown hash", %{store: s} do
    assert {:error, :not_found} =
             ObjectStore.retrieve(s, "0000000000000000000000000000000000000000")
  end

  test "storing the same content twice returns the same hash", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "duplicate")
    {:ok, h2} = ObjectStore.store(s, "duplicate")
    assert h1 == h2
  end

  # ---------------- commit objects ----------------

  test "root commit (empty parents) is retrievable and has empty parents in log", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree-content")
    {:ok, c} = ObjectStore.commit(s, t, [], "root commit", "alice")

    assert c =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, c)

    {:ok, [entry]} = ObjectStore.log(s, c)
    assert entry.hash == c
    assert entry.tree == t
    assert entry.parents == []
    assert entry.message == "root commit"
    assert entry.author == "alice"
  end

  test "identical commit arguments produce the same hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "msg", "author")
    {:ok, c2} = ObjectStore.commit(s, t, [], "msg", "author")
    assert c1 == c2
  end

  test "different parents produce different commit hashes", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, base} = ObjectStore.commit(s, t, [], "base", "alice")
    {:ok, extra} = ObjectStore.commit(s, t, [], "extra", "alice")

    {:ok, one_parent} = ObjectStore.commit(s, t, [base], "x", "alice")
    {:ok, two_parents} = ObjectStore.commit(s, t, [base, extra], "x", "alice")
    assert one_parent != two_parents
  end

  # ---------------- log (DAG walk) ----------------

  test "log walks a linear chain newest-to-oldest", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")
    {:ok, c3} = ObjectStore.commit(s, t, [c2], "third", "carol")

    {:ok, log} = ObjectStore.log(s, c3)
    assert length(log) == 3
    assert hd(log).hash == c3
    assert order_ok?(log)
    assert MapSet.new(Enum.map(log, & &1.hash)) == MapSet.new([c1, c2, c3])
  end

  test "log of a merge commit includes both branches and orders ancestors after", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "branch a root", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [], "branch b root", "bob")
    {:ok, m} = ObjectStore.commit(s, t, [c1, c2], "merge", "carol")

    {:ok, log} = ObjectStore.log(s, m)
    assert length(log) == 3
    assert hd(log).hash == m
    assert hd(log).parents == [c1, c2]
    assert order_ok?(log)
    assert MapSet.new(Enum.map(log, & &1.hash)) == MapSet.new([m, c1, c2])
  end

  test "log returns error for unknown commit hash", %{store: s} do
    assert {:error, :not_found} = ObjectStore.log(s, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
  end

  # ---------------- merge_base ----------------

  test "merge_base of a diamond returns the shared root", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [root], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [root], "b", "bob")

    assert {:ok, ^root} = ObjectStore.merge_base(s, a, b)
  end

  test "merge_base where one commit is an ancestor of the other", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")

    assert {:ok, ^c1} = ObjectStore.merge_base(s, c2, c1)
  end

  test "merge_base returns not_found when a hash is missing", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")

    assert {:error, :not_found} =
             ObjectStore.merge_base(s, c1, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
  end

  test "merge_base of two independent roots has no common ancestor", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, r1} = ObjectStore.commit(s, t, [], "root one", "alice")
    {:ok, r2} = ObjectStore.commit(s, t, [], "root two", "bob")

    assert {:error, :no_merge_base} = ObjectStore.merge_base(s, r1, r2)
  end

  test "merge_base returns the nearest shared ancestor, not an older common one", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, mid} = ObjectStore.commit(s, t, [root], "mid", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [mid], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [mid], "b", "bob")

    # root is also a common ancestor, but it is a proper ancestor of mid.
    assert {:ok, ^mid} = ObjectStore.merge_base(s, a, b)
  end

  test "the stored commit object is a text representation carrying every field", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree-content")
    {:ok, c} = ObjectStore.commit(s, t, [], "an important message", "alice")
    {:ok, raw} = ObjectStore.retrieve(s, c)

    assert String.printable?(raw)
    assert raw =~ t
    assert raw =~ "an important message"
    assert raw =~ "alice"
  end

  test "log of a diamond lists each reachable commit exactly once", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [root], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [root], "b", "bob")
    {:ok, m} = ObjectStore.commit(s, t, [a, b], "merge", "carol")

    {:ok, log} = ObjectStore.log(s, m)
    hashes = Enum.map(log, & &1.hash)

    assert length(hashes) == 4
    assert Enum.uniq(hashes) == hashes
    assert MapSet.new(hashes) == MapSet.new([m, a, b, root])
    assert hd(log).hash == m
    assert order_ok?(log)
  end

  test "start_link registers the process under the given :name option" do
    name = :object_store_promise_named
    {:ok, pid} = ObjectStore.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.whereis(name) == pid

    {:ok, hash} = ObjectStore.store(name, "named registration")
    assert hash == sha1("named registration")
    assert {:ok, "named registration"} = ObjectStore.retrieve(name, hash)
  end

  test "reordering the parent list changes the commit hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, p1} = ObjectStore.commit(s, t, [], "p one", "alice")
    {:ok, p2} = ObjectStore.commit(s, t, [], "p two", "bob")

    {:ok, ab} = ObjectStore.commit(s, t, [p1, p2], "merge", "carol")
    {:ok, ba} = ObjectStore.commit(s, t, [p2, p1], "merge", "carol")
    {:ok, again} = ObjectStore.commit(s, t, [p1, p2], "merge", "carol")

    assert ab != ba
    assert ab == again

    {:ok, [entry | _]} = ObjectStore.log(s, ba)
    assert entry.parents == [p2, p1]
  end

  test "merge_base of a commit with itself returns that commit", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")

    assert {:ok, ^c2} = ObjectStore.merge_base(s, c2, c2)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
