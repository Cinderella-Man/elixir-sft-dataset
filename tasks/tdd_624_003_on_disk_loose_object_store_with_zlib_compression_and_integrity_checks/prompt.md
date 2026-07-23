# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

```elixir
defmodule ObjectStoreTest do
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "objstore_#{System.pid()}_#{System.unique_integer([:positive])}"
      )

    {:ok, s} = ObjectStore.start_link(dir: dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{store: s, dir: dir}
  end

  defp sha1(content), do: :crypto.hash(:sha, content) |> Base.encode16(case: :lower)

  defp object_path(dir, hash) do
    Path.join([dir, String.slice(hash, 0, 2), String.slice(hash, 2, 38)])
  end

  # ---------------- basic store / retrieve ----------------

  test "store returns the lowercase SHA-1 hash", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "hello world")
    assert hash == sha1("hello world")
    assert hash =~ ~r/^[0-9a-f]{40}$/
  end

  test "retrieve returns the stored content", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "round trip")
    assert {:ok, "round trip"} = ObjectStore.retrieve(s, hash)
  end

  test "retrieve returns not_found for unknown hash", %{store: s} do
    assert {:error, :not_found} =
             ObjectStore.retrieve(s, "0000000000000000000000000000000000000000")
  end

  test "store is idempotent", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "dup")
    {:ok, h2} = ObjectStore.store(s, "dup")
    assert h1 == h2
  end

  test "empty and null-byte content round-trip", %{store: s} do
    {:ok, he} = ObjectStore.store(s, "")
    assert {:ok, ""} = ObjectStore.retrieve(s, he)

    bin = <<0, 1, 2, 255, 254, 253>>
    {:ok, hb} = ObjectStore.store(s, bin)
    assert {:ok, ^bin} = ObjectStore.retrieve(s, hb)
  end

  # ---------------- on-disk layout ----------------

  test "object is written at the documented fan-out path", %{store: s, dir: dir} do
    {:ok, hash} = ObjectStore.store(s, "layout check")
    assert File.exists?(object_path(dir, hash))
  end

  test "the file contents are zlib-compressed raw bytes", %{store: s, dir: dir} do
    content = "compress me please"
    {:ok, hash} = ObjectStore.store(s, content)
    raw = File.read!(object_path(dir, hash))
    assert :zlib.uncompress(raw) == content
  end

  # ---------------- integrity checks ----------------

  test "retrieve returns corrupt when the file cannot be decompressed", %{store: s, dir: dir} do
    {:ok, hash} = ObjectStore.store(s, "will be clobbered")
    File.write!(object_path(dir, hash), "this is not valid zlib data")
    assert {:error, :corrupt} = ObjectStore.retrieve(s, hash)
  end

  test "retrieve returns corrupt when the hash does not match", %{store: s, dir: dir} do
    hash_a = sha1("content A")
    path = object_path(dir, hash_a)
    File.mkdir_p!(Path.dirname(path))
    # Store the compressed bytes of a DIFFERENT content under hash_a's path.
    File.write!(path, :zlib.compress("content B"))
    assert {:error, :corrupt} = ObjectStore.retrieve(s, hash_a)
  end

  # ---------------- has_object? / list_objects ----------------

  test "has_object? reflects presence", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "present")
    assert ObjectStore.has_object?(s, hash) == true
    assert ObjectStore.has_object?(s, sha1("absent")) == false
  end

  test "list_objects returns all hashes sorted", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "one")
    {:ok, h2} = ObjectStore.store(s, "two")
    {:ok, h3} = ObjectStore.store(s, "three")
    assert ObjectStore.list_objects(s) == Enum.sort([h1, h2, h3])
  end

  # ---------------- persistence across processes ----------------

  test "objects persist to a new process using the same directory", %{store: s, dir: dir} do
    {:ok, h1} = ObjectStore.store(s, "persist one")
    {:ok, h2} = ObjectStore.store(s, "persist two")
    :ok = GenServer.stop(s)

    {:ok, s2} = ObjectStore.start_link(dir: dir)
    assert {:ok, "persist one"} = ObjectStore.retrieve(s2, h1)
    assert {:ok, "persist two"} = ObjectStore.retrieve(s2, h2)
    assert ObjectStore.list_objects(s2) == Enum.sort([h1, h2])
  end

  test "a second live process on the same directory sees objects written by the first", %{
    store: s,
    dir: dir
  } do
    {:ok, s2} = ObjectStore.start_link(dir: dir)

    {:ok, h1} = ObjectStore.store(s, "written by first")
    assert {:ok, "written by first"} = ObjectStore.retrieve(s2, h1)
    assert ObjectStore.has_object?(s2, h1) == true

    {:ok, h2} = ObjectStore.store(s2, "written by second")
    assert {:ok, "written by second"} = ObjectStore.retrieve(s, h2)
    assert ObjectStore.list_objects(s) == Enum.sort([h1, h2])

    :ok = GenServer.stop(s2)
  end

  test "storing the same content twice leaves the existing file untouched", %{store: s, dir: dir} do
    content = "no rewrite please"
    {:ok, hash} = ObjectStore.store(s, content)
    path = object_path(dir, hash)

    stamp = 946_684_800
    :ok = File.touch!(path, stamp)
    assert File.stat!(path, time: :posix).mtime == stamp

    {:ok, ^hash} = ObjectStore.store(s, content)

    assert File.stat!(path, time: :posix).mtime == stamp
    assert {:ok, ^content} = ObjectStore.retrieve(s, hash)
  end

  test "start_link creates the object directory when it does not exist", %{dir: dir} do
    nested = Path.join([dir, "not", "yet", "created"])
    refute File.exists?(nested)

    {:ok, s2} = ObjectStore.start_link(dir: nested)
    assert File.dir?(nested)

    {:ok, hash} = ObjectStore.store(s2, "fresh dir")
    assert File.exists?(object_path(nested, hash))
    assert ObjectStore.list_objects(s2) == [hash]

    :ok = GenServer.stop(s2)
  end

  test "start_link registers the process under the given :name", %{dir: dir} do
    name = :"objstore_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = ObjectStore.start_link(dir: Path.join(dir, "named"), name: name)
    assert Process.whereis(name) == pid

    {:ok, hash} = ObjectStore.store(name, "via name")
    assert {:ok, "via name"} = ObjectStore.retrieve(name, hash)
    assert ObjectStore.has_object?(name, hash) == true
    assert ObjectStore.list_objects(name) == [hash]

    :ok = GenServer.stop(name)
  end

  test "list_objects returns an empty list for a store with no objects", %{store: s} do
    assert ObjectStore.list_objects(s) == []

    {:ok, hash} = ObjectStore.store(s, "only one")
    assert ObjectStore.list_objects(s) == [hash]
  end

  test "start_link without the required :dir option raises" do
    assert_raise KeyError, fn -> ObjectStore.start_link([]) end
    assert_raise KeyError, fn -> ObjectStore.start_link(name: :objstore_no_dir) end
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
