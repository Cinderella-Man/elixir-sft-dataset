defmodule FileUploadTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @upload_dir Path.join(
                System.tmp_dir!(),
                "file_upload_dedup_test_#{System.pid()}_#{System.unique_integer([:positive])}"
              )

  setup_all do
    File.mkdir_p!(@upload_dir)
    on_exit(fn -> File.rm_rf!(@upload_dir) end)
    :ok
  end

  setup do
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

  defp call_upload(opts, filename, content, content_type \\ nil) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "upl_#{System.pid()}_#{System.unique_integer([:positive])}_#{filename}"
      )

    File.write!(tmp_path, content)

    ct =
      content_type ||
        case Path.extname(filename) do
          ".csv" -> "text/csv"
          ".json" -> "application/json"
          _ -> "application/octet-stream"
        end

    upload = %Plug.Upload{path: tmp_path, filename: filename, content_type: ct}

    conn =
      conn(:post, "/api/uploads", %{"file" => upload})
      |> put_req_header("content-type", "multipart/form-data")
      |> FileUpload.Router.call(opts)

    File.rm(tmp_path)
    conn
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  test "new CSV upload returns 201 with sha256 id, deduplicated=false", %{opts: opts} do
    conn = call_upload(opts, "people.csv", "name,age\nAlice,30\n")
    assert conn.status == 201
    body = json_body(conn)
    assert String.length(body["id"]) == 64
    assert body["id"] =~ ~r/\A[0-9a-f]{64}\z/
    assert body["deduplicated"] == false
    assert body["upload_count"] == 1
    assert body["original_name"] == "people.csv"
    assert String.contains?(body["download_url"], body["id"])
  end

  test "identical content under a new name dedupes (200, same id)", %{opts: opts} do
    content = "x,y\n1,2\n"
    c1 = call_upload(opts, "first.csv", content)
    c2 = call_upload(opts, "second.csv", content)

    assert c1.status == 201
    assert c2.status == 200

    b1 = json_body(c1)
    b2 = json_body(c2)

    assert b1["id"] == b2["id"]
    assert b1["deduplicated"] == false
    assert b2["deduplicated"] == true
    assert b1["upload_count"] == 1
    assert b2["upload_count"] == 2
    # original_name is preserved from the first upload
    assert b2["original_name"] == "first.csv"
  end

  test "deduplication does not create a second file on disk", %{opts: opts} do
    content = "a,b\n1,2\n"
    call_upload(opts, "one.csv", content)
    call_upload(opts, "two.csv", content)

    files = File.ls!(@upload_dir)
    assert length(files) == 1
  end

  test "different content produces different ids and two files", %{opts: opts} do
    c1 = call_upload(opts, "a.csv", "a,b\n1,2\n")
    c2 = call_upload(opts, "b.csv", "c,d\n3,4\n")

    assert c1.status == 201
    assert c2.status == 201
    assert json_body(c1)["id"] != json_body(c2)["id"]
    assert length(File.ls!(@upload_dir)) == 2
  end

  test "file is persisted to disk under the hash name", %{opts: opts} do
    conn = call_upload(opts, "disk.csv", "col1,col2\nv1,v2\n")
    assert conn.status == 201
    body = json_body(conn)
    path = Path.join(@upload_dir, body["id"] <> ".csv")
    assert File.exists?(path)
    assert File.read!(path) == "col1,col2\nv1,v2\n"
  end

  test "valid JSON upload works", %{opts: opts} do
    conn = call_upload(opts, "data.json", Jason.encode!(%{"k" => "v"}))
    assert conn.status == 201
    assert json_body(conn)["content_type"] == "application/json"
  end

  test "rejects disallowed extension with 422", %{opts: opts} do
    conn = call_upload(opts, "notes.txt", "hello")
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "not allowed"
  end

  test "extension check is case-insensitive", %{opts: opts} do
    conn = call_upload(opts, "DATA.CSV", "a,b\n1,2\n")
    assert conn.status == 201
  end

  test "rejects invalid CSV with 422", %{opts: opts} do
    conn = call_upload(opts, "bad.csv", "justonevalue")
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "Invalid CSV"
  end

  test "rejects malformed JSON with 422", %{opts: opts} do
    conn = call_upload(opts, "bad.json", "{not json")
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "Invalid JSON"
  end

  test "rejects files larger than 5MB with 413", %{opts: opts} do
    big = String.duplicate("x", 5_242_881)
    conn = call_upload(opts, "huge.csv", big)
    assert conn.status == 413
    assert json_body(conn)["error"] =~ "too large"
  end

  test "returns 422 when no file field is provided", %{opts: opts} do
    conn =
      conn(:post, "/api/uploads", %{"other" => "x"})
      |> put_req_header("content-type", "multipart/form-data")
      |> FileUpload.Router.call(opts)

    assert conn.status == 422
    assert json_body(conn)["error"] =~ "No file"
  end

  test "metadata is retrievable from the store, and list dedups", %{opts: opts} do
    content = "p,q\n1,2\n"
    call_upload(opts, "s1.csv", content)
    call_upload(opts, "s2.csv", content)

    files = FileUpload.Store.list(:test_store)
    assert length(files) == 1
    [rec] = files
    assert {:ok, got} = FileUpload.Store.get(:test_store, rec.id)
    assert got.upload_count == 2
  end

  test "store get returns error for unknown id", _ctx do
    start_supervised!({FileUpload.Store, name: :lonely})
    assert {:error, :not_found} = FileUpload.Store.get(:lonely, "deadbeef")
  end

  test "uploaded_at is a valid ISO 8601 string and stable across dedup", %{opts: opts} do
    content = "a,b\n1,2\n"
    b1 = json_body(call_upload(opts, "t1.csv", content))
    b2 = json_body(call_upload(opts, "t2.csv", content))
    assert {:ok, _dt, _} = DateTime.from_iso8601(b1["uploaded_at"])
    assert b1["uploaded_at"] == b2["uploaded_at"]
  end

  test "id equals the real lowercase-hex SHA-256 of the uploaded bytes", %{opts: opts} do
    content = "h1,h2\nv1,v2\n"
    expected = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    conn = call_upload(opts, "hash.csv", content)
    assert conn.status == 201
    assert json_body(conn)["id"] == expected
  end

  test "413 body carries the exact error message and max_bytes value", %{opts: opts} do
    conn = call_upload(opts, "oversize.csv", String.duplicate("y", 5_242_881))
    assert conn.status == 413
    assert json_body(conn) == %{"error" => "File too large", "max_bytes" => 5_242_880}
  end

  test "a file of exactly 5_242_880 bytes is accepted, not rejected as too large", %{opts: opts} do
    content = "a,b\n" <> String.duplicate("x", 5_242_876)
    assert byte_size(content) == 5_242_880

    conn = call_upload(opts, "exactly_max.csv", content)
    assert conn.status == 201
    assert json_body(conn)["size"] == 5_242_880
  end

  test "download_url uses the configured base_url in the documented shape", _ctx do
    opts =
      FileUpload.Router.init(
        store: :test_store,
        upload_dir: @upload_dir,
        base_url: "https://files.example.test"
      )

    body = json_body(call_upload(opts, "url.csv", "u,v\n1,2\n"))
    assert body["download_url"] == "https://files.example.test/api/uploads/#{body["id"]}"
  end

  test "Store.save reports :created then :exists with preserved original fields", _ctx do
    meta1 = %{original_name: "orig.csv", size: 8, content_type: "text/csv"}
    meta2 = %{original_name: "later.csv", size: 8, content_type: "text/csv"}

    assert {:ok, :created, first} = FileUpload.Store.save(:test_store, "abc123", meta1)
    assert first.id == "abc123"
    assert first.upload_count == 1

    assert {:ok, :exists, second} = FileUpload.Store.save(:test_store, "abc123", meta2)
    assert second.id == "abc123"
    assert second.original_name == "orig.csv"
    assert second.uploaded_at == first.uploaded_at
    assert second.upload_count == 2
  end

  test "CSV passes on a lone comma line and on two comma-free lines", %{opts: opts} do
    single_line = call_upload(opts, "one_line.csv", "only,one,line")
    assert single_line.status == 201

    two_lines = call_upload(opts, "no_commas.csv", "alpha\nbeta\n")
    assert two_lines.status == 201
  end
end
