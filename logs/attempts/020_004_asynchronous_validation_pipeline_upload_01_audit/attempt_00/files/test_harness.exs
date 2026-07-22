defmodule FileUploadTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @upload_dir Path.join(
                System.tmp_dir!(),
                "file_upload_async_test_#{System.pid()}_#{System.unique_integer([:positive])}"
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

  defp post_upload(opts, filename, content, content_type \\ nil) do
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

  defp get_status(opts, id) do
    conn(:get, "/api/uploads/#{id}") |> FileUpload.Router.call(opts)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  # Poll the store directly until the record settles out of :pending.
  defp await_settled(store, id) do
    Enum.reduce_while(1..200, nil, fn _, _ ->
      {:ok, rec} = FileUpload.Store.get(store, id)

      if rec.status == :pending do
        Process.sleep(5)
        {:cont, nil}
      else
        {:halt, rec}
      end
    end)
  end

  test "POST returns 202 pending synchronously with a status_url", %{opts: opts} do
    conn = post_upload(opts, "people.csv", "name,age\nAlice,30\n")
    assert conn.status == 202
    body = json_body(conn)
    assert body["status"] == "pending"
    assert is_binary(body["id"])
    assert String.length(body["id"]) == 36
    assert String.contains?(body["status_url"], body["id"])
    assert body["original_name"] == "people.csv"
    assert {:ok, _dt, _} = DateTime.from_iso8601(body["uploaded_at"])
  end

  test "valid CSV eventually transitions to valid with a download_url", %{opts: opts} do
    conn = post_upload(opts, "ok.csv", "a,b\n1,2\n")
    id = json_body(conn)["id"]

    rec = await_settled(:test_store, id)
    assert rec.status == :valid

    got = get_status(opts, id)
    assert got.status == 200
    body = json_body(got)
    assert body["status"] == "valid"
    assert String.contains?(body["download_url"], id)
  end

  test "valid JSON eventually transitions to valid", %{opts: opts} do
    conn = post_upload(opts, "d.json", Jason.encode!(%{"k" => "v"}))
    id = json_body(conn)["id"]
    rec = await_settled(:test_store, id)
    assert rec.status == :valid
    assert json_body(get_status(opts, id))["status"] == "valid"
  end

  test "invalid CSV content transitions to invalid with an error", %{opts: opts} do
    conn = post_upload(opts, "bad.csv", "singlevalue")
    assert conn.status == 202
    id = json_body(conn)["id"]

    rec = await_settled(:test_store, id)
    assert rec.status == :invalid

    body = json_body(get_status(opts, id))
    assert body["status"] == "invalid"
    assert body["error"] =~ "Invalid CSV"
    refute Map.has_key?(body, "download_url")
  end

  test "disallowed type transitions to invalid via the async pipeline", %{opts: opts} do
    conn = post_upload(opts, "notes.txt", "hello")
    assert conn.status == 202
    id = json_body(conn)["id"]

    rec = await_settled(:test_store, id)
    assert rec.status == :invalid
    assert json_body(get_status(opts, id))["error"] =~ "not allowed"
  end

  test "malformed JSON transitions to invalid", %{opts: opts} do
    conn = post_upload(opts, "bad.json", "{nope")
    id = json_body(conn)["id"]
    rec = await_settled(:test_store, id)
    assert rec.status == :invalid
    assert json_body(get_status(opts, id))["error"] =~ "Invalid JSON"
  end

  test "file is persisted to disk immediately (even while pending)", %{opts: opts} do
    conn = post_upload(opts, "disk.csv", "col1,col2\nv1,v2\n")
    id = json_body(conn)["id"]
    # copy is synchronous, so the file exists right after the request returns
    path = Path.join(@upload_dir, id <> ".csv")
    assert File.exists?(path)
    assert File.read!(path) == "col1,col2\nv1,v2\n"
  end

  test "oversize file is rejected synchronously with 413", %{opts: opts} do
    big = String.duplicate("x", 5_242_881)
    conn = post_upload(opts, "huge.csv", big)
    assert conn.status == 413
    assert json_body(conn)["error"] =~ "too large"
  end

  test "413 body reports the exact 5MB limit under max_bytes", %{opts: opts} do
    conn = post_upload(opts, "huge2.csv", String.duplicate("y", 5_242_881))
    assert conn.status == 413
    body = json_body(conn)
    assert body["error"] == "File too large"
    assert body["max_bytes"] == 5_242_880
    # rejection happens before acceptance: no record is created for it
    assert FileUpload.Store.list(:test_store) == []
  end

  test "missing file field returns 422", %{opts: opts} do
    conn =
      conn(:post, "/api/uploads", %{"nope" => "x"})
      |> put_req_header("content-type", "multipart/form-data")
      |> FileUpload.Router.call(opts)

    assert conn.status == 422
    assert json_body(conn)["error"] =~ "No file"
  end

  test "GET on unknown id returns 404", %{opts: opts} do
    conn = get_status(opts, "no-such-id")
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "Not found"
  end

  test "store list contains created records", %{opts: opts} do
    post_upload(opts, "a.csv", "x,y\n1,2\n")
    post_upload(opts, "b.json", Jason.encode!(%{"ok" => true}))
    assert length(FileUpload.Store.list(:test_store)) == 2
  end

  test "update_status on unknown id returns error", _ctx do
    start_supervised!({FileUpload.Store, name: :other_store})
    assert {:error, :not_found} = FileUpload.Store.update_status(:other_store, "x", :valid, %{})
  end

  test "file of exactly the 5MB limit is accepted, not rejected", %{opts: opts} do
    content = "a,b\n" <> String.duplicate("x", 5_242_876)
    assert byte_size(content) == 5_242_880
    conn = post_upload(opts, "limit.csv", content)
    assert conn.status == 202
    body = json_body(conn)
    assert body["status"] == "pending"
    assert body["size"] == 5_242_880
    assert length(FileUpload.Store.list(:test_store)) == 1
  end

  test "uppercase extensions are accepted case-insensitively by the pipeline", %{opts: opts} do
    csv_conn = post_upload(opts, "SHOUT.CSV", "a,b\n1,2\n", "text/csv")
    csv_id = json_body(csv_conn)["id"]
    json_conn = post_upload(opts, "SHOUT.JSON", Jason.encode!(%{"k" => 1}), "application/json")
    json_id = json_body(json_conn)["id"]

    assert await_settled(:test_store, csv_id).status == :valid
    assert await_settled(:test_store, json_id).status == :valid
    assert json_body(get_status(opts, csv_id))["status"] == "valid"
    assert json_body(get_status(opts, json_id))["status"] == "valid"
  end

  test "single comma-containing CSV line is valid at the boundary", %{opts: opts} do
    conn = post_upload(opts, "oneline.csv", "a,b")
    id = json_body(conn)["id"]
    assert await_settled(:test_store, id).status == :valid

    other = post_upload(opts, "twolines.csv", "abc\ndef\n")
    other_id = json_body(other)["id"]
    assert await_settled(:test_store, other_id).status == :valid
  end

  test "status_url and download_url use the exact documented base_url shapes", %{opts: opts} do
    conn = post_upload(opts, "urls.csv", "a,b\n1,2\n")
    body = json_body(conn)
    id = body["id"]
    assert body["status_url"] == "http://localhost:4000/api/uploads/#{id}"

    assert await_settled(:test_store, id).status == :valid
    got = json_body(get_status(opts, id))
    assert got["download_url"] == "http://localhost:4000/api/uploads/#{id}/download"
  end

  test "GET on a pending record returns the full base body without download_url or error", ctx do
    {:ok, record} =
      FileUpload.Store.create(:test_store, %{
        original_name: "waiting.csv",
        size: 12,
        content_type: "text/csv"
      })

    conn = get_status(ctx.opts, record.id)
    assert conn.status == 200
    body = json_body(conn)
    assert body["status"] == "pending"
    assert body["id"] == record.id
    assert body["original_name"] == "waiting.csv"
    assert body["size"] == 12
    assert body["content_type"] == "text/csv"
    assert {:ok, _dt, _} = DateTime.from_iso8601(body["uploaded_at"])
    refute Map.has_key?(body, "download_url")
    refute Map.has_key?(body, "error")
  end

  test "update_status merges extra keys and sets status on an existing record", _ctx do
    {:ok, record} =
      FileUpload.Store.create(:test_store, %{
        original_name: "m.json",
        size: 3,
        content_type: "application/json"
      })

    assert :ok = FileUpload.Store.update_status(:test_store, record.id, :valid, %{note: "hi"})
    {:ok, updated} = FileUpload.Store.get(:test_store, record.id)
    assert updated.status == :valid
    assert updated.note == "hi"
    assert updated.original_name == "m.json"
    assert updated.uploaded_at == record.uploaded_at
  end
end
