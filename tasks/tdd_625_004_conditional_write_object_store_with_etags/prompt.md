# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule ConditionalObjectStorageTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = ConditionalObjectStorage.start_link([])
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{os: pid}
  end

  defp etag_of(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  # -------------------------------------------------------
  # Buckets
  # -------------------------------------------------------

  test "create, list, invalid and duplicate buckets", %{os: os} do
    assert :ok = ConditionalObjectStorage.create_bucket(os, "beta")
    assert :ok = ConditionalObjectStorage.create_bucket(os, "alpha")
    assert {:ok, ["alpha", "beta"]} = ConditionalObjectStorage.list_buckets(os)
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "UP")
    assert {:error, :already_exists} = ConditionalObjectStorage.create_bucket(os, "alpha")
  end

  # -------------------------------------------------------
  # ETag semantics
  # -------------------------------------------------------

  test "put returns the sha256 hex etag of the data", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    assert {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "hello world")
    assert etag == etag_of("hello world")
  end

  test "get returns data, etag, size and last_modified", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    ConditionalObjectStorage.put_object(os, "b", "k", "payload")

    assert {:ok, obj} = ConditionalObjectStorage.get_object(os, "b", "k")
    assert obj.data == "payload"
    assert obj.etag == etag_of("payload")
    assert obj.size == byte_size("payload")
    assert %DateTime{} = obj.last_modified
  end

  test "identical data yields identical etag; different data differs", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, e1} = ConditionalObjectStorage.put_object(os, "b", "k", "same")
    {:ok, e2} = ConditionalObjectStorage.put_object(os, "b", "k", "same")
    {:ok, e3} = ConditionalObjectStorage.put_object(os, "b", "k", "different")
    assert e1 == e2
    assert e1 != e3
  end

  # -------------------------------------------------------
  # if_none_match: "*" (create-only)
  # -------------------------------------------------------

  test "if_none_match * creates only when absent", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:ok, _} =
             ConditionalObjectStorage.put_object(os, "b", "k", "first", if_none_match: "*")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "second", if_none_match: "*")

    # unchanged
    assert {:ok, %{data: "first"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # if_match: compare-and-swap
  # -------------------------------------------------------

  test "if_match succeeds on a matching etag and returns the new etag", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, e1} = ConditionalObjectStorage.put_object(os, "b", "k", "v1")

    assert {:ok, e2} = ConditionalObjectStorage.put_object(os, "b", "k", "v2", if_match: e1)
    assert e2 == etag_of("v2")
    assert {:ok, %{data: "v2"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  test "if_match fails on a stale etag and leaves the object unchanged", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, _e1} = ConditionalObjectStorage.put_object(os, "b", "k", "v1")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "v2", if_match: "stale-etag")

    assert {:ok, %{data: "v1"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  test "if_match on a missing key fails the precondition", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "v", if_match: "anything")

    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  test "put to a missing bucket returns bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.put_object(os, "nope", "k", "v")
  end

  # -------------------------------------------------------
  # Conditional get (cache revalidation)
  # -------------------------------------------------------

  test "get with if_none_match matching returns not_modified", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "body")

    assert {:error, :not_modified} =
             ConditionalObjectStorage.get_object(os, "b", "k", if_none_match: etag)

    assert {:ok, %{data: "body"}} =
             ConditionalObjectStorage.get_object(os, "b", "k", if_none_match: "other")
  end

  test "get errors for missing bucket and missing key", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.get_object(os, "nope", "k")
    ConditionalObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "missing")
  end

  # -------------------------------------------------------
  # Conditional / idempotent delete
  # -------------------------------------------------------

  test "delete is idempotent and reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.delete_object(os, "nope", "k")
    ConditionalObjectStorage.create_bucket(os, "b")
    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "never")
  end

  test "delete with no precondition removes the existing object", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, _} = ConditionalObjectStorage.put_object(os, "b", "gone", "v")
    {:ok, _} = ConditionalObjectStorage.put_object(os, "b", "kept", "w")

    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "gone")
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "gone")

    assert {:ok, remaining} = ConditionalObjectStorage.list_objects(os, "b")
    assert Enum.map(remaining, & &1.key) == ["kept"]

    # deleting the now-absent key again is still a success
    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "gone")
    assert {:ok, %{data: "w"}} = ConditionalObjectStorage.get_object(os, "b", "kept")
  end

  test "delete with if_match succeeds only on a matching etag", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "k", if_match: "wrong")

    # object still there
    assert {:ok, %{data: "v"}} = ConditionalObjectStorage.get_object(os, "b", "k")

    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "k", if_match: etag)
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  test "delete with if_match on a missing key fails the precondition", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "missing", if_match: "x")
  end

  test "a deleted key can be recreated with if_none_match *", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, _} = ConditionalObjectStorage.put_object(os, "b", "k", "old")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "new", if_none_match: "*")

    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "k")

    assert {:ok, etag} =
             ConditionalObjectStorage.put_object(os, "b", "k", "new", if_none_match: "*")

    assert etag == etag_of("new")
    assert {:ok, %{data: "new"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # Listing
  # -------------------------------------------------------

  test "list_objects returns sorted entries with etag and size", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    ConditionalObjectStorage.put_object(os, "b", "c", "333")
    ConditionalObjectStorage.put_object(os, "b", "a", "1")
    ConditionalObjectStorage.put_object(os, "b", "b", "22")

    assert {:ok, objs} = ConditionalObjectStorage.list_objects(os, "b")
    assert Enum.map(objs, & &1.key) == ["a", "b", "c"]
    a = Enum.find(objs, &(&1.key == "a"))
    assert a.size == 1
    assert a.etag == etag_of("1")
    assert %DateTime{} = a.last_modified
  end

  test "list_objects on a missing bucket errors", %{os: os} do
    assert {:error, :bucket_not_found} = ConditionalObjectStorage.list_objects(os, "nope")
  end

  test "put with a precondition on a missing bucket reports bucket_not_found not precondition", %{
    os: os
  } do
    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.put_object(os, "nope", "k", "v", if_none_match: "*")

    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.put_object(os, "nope", "k", "v", if_match: "anything")
  end

  test "delete with if_match on a missing bucket reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.delete_object(os, "nope", "k", if_match: "some-etag")
  end

  test "start_link registers the process under the given name option" do
    name = :cos_named_registration_test
    {:ok, pid} = ConditionalObjectStorage.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.whereis(name) == pid
    assert :ok = ConditionalObjectStorage.create_bucket(name, "b")
    assert {:ok, ["b"]} = ConditionalObjectStorage.list_buckets(name)
  end

  test "an empty bucket name is rejected as invalid_name", %{os: os} do
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "")
    assert {:ok, []} = ConditionalObjectStorage.list_buckets(os)
  end

  test "bucket names with hyphens, dots and digits are accepted", %{os: os} do
    assert :ok = ConditionalObjectStorage.create_bucket(os, "my-bucket.v2")
    assert :ok = ConditionalObjectStorage.create_bucket(os, "a.b-c9")
    assert {:ok, ["a.b-c9", "my-bucket.v2"]} = ConditionalObjectStorage.list_buckets(os)
    assert {:error, :invalid_name} = ConditionalObjectStorage.create_bucket(os, "has_underscore")
  end

  test "delete with a stale etag from a previous version leaves the object in place", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, old_etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v1")
    {:ok, new_etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v2")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "k", if_match: old_etag)

    assert {:ok, %{data: "v2"}} = ConditionalObjectStorage.get_object(os, "b", "k")
    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "k", if_match: new_etag)
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
