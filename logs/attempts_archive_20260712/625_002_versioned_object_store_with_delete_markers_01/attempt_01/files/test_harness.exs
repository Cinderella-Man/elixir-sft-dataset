defmodule VersionedObjectStorageTest do
  use ExUnit.Case, async: false

  # Build a per-run unique root so concurrent OS processes sharing a CWD do not
  # collide. System.pid/0 separates BEAM instances; the random suffix guards
  # against OS pid reuse. Cleanup uses the non-raising rm_rf/1.
  setup do
    unique =
      "#{System.pid()}-#{System.unique_integer([:positive])}-" <>
        Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    tmp_dir = Path.expand(Path.join(["tmp", "versioned_object_storage_test", unique]))
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    {:ok, pid} = VersionedObjectStorage.start_link(root_dir: tmp_dir)
    %{os: pid, tmp_dir: tmp_dir}
  end

  # -------------------------------------------------------
  # Buckets
  # -------------------------------------------------------

  test "create and list buckets sorted", %{os: os} do
    assert :ok = VersionedObjectStorage.create_bucket(os, "beta")
    assert :ok = VersionedObjectStorage.create_bucket(os, "alpha")
    assert {:ok, ["alpha", "beta"]} = VersionedObjectStorage.list_buckets(os)
  end

  test "invalid and duplicate bucket names", %{os: os} do
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "UPPER")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "has space")
    assert :ok = VersionedObjectStorage.create_bucket(os, "my-bucket.v2")
    assert {:error, :already_exists} = VersionedObjectStorage.create_bucket(os, "my-bucket.v2")
  end

  # -------------------------------------------------------
  # Put / get / versions
  # -------------------------------------------------------

  test "put returns a unique version id and get returns the latest version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")

    assert {:ok, vid} = VersionedObjectStorage.put_object(os, "b", "k", "one", %{"n" => "1"})
    assert is_binary(vid)

    assert {:ok, obj} = VersionedObjectStorage.get_object(os, "b", "k")
    assert obj.data == "one"
    assert obj.metadata == %{"n" => "1"}
    assert obj.size == byte_size("one")
    assert obj.version_id == vid
    assert %DateTime{} = obj.last_modified
  end

  test "each put creates a new retained version; get returns the newest", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert vid1 != vid2

    assert {:ok, %{data: "two", version_id: ^vid2}} =
             VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 2

    # newest first
    assert [%{version_id: ^vid2, is_delete_marker: false} | _] = versions
  end

  test "get_object_version fetches a specific historical version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, v} = VersionedObjectStorage.get_object_version(os, "b", "k", vid1)
    assert v.data == "one"
    assert v.version_id == vid1
    assert v.is_delete_marker == false
  end

  test "get_object_version on unknown version returns not_found", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    VersionedObjectStorage.put_object(os, "b", "k", "one")
    assert {:error, :not_found} = VersionedObjectStorage.get_object_version(os, "b", "k", "bogus")
  end

  # -------------------------------------------------------
  # Delete markers
  # -------------------------------------------------------

  test "delete_object writes a delete marker and hides the object", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")

    assert {:ok, marker} = VersionedObjectStorage.delete_object(os, "b", "k")
    assert is_binary(marker)

    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 2
    assert [%{version_id: ^marker, is_delete_marker: true, size: 0} | _] = versions

    assert {:ok, %{is_delete_marker: true, data: ""}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", marker)
  end

  test "delete_version permanently removes one version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", vid1)
    assert {:ok, [one]} = VersionedObjectStorage.list_versions(os, "b", "k")
    refute one.version_id == vid1
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
  end

  test "delete_version is idempotent", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert :ok = VersionedObjectStorage.delete_version(os, "b", "never", "nope")
  end

  test "deleting the delete marker restores the previous version", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "two")
    {:ok, marker} = VersionedObjectStorage.delete_object(os, "b", "k")

    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")
    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", marker)
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
  end

  # -------------------------------------------------------
  # list_objects reflects current state
  # -------------------------------------------------------

  test "list_objects shows only live keys, sorted", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    VersionedObjectStorage.put_object(os, "b", "a", "1")
    VersionedObjectStorage.put_object(os, "b", "b", "22")
    VersionedObjectStorage.put_object(os, "b", "c", "333")
    VersionedObjectStorage.delete_object(os, "b", "b")

    assert {:ok, objs} = VersionedObjectStorage.list_objects(os, "b")
    assert Enum.map(objs, & &1.key) == ["a", "c"]

    assert Enum.all?(objs, fn o ->
             is_integer(o.size) and match?(%DateTime{}, o.last_modified)
           end)
  end

  test "list_objects on empty bucket returns empty list", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "empty")
    assert {:ok, []} = VersionedObjectStorage.list_objects(os, "empty")
  end

  # -------------------------------------------------------
  # Errors
  # -------------------------------------------------------

  test "operations on a missing bucket report bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} = VersionedObjectStorage.put_object(os, "nope", "k", "v")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.get_object(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.delete_object(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.list_versions(os, "nope", "k")
    assert {:error, :bucket_not_found} = VersionedObjectStorage.list_objects(os, "nope")
  end

  test "get on a key with no versions returns not_found", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "missing")
  end

  # -------------------------------------------------------
  # Persistence
  # -------------------------------------------------------

  test "versions and restore survive a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "persist")
    {:ok, _} = VersionedObjectStorage.put_object(os, "persist", "k", "one", %{"x" => "y"})
    {:ok, _} = VersionedObjectStorage.put_object(os, "persist", "k", "two")
    {:ok, marker} = VersionedObjectStorage.delete_object(os, "persist", "k")

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, ["persist"]} = VersionedObjectStorage.list_buckets(pid2)
    assert {:error, :not_found} = VersionedObjectStorage.get_object(pid2, "persist", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(pid2, "persist", "k")
    assert length(versions) == 3
    assert [%{is_delete_marker: true} | _] = versions

    assert :ok = VersionedObjectStorage.delete_version(pid2, "persist", "k", marker)
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(pid2, "persist", "k")
  end
end
