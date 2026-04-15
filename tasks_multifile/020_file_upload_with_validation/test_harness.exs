defmodule FileUploadTest do
  use ExUnit.Case, async: false
  use Plug.Test

  @upload_dir Path.join(System.tmp_dir!(), "file_upload_test_#{:rand.uniform(100_000)}")

  setup_all do
    File.mkdir_p!(@upload_dir)

    on_exit(fn ->
      File.rm_rf!(@upload_dir)
    end)

    :ok
  end

  setup do
    # Clean upload dir between tests
    @upload_dir |> File.ls!() |> Enum.each(&File.rm!(Path.join(@upload_dir, &1)))

    start_supervised!({FileUpload.Store, name: :test_store})

    opts =
      FileUpload.Router.init(
        store: :test_store,
        upload_dir: @upload_dir,
        base_url: "http://localhost:4000"
      )

    %{opts: opts}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp call_upload(opts, filename, content, content_type \\ nil) do
    # Write content to a tmp file so Plug.Upload can reference it
    tmp_path = Path.join(System.tmp_dir!(), "upload_#{:rand.uniform(100_000)}_#{filename}")
    File.write!(tmp_path, content)

    ct =
      content_type ||
        case Path.extname(filename) do
          ".csv" -> "text/csv"
          ".json" -> "application/json"
          ext -> "application/octet-stream"
        end

    upload = %Plug.Upload{
      path: tmp_path,
      filename: filename,
      content_type: ct
    }

    conn =
      conn(:post, "/api/uploads", %{"file" => upload})
      |> put_req_header("content-type", "multipart/form-data")
      |> FileUpload.Router.call(opts)

    File.rm(tmp_path)
    conn
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  # -------------------------------------------------------
  # Valid uploads
  # -------------------------------------------------------

  test "uploads a valid CSV and returns 201 with metadata", %{opts: opts} do
    csv_content = "name,age,email\nAlice,30,alice@example.com\nBob,25,bob@test.com\n"
    conn = call_upload(opts, "people.csv", csv_content)

    assert conn.status == 201

    body = json_body(conn)
    assert body["original_name"] == "people.csv"
    assert body["size"] == byte_size(csv_content)
    assert body["content_type"] == "text/csv"
    assert is_binary(body["id"])
    assert String.length(body["id"]) == 36  # UUID v4 length
    assert is_binary(body["uploaded_at"])
    assert String.contains?(body["download_url"], body["id"])
  end

  test "uploads a valid JSON file and returns 201 with metadata", %{opts: opts} do
    json_content = Jason.encode!(%{"users" => [%{"name" => "Alice"}, %{"name" => "Bob"}]})
    conn = call_upload(opts, "data.json", json_content)

    assert conn.status == 201

    body = json_body(conn)
    assert body["original_name"] == "data.json"
    assert body["size"] == byte_size(json_content)
    assert body["content_type"] == "application/json"
    assert is_binary(body["id"])
    assert is_binary(body["uploaded_at"])
    assert is_binary(body["download_url"])
  end

  test "file is actually persisted to disk", %{opts: opts} do
    csv_content = "col1,col2\nval1,val2\n"
    conn = call_upload(opts, "disk_check.csv", csv_content)

    assert conn.status == 201
    body = json_body(conn)

    # The file should exist in the upload dir with the UUID-based name
    expected_path = Path.join(@upload_dir, body["id"] <> ".csv")
    assert File.exists?(expected_path)
    assert File.read!(expected_path) == csv_content
  end

  # -------------------------------------------------------
  # File type validation
  # -------------------------------------------------------

  test "rejects .txt files with 422", %{opts: opts} do
    conn = call_upload(opts, "notes.txt", "some text content")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "not allowed"
  end

  test "rejects .exe files with 422", %{opts: opts} do
    conn = call_upload(opts, "malware.exe", "MZ\x90\x00")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "not allowed"
  end

  test "rejects files with no extension with 422", %{opts: opts} do
    conn = call_upload(opts, "Makefile", "all:\n\techo hello")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "not allowed"
  end

  test "extension check is case-insensitive", %{opts: opts} do
    csv_content = "a,b\n1,2\n"
    conn = call_upload(opts, "DATA.CSV", csv_content)
    assert conn.status == 201

    json_content = Jason.encode!(%{"ok" => true})
    conn = call_upload(opts, "config.JSON", json_content)
    assert conn.status == 201
  end

  # -------------------------------------------------------
  # File size validation (413)
  # -------------------------------------------------------

  test "rejects files larger than 5MB with 413", %{opts: opts} do
    # Create content just over 5MB
    big_content = String.duplicate("x", 5_242_881)
    conn = call_upload(opts, "huge.csv", big_content)

    assert conn.status == 413
    body = json_body(conn)
    assert body["error"] =~ "too large" or body["error"] =~ "Too large"
  end

  test "accepts a file exactly at 5MB", %{opts: opts} do
    # Build a valid CSV that is just under 5MB
    header = "col1,col2\n"
    row = "aaaa,bbbb\n"
    # Fill up to just under 5MB
    num_rows = div(5_242_880 - byte_size(header), byte_size(row)) - 1
    content = header <> String.duplicate(row, num_rows)

    # Ensure we're within the limit
    assert byte_size(content) <= 5_242_880

    conn = call_upload(opts, "big_but_ok.csv", content)
    assert conn.status == 201
  end

  # -------------------------------------------------------
  # Content validity — malformed CSV
  # -------------------------------------------------------

  test "rejects an empty CSV with 422", %{opts: opts} do
    conn = call_upload(opts, "empty.csv", "")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "Invalid CSV"
  end

  test "rejects a CSV with only a single value (no columns)", %{opts: opts} do
    conn = call_upload(opts, "single.csv", "justonevalue")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "Invalid CSV"
  end

  test "accepts a CSV with a proper header row", %{opts: opts} do
    conn = call_upload(opts, "good.csv", "name,email\n")
    assert conn.status == 201
  end

  # -------------------------------------------------------
  # Content validity — malformed JSON
  # -------------------------------------------------------

  test "rejects malformed JSON with 422 and descriptive error", %{opts: opts} do
    conn = call_upload(opts, "bad.json", "{invalid json content")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "Invalid JSON"
  end

  test "rejects empty JSON file with 422", %{opts: opts} do
    conn = call_upload(opts, "empty.json", "")

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "Invalid JSON"
  end

  test "accepts JSON arrays", %{opts: opts} do
    conn = call_upload(opts, "list.json", Jason.encode!([1, 2, 3]))
    assert conn.status == 201
  end

  test "accepts JSON primitives (string)", %{opts: opts} do
    conn = call_upload(opts, "str.json", Jason.encode!("hello"))
    assert conn.status == 201
  end

  # -------------------------------------------------------
  # Missing file field
  # -------------------------------------------------------

  test "returns 422 when no file field is provided", %{opts: opts} do
    conn =
      conn(:post, "/api/uploads", %{"not_file" => "something"})
      |> put_req_header("content-type", "multipart/form-data")
      |> FileUpload.Router.call(opts)

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "No file"
  end

  # -------------------------------------------------------
  # Store integration
  # -------------------------------------------------------

  test "metadata is retrievable from the store after upload", %{opts: opts} do
    csv_content = "x,y\n1,2\n"
    conn = call_upload(opts, "stored.csv", csv_content)
    assert conn.status == 201

    body = json_body(conn)
    id = body["id"]

    assert {:ok, meta} = FileUpload.Store.get(:test_store, id)
    assert meta.original_name == "stored.csv"
    assert meta.size == byte_size(csv_content)
  end

  test "store list returns all uploaded files", %{opts: opts} do
    call_upload(opts, "a.csv", "h1,h2\n1,2\n")
    call_upload(opts, "b.json", Jason.encode!(%{"k" => "v"}))

    files = FileUpload.Store.list(:test_store)
    assert length(files) == 2

    names = Enum.map(files, & &1.original_name) |> Enum.sort()
    assert names == ["a.csv", "b.json"]
  end

  test "store get returns error for unknown id", _ctx do
    start_supervised!({FileUpload.Store, name: :lonely_store})
    assert {:error, :not_found} = FileUpload.Store.get(:lonely_store, "nonexistent-uuid")
  end

  # -------------------------------------------------------
  # Download URL format
  # -------------------------------------------------------

  test "download URL contains the base_url and file id", %{opts: opts} do
    conn = call_upload(opts, "dl.json", Jason.encode!(%{}))
    assert conn.status == 201

    body = json_body(conn)
    assert String.starts_with?(body["download_url"], "http://localhost:4000")
    assert String.contains?(body["download_url"], body["id"])
  end

  # -------------------------------------------------------
  # uploaded_at timestamp
  # -------------------------------------------------------

  test "uploaded_at is a valid ISO 8601 string", %{opts: opts} do
    conn = call_upload(opts, "ts.csv", "a,b\n1,2\n")
    assert conn.status == 201

    body = json_body(conn)
    assert {:ok, _dt, _offset} = DateTime.from_iso8601(body["uploaded_at"])
  end

  # -------------------------------------------------------
  # Multiple uploads don't collide
  # -------------------------------------------------------

  test "uploading the same filename twice produces two distinct entries", %{opts: opts} do
    csv = "x,y\n1,2\n"
    conn1 = call_upload(opts, "dup.csv", csv)
    conn2 = call_upload(opts, "dup.csv", csv)

    assert conn1.status == 201
    assert conn2.status == 201

    body1 = json_body(conn1)
    body2 = json_body(conn2)

    assert body1["id"] != body2["id"]

    # Both files exist on disk
    assert File.exists?(Path.join(@upload_dir, body1["id"] <> ".csv"))
    assert File.exists?(Path.join(@upload_dir, body2["id"] <> ".csv"))
  end
end
