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

  test "list_buckets is empty for a fresh store", %{os: os} do
    assert {:ok, []} = VersionedObjectStorage.list_buckets(os)
  end

  test "underscore and slash bucket names are rejected", %{os: os} do
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "bad_name")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "bad/name")
    assert {:error, :invalid_name} = VersionedObjectStorage.create_bucket(os, "MiXeD")
  end

  test "buckets are isolated from one another", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "one")
    VersionedObjectStorage.create_bucket(os, "two")
    VersionedObjectStorage.put_object(os, "one", "k", "in-one")

    assert {:ok, %{data: "in-one"}} = VersionedObjectStorage.get_object(os, "one", "k")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "two", "k")
    assert {:ok, []} = VersionedObjectStorage.list_objects(os, "two")
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

  test "put_object defaults metadata to an empty map", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _vid} = VersionedObjectStorage.put_object(os, "b", "k", "payload")

    assert {:ok, obj} = VersionedObjectStorage.get_object(os, "b", "k")
    assert obj.metadata == %{}
    assert obj.data == "payload"
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

  test "list_versions is ordered strictly newest first", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, v2} = VersionedObjectStorage.put_object(os, "b", "k", "two")
    {:ok, v3} = VersionedObjectStorage.put_object(os, "b", "k", "three")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert Enum.map(versions, & &1.version_id) == [v3, v2, v1]
  end

  test "list_versions on a key with no versions returns empty list", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    assert {:ok, []} = VersionedObjectStorage.list_versions(os, "b", "ghost")
  end

  test "each version records its own size", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, small} = VersionedObjectStorage.put_object(os, "b", "k", "hi")
    {:ok, big} = VersionedObjectStorage.put_object(os, "b", "k", "hello world")

    assert {:ok, sv} = VersionedObjectStorage.get_object_version(os, "b", "k", small)
    assert {:ok, bv} = VersionedObjectStorage.get_object_version(os, "b", "k", big)
    assert sv.size == byte_size("hi")
    assert bv.size == byte_size("hello world")
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

  test "get_object_version preserves per-version metadata", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "one", %{"tag" => "a"})
    {:ok, v2} = VersionedObjectStorage.put_object(os, "b", "k", "two", %{"tag" => "b"})

    assert {:ok, %{metadata: %{"tag" => "a"}}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", v1)

    assert {:ok, %{metadata: %{"tag" => "b"}}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", v2)
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

  test "delete marker still hides the object after re-put then re-delete", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _} = VersionedObjectStorage.delete_object(os, "b", "k")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(os, "b", "k")
    {:ok, _} = VersionedObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 4
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

  test "delete_version of an old version leaves it unreadable afterward", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, _vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", vid1)

    assert {:error, :not_found} =
             VersionedObjectStorage.get_object_version(os, "b", "k", vid1)
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

  test "list_objects reports the latest version id per key", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, latest} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert {:ok, [%{key: "k", version_id: ^latest, size: 3}]} =
             VersionedObjectStorage.list_objects(os, "b")
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

  test "version operations on a missing bucket report bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} =
             VersionedObjectStorage.get_object_version(os, "nope", "k", "vid")

    assert {:error, :bucket_not_found} =
             VersionedObjectStorage.delete_version(os, "nope", "k", "vid")
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

  test "an empty bucket survives a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "kept")

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, ["kept"]} = VersionedObjectStorage.list_buckets(pid2)
    assert {:ok, []} = VersionedObjectStorage.list_objects(pid2, "kept")
  end

  test "metadata and version ids survive a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "meta")
    {:ok, vid} = VersionedObjectStorage.put_object(os, "meta", "k", "body", %{"a" => "b"})

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, obj} = VersionedObjectStorage.get_object(pid2, "meta", "k")
    assert obj.version_id == vid
    assert obj.metadata == %{"a" => "b"}
    assert obj.data == "body"
  end

  test "start_link registers the process under the :name option", %{tmp_dir: tmp_dir} do
    name = :"vos_named_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      VersionedObjectStorage.start_link(root_dir: Path.join(tmp_dir, "named"), name: name)

    assert :ok = VersionedObjectStorage.create_bucket(name, "b")
    assert {:ok, _vid} = VersionedObjectStorage.put_object(name, "b", "k", "via-name")
    assert {:ok, ["b"]} = VersionedObjectStorage.list_buckets(name)
    assert {:ok, %{data: "via-name"}} = VersionedObjectStorage.get_object(name, "b", "k")
  end

  test "a permanently deleted version stays gone after a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "perm")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "perm", "k", "one")
    {:ok, v2} = VersionedObjectStorage.put_object(os, "perm", "k", "two")
    assert :ok = VersionedObjectStorage.delete_version(os, "perm", "k", v1)

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:error, :not_found} = VersionedObjectStorage.get_object_version(pid2, "perm", "k", v1)
    assert {:ok, [%{version_id: ^v2}]} = VersionedObjectStorage.list_versions(pid2, "perm", "k")
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(pid2, "perm", "k")
  end

  test "identical repeated puts still create distinct retained versions", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "same", %{"m" => "1"})
    {:ok, v2} = VersionedObjectStorage.put_object(os, "b", "k", "same", %{"m" => "1"})

    assert v1 != v2
    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert Enum.map(versions, & &1.version_id) == [v2, v1]

    assert {:ok, %{data: "same", metadata: %{"m" => "1"}}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", v1)
  end

  test "delete_object on a key with no versions returns a marker id", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")

    assert {:ok, marker} = VersionedObjectStorage.delete_object(os, "b", "ghost")
    assert is_binary(marker)

    assert {:ok, [%{version_id: ^marker, is_delete_marker: true, size: 0}]} =
             VersionedObjectStorage.list_versions(os, "b", "ghost")

    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "ghost")
    assert {:ok, []} = VersionedObjectStorage.list_objects(os, "b")
  end

  test "delete_version with an unknown id leaves existing versions intact", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, v1} = VersionedObjectStorage.put_object(os, "b", "k", "one")

    assert :ok = VersionedObjectStorage.delete_version(os, "b", "k", "no-such-version")
    assert {:ok, [%{version_id: ^v1}]} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert {:ok, %{data: "one"}} = VersionedObjectStorage.get_object(os, "b", "k")
  end

  test "a bucket recreated after a restart reports already_exists", %{os: os, tmp_dir: tmp_dir} do
    assert :ok = VersionedObjectStorage.create_bucket(os, "dup")

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:error, :already_exists} = VersionedObjectStorage.create_bucket(pid2, "dup")
    assert {:ok, ["dup"]} = VersionedObjectStorage.list_buckets(pid2)
  end
end
