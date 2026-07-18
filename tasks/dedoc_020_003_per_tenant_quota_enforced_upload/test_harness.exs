defmodule FileUploadTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @upload_dir Path.join(
                System.tmp_dir!(),
                "file_upload_quota_test_#{System.pid()}_#{System.unique_integer([:positive])}"
              )

  setup_all do
    File.mkdir_p!(@upload_dir)
    on_exit(fn -> File.rm_rf!(@upload_dir) end)
    :ok
  end

  setup do
    @upload_dir |> File.ls!() |> Enum.each(&File.rm!(Path.join(@upload_dir, &1)))
    start_supervised!({FileUpload.Store, name: :big_store, quota_bytes: 1_000_000})

    opts =
      FileUpload.Router.init(
        store: :big_store,
        upload_dir: @upload_dir,
        base_url: "http://localhost:4000"
      )

    %{opts: opts}
  end

  defp opts_for(store) do
    FileUpload.Router.init(
      store: store,
      upload_dir: @upload_dir,
      base_url: "http://localhost:4000"
    )
  end

  defp upload_conn(opts, account, filename, content, content_type \\ nil) do
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

    base = conn(:post, "/api/uploads", %{"file" => upload})
    base = put_req_header(base, "content-type", "multipart/form-data")
    base = if account, do: put_req_header(base, "x-account-id", account), else: base

    conn = FileUpload.Router.call(base, opts)
    File.rm(tmp_path)
    conn
  end

  defp delete_conn(opts, account, id) do
    base = conn(:delete, "/api/uploads/#{id}")
    base = if account, do: put_req_header(base, "x-account-id", account), else: base
    FileUpload.Router.call(base, opts)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  test "valid upload under quota returns 201 with usage info", %{opts: opts} do
    conn = upload_conn(opts, "acct1", "a.csv", "name,age\nAlice,30\n")
    assert conn.status == 201
    body = json_body(conn)
    assert body["account_id"] == "acct1"
    assert body["quota_bytes"] == 1_000_000
    assert body["used_bytes"] == byte_size("name,age\nAlice,30\n")
    assert String.contains?(body["download_url"], body["id"])
  end

  test "usage accumulates across uploads for the same account", %{opts: opts} do
    upload_conn(opts, "acct1", "a.csv", "a,b\n1,2\n")
    conn = upload_conn(opts, "acct1", "b.csv", "c,d\n3,4\n")
    assert conn.status == 201
    assert json_body(conn)["used_bytes"] == 16
    assert FileUpload.Store.usage(:big_store, "acct1") == 16
  end

  test "quota is enforced per-account and independent", _ctx do
    start_supervised!({FileUpload.Store, name: :q16, quota_bytes: 16})
    o = opts_for(:q16)

    # acct A fills its own budget
    assert upload_conn(o, "A", "a.csv", "a,b\n1,2\n").status == 201
    assert upload_conn(o, "A", "b.csv", "c,d\n3,4\n").status == 201
    # A is now full
    assert upload_conn(o, "A", "c.csv", "e,f\n5,6\n").status == 507
    # B has its own fresh budget
    assert upload_conn(o, "B", "a.csv", "a,b\n1,2\n").status == 201
  end

  test "over-quota upload returns 507 and consumes nothing", _ctx do
    start_supervised!({FileUpload.Store, name: :q10, quota_bytes: 10})
    o = opts_for(:q10)

    assert upload_conn(o, "A", "a.csv", "a,b\n1,2\n").status == 201
    before = FileUpload.Store.usage(:q10, "A")

    conn = upload_conn(o, "A", "big.csv", "aa,bb\n11,22\n")
    assert conn.status == 507
    body = json_body(conn)
    assert body["error"] =~ "Quota exceeded"
    assert body["quota_bytes"] == 10
    assert body["used_bytes"] == before
    assert body["requested_bytes"] == byte_size("aa,bb\n11,22\n")
    # usage unchanged, no extra disk file
    assert FileUpload.Store.usage(:q10, "A") == before
    assert length(File.ls!(@upload_dir)) == 1
  end

  test "exactly at quota succeeds, one byte over fails", _ctx do
    start_supervised!({FileUpload.Store, name: :q8, quota_bytes: 8})
    o = opts_for(:q8)

    # exactly 8 bytes
    assert upload_conn(o, "A", "a.csv", "a,b\n1,2\n").status == 201
    assert FileUpload.Store.usage(:q8, "A") == 8
    # any further byte exceeds
    assert upload_conn(o, "A", "b.csv", "c,d\n3,4\n").status == 507
  end

  test "missing account header returns 400 on POST", %{opts: opts} do
    conn = upload_conn(opts, nil, "a.csv", "a,b\n1,2\n")
    assert conn.status == 400
    assert json_body(conn)["error"] =~ "Missing account"
  end

  test "delete frees quota and allows re-upload", _ctx do
    start_supervised!({FileUpload.Store, name: :qd, quota_bytes: 8})
    o = opts_for(:qd)

    up = upload_conn(o, "A", "a.csv", "a,b\n1,2\n")
    assert up.status == 201
    id = json_body(up)["id"]

    # full now
    assert upload_conn(o, "A", "b.csv", "c,d\n3,4\n").status == 507

    del = delete_conn(o, "A", id)
    assert del.status == 200
    dbody = json_body(del)
    assert dbody["freed_bytes"] == 8
    assert dbody["used_bytes"] == 0
    assert FileUpload.Store.usage(:qd, "A") == 0
    refute File.exists?(Path.join(@upload_dir, id <> ".csv"))

    # budget freed, re-upload works
    assert upload_conn(o, "A", "c.csv", "e,f\n5,6\n").status == 201
  end

  test "delete by wrong account is forbidden", %{opts: opts} do
    up = upload_conn(opts, "owner", "a.csv", "a,b\n1,2\n")
    id = json_body(up)["id"]
    conn = delete_conn(opts, "intruder", id)
    assert conn.status == 403
    assert json_body(conn)["error"] =~ "Forbidden"
    # still present
    assert File.exists?(Path.join(@upload_dir, id <> ".csv"))
  end

  test "delete of unknown id returns 404", %{opts: opts} do
    conn = delete_conn(opts, "acct1", "does-not-exist")
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "Not found"
  end

  test "validation still enforced (invalid CSV -> 422, no quota used)", _ctx do
    start_supervised!({FileUpload.Store, name: :qv, quota_bytes: 1000})
    o = opts_for(:qv)
    conn = upload_conn(o, "A", "bad.csv", "singlevalue")
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "Invalid CSV"
    assert FileUpload.Store.usage(:qv, "A") == 0
  end

  test "size limit enforced with 413", %{opts: opts} do
    big = String.duplicate("x", 5_242_881)
    conn = upload_conn(opts, "acct1", "huge.csv", big)
    assert conn.status == 413
  end

  test "missing file field returns 422", %{opts: opts} do
    base =
      conn(:post, "/api/uploads", %{"nope" => "x"})
      |> put_req_header("content-type", "multipart/form-data")
      |> put_req_header("x-account-id", "acct1")

    conn = FileUpload.Router.call(base, opts)
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "No file"
  end

  test "store list and get reflect saved records", %{opts: opts} do
    up = upload_conn(opts, "acct1", "s.csv", "x,y\n1,2\n")
    id = json_body(up)["id"]
    assert {:ok, rec} = FileUpload.Store.get(:big_store, id)
    assert rec.account == "acct1"
    assert length(FileUpload.Store.list(:big_store)) == 1
  end

  test "uploaded_at is valid ISO 8601", %{opts: opts} do
    up = upload_conn(opts, "acct1", "t.csv", "a,b\n1,2\n")
    assert {:ok, _dt, _} = DateTime.from_iso8601(json_body(up)["uploaded_at"])
  end
end
