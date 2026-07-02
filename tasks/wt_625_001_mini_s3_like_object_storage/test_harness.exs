defmodule ObjectStorageTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, pid} = ObjectStorage.start_link(root_dir: tmp_dir)
    %{os: pid}
  end

  # -------------------------------------------------------
  # Bucket CRUD
  # -------------------------------------------------------

  test "create and list buckets", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "alpha")
    assert :ok = ObjectStorage.create_bucket(os, "beta")
    assert {:ok, ["alpha", "beta"]} = ObjectStorage.list_buckets(os)
  end

  test "creating a duplicate bucket returns error", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "photos")
    assert {:error, :already_exists} = ObjectStorage.create_bucket(os, "photos")
  end

  test "invalid bucket names are rejected", %{os: os} do
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "UPPER")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "has space")
    assert {:error, :invalid_name} = ObjectStorage.create_bucket(os, "under_score")
  end

  test "valid bucket names with hyphens and dots", %{os: os} do
    assert :ok = ObjectStorage.create_bucket(os, "my-bucket")
    assert :ok = ObjectStorage.create_bucket(os, "my.bucket.v2")
    assert :ok = ObjectStorage.create_bucket(os, "abc123")
  end

  test "delete an empty bucket", %{os: os} do
    ObjectStorage.create_bucket(os, "temp")
    assert :ok = ObjectStorage.delete_bucket(os, "temp")
    assert {:ok, []} = ObjectStorage.list_buckets(os)
  end

  test "delete a non-existent bucket returns error", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.delete_bucket(os, "ghost")
  end

  test "delete a non-empty bucket returns error", %{os: os} do
    ObjectStorage.create_bucket(os, "full")
    ObjectStorage.put_object(os, "full", "file.txt", "hello")
    assert {:error, :not_empty} = ObjectStorage.delete_bucket(os, "full")
  end

  # -------------------------------------------------------
  # Object CRUD
  # -------------------------------------------------------

  test "put and get an object", %{os: os} do
    ObjectStorage.create_bucket(os, "data")

    assert :ok =
             ObjectStorage.put_object(os, "data", "greeting.txt", "hello world", "text/plain", %{
               "author" => "test"
             })

    assert {:ok, obj} = ObjectStorage.get_object(os, "data", "greeting.txt")
    assert obj.data == "hello world"
    assert obj.content_type == "text/plain"
    assert obj.metadata == %{"author" => "test"}
    assert obj.size == byte_size("hello world")
    assert %DateTime{} = obj.last_modified
  end

  test "put overwrites an existing object silently", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "v1")
    ObjectStorage.put_object(os, "b", "k", "v2")

    assert {:ok, %{data: "v2"}} = ObjectStorage.get_object(os, "b", "k")
  end

  test "get from non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.get_object(os, "nope", "k")
  end

  test "get a non-existent key", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ObjectStorage.get_object(os, "b", "missing")
  end

  test "put to non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.put_object(os, "nope", "k", "v")
  end

  test "default content_type is application/octet-stream", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "data")

    assert {:ok, %{content_type: "application/octet-stream"}} =
             ObjectStorage.get_object(os, "b", "k")
  end

  test "delete an object", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "v")
    assert :ok = ObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = ObjectStorage.get_object(os, "b", "k")
  end

  test "delete is idempotent — deleting a missing key succeeds", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert :ok = ObjectStorage.delete_object(os, "b", "never-existed")
  end

  test "delete from non-existent bucket returns error", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.delete_object(os, "nope", "k")
  end

  # -------------------------------------------------------
  # Binary data
  # -------------------------------------------------------

  test "stores and retrieves raw binary data correctly", %{os: os} do
    ObjectStorage.create_bucket(os, "bin")
    blob = :crypto.strong_rand_bytes(4096)
    ObjectStorage.put_object(os, "bin", "random.bin", blob, "application/octet-stream")

    assert {:ok, %{data: ^blob, size: 4096}} = ObjectStorage.get_object(os, "bin", "random.bin")
  end

  # -------------------------------------------------------
  # Listing with prefix and max_keys
  # -------------------------------------------------------

  test "list_objects returns all keys sorted", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "c.txt", "")
    ObjectStorage.put_object(os, "b", "a.txt", "")
    ObjectStorage.put_object(os, "b", "b.txt", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b")
    keys = Enum.map(objects, & &1.key)
    assert keys == ["a.txt", "b.txt", "c.txt"]
  end

  test "list_objects with prefix filter", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "images/cat.png", "")
    ObjectStorage.put_object(os, "b", "images/dog.png", "")
    ObjectStorage.put_object(os, "b", "docs/readme.md", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b", prefix: "images/")
    keys = Enum.map(objects, & &1.key)
    assert keys == ["images/cat.png", "images/dog.png"]
  end

  test "list_objects with max_keys", %{os: os} do
    ObjectStorage.create_bucket(os, "b")

    for i <- 1..10,
        do: ObjectStorage.put_object(os, "b", "file-#{String.pad_leading("#{i}", 2, "0")}", "")

    assert {:ok, objects} = ObjectStorage.list_objects(os, "b", max_keys: 3)
    assert length(objects) == 3
  end

  test "list_objects includes size and last_modified", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "12345")

    assert {:ok, [obj]} = ObjectStorage.list_objects(os, "b")
    assert obj.key == "k"
    assert obj.size == 5
    assert %DateTime{} = obj.last_modified
  end

  test "list_objects on non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.list_objects(os, "nope")
  end

  test "list_objects on empty bucket returns empty list", %{os: os} do
    ObjectStorage.create_bucket(os, "empty")
    assert {:ok, []} = ObjectStorage.list_objects(os, "empty")
  end

  # -------------------------------------------------------
  # Copy
  # -------------------------------------------------------

  test "copy an object within the same bucket", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "src", "payload", "text/plain", %{"tag" => "1"})

    assert :ok = ObjectStorage.copy_object(os, "b", "src", "b", "dst")

    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "dst")
    assert obj.data == "payload"
    assert obj.content_type == "text/plain"
    assert obj.metadata == %{"tag" => "1"}

    # Source still exists
    assert {:ok, _} = ObjectStorage.get_object(os, "b", "src")
  end

  test "copy an object across buckets", %{os: os} do
    ObjectStorage.create_bucket(os, "src-bucket")
    ObjectStorage.create_bucket(os, "dst-bucket")
    ObjectStorage.put_object(os, "src-bucket", "file", "cross-bucket", "image/png")

    assert :ok = ObjectStorage.copy_object(os, "src-bucket", "file", "dst-bucket", "file-copy")

    assert {:ok, %{data: "cross-bucket", content_type: "image/png"}} =
             ObjectStorage.get_object(os, "dst-bucket", "file-copy")
  end

  test "copy to same bucket and same key is a no-op success", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "original")

    assert :ok = ObjectStorage.copy_object(os, "b", "k", "b", "k")
    assert {:ok, %{data: "original"}} = ObjectStorage.get_object(os, "b", "k")
  end

  test "copy fails when source bucket doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "dst")

    assert {:error, :src_bucket_not_found} =
             ObjectStorage.copy_object(os, "ghost", "k", "dst", "k")
  end

  test "copy fails when destination bucket doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "src")
    ObjectStorage.put_object(os, "src", "k", "v")

    assert {:error, :dst_bucket_not_found} =
             ObjectStorage.copy_object(os, "src", "k", "ghost", "k")
  end

  test "copy fails when source key doesn't exist", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert {:error, :not_found} = ObjectStorage.copy_object(os, "b", "missing", "b", "dst")
  end

  # -------------------------------------------------------
  # Multipart upload
  # -------------------------------------------------------

  test "basic multipart upload and reassembly", %{os: os} do
    ObjectStorage.create_bucket(os, "b")

    assert {:ok, upload_id} =
             ObjectStorage.start_multipart(os, "b", "big-file.bin", "application/octet-stream", %{
               "source" => "upload"
             })

    assert is_binary(upload_id)

    assert :ok = ObjectStorage.upload_part(os, upload_id, 1, "AAA")
    assert :ok = ObjectStorage.upload_part(os, upload_id, 2, "BBB")
    assert :ok = ObjectStorage.upload_part(os, upload_id, 3, "CCC")

    assert :ok = ObjectStorage.complete_multipart(os, upload_id)

    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "big-file.bin")
    assert obj.data == "AAABBBCCC"
    assert obj.content_type == "application/octet-stream"
    assert obj.metadata == %{"source" => "upload"}
    assert obj.size == 9
  end

  test "multipart parts can arrive out of order", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "shuffled", "text/plain")

    ObjectStorage.upload_part(os, uid, 3, "third")
    ObjectStorage.upload_part(os, uid, 1, "first")
    ObjectStorage.upload_part(os, uid, 2, "second")

    ObjectStorage.complete_multipart(os, uid)

    assert {:ok, %{data: "firstsecondthird"}} = ObjectStorage.get_object(os, "b", "shuffled")
  end

  test "uploading the same part number overwrites previous data", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "overwrite-part", "text/plain")

    ObjectStorage.upload_part(os, uid, 1, "old")
    ObjectStorage.upload_part(os, uid, 1, "new")
    ObjectStorage.upload_part(os, uid, 2, "end")

    ObjectStorage.complete_multipart(os, uid)

    assert {:ok, %{data: "newend"}} = ObjectStorage.get_object(os, "b", "overwrite-part")
  end

  test "complete_multipart with no parts returns error", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "empty-multipart", "text/plain")

    assert {:error, :no_parts} = ObjectStorage.complete_multipart(os, uid)
  end

  test "upload_id is invalidated after completion", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "done", "text/plain")
    ObjectStorage.upload_part(os, uid, 1, "x")
    ObjectStorage.complete_multipart(os, uid)

    assert {:error, :not_found} = ObjectStorage.upload_part(os, uid, 2, "y")
    assert {:error, :not_found} = ObjectStorage.complete_multipart(os, uid)
  end

  test "start_multipart on non-existent bucket", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.start_multipart(os, "nope", "k")
  end

  test "upload_part with unknown upload_id", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.upload_part(os, "bogus-id", 1, "data")
  end

  test "complete_multipart with unknown upload_id", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.complete_multipart(os, "bogus-id")
  end

  # -------------------------------------------------------
  # Abort multipart
  # -------------------------------------------------------

  test "abort cleans up and invalidates the upload", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid} = ObjectStorage.start_multipart(os, "b", "aborted", "text/plain")
    ObjectStorage.upload_part(os, uid, 1, "partial")

    assert :ok = ObjectStorage.abort_multipart(os, uid)

    # upload_id is now invalid
    assert {:error, :not_found} = ObjectStorage.upload_part(os, uid, 2, "more")
    assert {:error, :not_found} = ObjectStorage.complete_multipart(os, uid)

    # Object was never created
    assert {:error, :not_found} = ObjectStorage.get_object(os, "b", "aborted")
  end

  test "abort unknown upload_id returns error", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.abort_multipart(os, "bogus-id")
  end

  # -------------------------------------------------------
  # Persistence across restarts
  # -------------------------------------------------------

  test "objects survive a GenServer restart", %{os: os, tmp_dir: tmp_dir} do
    ObjectStorage.create_bucket(os, "persist")
    ObjectStorage.put_object(os, "persist", "key", "durable-data", "text/plain", %{"x" => "y"})

    # Stop the GenServer
    GenServer.stop(os)

    # Restart with the same root_dir
    {:ok, pid2} = ObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, ["persist"]} = ObjectStorage.list_buckets(pid2)
    assert {:ok, obj} = ObjectStorage.get_object(pid2, "persist", "key")
    assert obj.data == "durable-data"
    assert obj.content_type == "text/plain"
    assert obj.metadata == %{"x" => "y"}
  end

  # -------------------------------------------------------
  # Concurrent multipart uploads
  # -------------------------------------------------------

  test "multiple concurrent multipart uploads don't interfere", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    {:ok, uid1} = ObjectStorage.start_multipart(os, "b", "file-a", "text/plain")
    {:ok, uid2} = ObjectStorage.start_multipart(os, "b", "file-b", "text/plain")

    assert uid1 != uid2

    ObjectStorage.upload_part(os, uid1, 1, "A1")
    ObjectStorage.upload_part(os, uid2, 1, "B1")
    ObjectStorage.upload_part(os, uid1, 2, "A2")
    ObjectStorage.upload_part(os, uid2, 2, "B2")

    ObjectStorage.complete_multipart(os, uid1)
    ObjectStorage.complete_multipart(os, uid2)

    assert {:ok, %{data: "A1A2"}} = ObjectStorage.get_object(os, "b", "file-a")
    assert {:ok, %{data: "B1B2"}} = ObjectStorage.get_object(os, "b", "file-b")
  end
end
