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
end
