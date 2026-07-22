defmodule TtlObjectStorageTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = TtlObjectStorage.start_link([])
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{os: pid}
  end

  # -------------------------------------------------------
  # Buckets
  # -------------------------------------------------------

  test "create, list, and delete buckets", %{os: os} do
    assert :ok = TtlObjectStorage.create_bucket(os, "beta")
    assert :ok = TtlObjectStorage.create_bucket(os, "alpha")
    assert {:ok, ["alpha", "beta"]} = TtlObjectStorage.list_buckets(os)
    assert :ok = TtlObjectStorage.delete_bucket(os, "alpha")
    assert {:ok, ["beta"]} = TtlObjectStorage.list_buckets(os)
  end

  test "invalid and duplicate bucket names", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "UPPER")
    assert :ok = TtlObjectStorage.create_bucket(os, "a-b.c")
    assert {:error, :already_exists} = TtlObjectStorage.create_bucket(os, "a-b.c")
  end

  test "delete_bucket returns not_found / not_empty", %{os: os} do
    assert {:error, :not_found} = TtlObjectStorage.delete_bucket(os, "ghost")

    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v")
    assert {:error, :not_empty} = TtlObjectStorage.delete_bucket(os, "b")
  end

  test "list_buckets is empty for a fresh server", %{os: os} do
    assert {:ok, []} = TtlObjectStorage.list_buckets(os)
  end

  test "non-string bucket names are rejected as invalid", %{os: os} do
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, :atom)
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, 123)
    assert {:error, :invalid_name} = TtlObjectStorage.create_bucket(os, "has space")
  end

  # -------------------------------------------------------
  # Basic put / get
  # -------------------------------------------------------

  test "put and get with default (infinite) ttl", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.put_object(os, "b", "k", "hello")

    assert {:ok, obj} = TtlObjectStorage.get_object(os, "b", "k")
    assert obj.data == "hello"
    assert obj.size == byte_size("hello")
    assert %DateTime{} = obj.last_modified
  end

  test "put to a missing bucket and get errors", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.put_object(os, "nope", "k", "v")
    assert {:error, :bucket_not_found} = TtlObjectStorage.get_object(os, "nope", "k")

    TtlObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "missing")
  end

  test "an object with a live ttl is still readable", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "put and get an empty binary reports a zero size", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.put_object(os, "b", "k", "")
    assert {:ok, %{data: "", size: 0}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # Expiration
  # -------------------------------------------------------

  test "an expired object reads as not_found", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "reading an expired object removes it lazily", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    # The lazy read should have deleted it, so a later purge finds nothing.
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
    assert {:ok, 0} = TtlObjectStorage.purge_expired(os)
  end

  test "list_objects excludes expired objects and is sorted", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "keep", "1", ttl_ms: 5_000)
    :ok = TtlObjectStorage.put_object(os, "b", "gone", "22", ttl_ms: 40)
    Process.sleep(120)

    assert {:ok, [obj]} = TtlObjectStorage.list_objects(os, "b")
    assert obj.key == "keep"
    assert obj.size == 1
    assert %DateTime{} = obj.last_modified
  end

  test "list_objects reports bucket_not_found and empty buckets", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.list_objects(os, "nope")
    TtlObjectStorage.create_bucket(os, "b")
    assert {:ok, []} = TtlObjectStorage.list_objects(os, "b")
  end

  test "purge_expired removes expired objects and reports the count", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "a", "x", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "b", "y", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "c", "z", ttl_ms: 5_000)
    Process.sleep(120)

    assert {:ok, 2} = TtlObjectStorage.purge_expired(os)
    assert {:ok, [%{key: "c"}]} = TtlObjectStorage.list_objects(os, "b")
  end

  test "purge_expired counts across multiple buckets", %{os: os} do
    TtlObjectStorage.create_bucket(os, "one")
    TtlObjectStorage.create_bucket(os, "two")
    :ok = TtlObjectStorage.put_object(os, "one", "k", "v", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "two", "k", "v", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "two", "live", "v", ttl_ms: 5_000)
    Process.sleep(120)

    assert {:ok, 2} = TtlObjectStorage.purge_expired(os)
    assert {:ok, []} = TtlObjectStorage.list_objects(os, "one")
    assert {:ok, [%{key: "live"}]} = TtlObjectStorage.list_objects(os, "two")
  end

  test "purge_expired returns zero when nothing has expired", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert {:ok, 0} = TtlObjectStorage.purge_expired(os)
    assert {:ok, [%{key: "k"}]} = TtlObjectStorage.list_objects(os, "b")
  end

  test "delete_bucket succeeds when only expired objects remain", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    assert :ok = TtlObjectStorage.delete_bucket(os, "b")
    assert {:ok, []} = TtlObjectStorage.list_buckets(os)
  end

  # -------------------------------------------------------
  # set_ttl
  # -------------------------------------------------------

  test "set_ttl extends the life of an object", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "set_ttl can shorten an object's life", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: :infinity)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", 40)
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "set_ttl to infinity keeps a previously expiring object alive", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 5_000)
    assert :ok = TtlObjectStorage.set_ttl(os, "b", "k", :infinity)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  test "set_ttl errors for missing bucket or key", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.set_ttl(os, "nope", "k", 100)
    TtlObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = TtlObjectStorage.set_ttl(os, "b", "missing", 100)
  end

  test "set_ttl on an already expired key errors as not_found", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v", ttl_ms: 40)
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.set_ttl(os, "b", "k", 5_000)
  end

  # -------------------------------------------------------
  # Overwrite resets ttl
  # -------------------------------------------------------

  test "overwriting an object resets its ttl", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "old", ttl_ms: 40)
    :ok = TtlObjectStorage.put_object(os, "b", "k", "new", ttl_ms: 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "new"}} = TtlObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # delete_object
  # -------------------------------------------------------

  test "delete_object is idempotent and reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = TtlObjectStorage.delete_object(os, "nope", "k")
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.delete_object(os, "b", "never")
    :ok = TtlObjectStorage.put_object(os, "b", "k", "v")
    assert :ok = TtlObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = TtlObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # Server default ttl / naming
  # -------------------------------------------------------

  test "server default_ttl_ms applies when no per-object ttl is given", %{os: _os} do
    {:ok, s2} = TtlObjectStorage.start_link(default_ttl_ms: 40)
    TtlObjectStorage.create_bucket(s2, "b")
    :ok = TtlObjectStorage.put_object(s2, "b", "k", "v")
    Process.sleep(120)
    assert {:error, :not_found} = TtlObjectStorage.get_object(s2, "b", "k")
    GenServer.stop(s2)
  end

  test "a per-object ttl overrides the server default_ttl_ms", %{os: _os} do
    {:ok, s2} = TtlObjectStorage.start_link(default_ttl_ms: 40)
    TtlObjectStorage.create_bucket(s2, "b")
    :ok = TtlObjectStorage.put_object(s2, "b", "k", "v", ttl_ms: 5_000)
    Process.sleep(120)
    assert {:ok, %{data: "v"}} = TtlObjectStorage.get_object(s2, "b", "k")
    GenServer.stop(s2)
  end

  test "the server can be registered and addressed by name", %{os: _os} do
    name = :"ttl_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = TtlObjectStorage.start_link(name: name)
    assert :ok = TtlObjectStorage.create_bucket(name, "b")
    :ok = TtlObjectStorage.put_object(name, "b", "k", "v")

    assert {:ok, %{data: "v"}} =
             TtlObjectStorage.get_object(name, "k" |> then(fn _ -> "b" end), "k")

    GenServer.stop(pid)
  end
end
