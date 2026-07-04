# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
<file path="lib/file_upload.ex">
defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that stores uploaded-file metadata in memory, keyed by a
  generated UUID v4, and stamps each record with an ISO 8601 UTC timestamp.
  """

  use GenServer

  @max_bytes 5_242_880

  def max_bytes, do: @max_bytes

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Stores `metadata`, adding an `:id` (UUID v4) and an `:uploaded_at` ISO 8601
  timestamp. Returns `{:ok, full_metadata}`.
  """
  def save(server, metadata), do: GenServer.call(server, {:save, metadata})

  def get(server, id), do: GenServer.call(server, {:get, id})

  def list(server), do: GenServer.call(server, :list)

  @impl true
  def init(_opts), do: {:ok, %{files: %{}}}

  @impl true
  def handle_call({:save, metadata}, _from, state) do
    id = uuid_v4()
    uploaded_at = DateTime.utc_now() |> DateTime.to_iso8601()

    record =
      metadata
      |> Map.put(:id, id)
      |> Map.put(:uploaded_at, uploaded_at)

    {:reply, {:ok, record}, put_in(state.files[id], record)}
  end

  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state.files, id) do
      {:ok, record} -> {:reply, {:ok, record}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.files), state}
  end

  defp uuid_v4 do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<a::32, b::16, c::16, d::16, e::48>> = <<u0::48, 4::4, u1::12, 2::2, u2::62>>

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
end

defmodule FileUpload.Validator do
  @moduledoc """
  Validates a `%Plug.Upload{}`: enforces the allowed extension set (`.csv`,
  `.json`, case-insensitive) and checks basic content validity per type.
  """

  def validate(%Plug.Upload{filename: filename, path: path}) do
    case filename |> Path.extname() |> String.downcase() do
      ".csv" -> validate_csv(path)
      ".json" -> validate_json(path)
      _ -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

  defp validate_csv(path) do
    content = File.read!(path)
    lines = String.split(content, ~r/\r?\n/, trim: true)

    cond do
      lines == [] ->
        {:error, "Invalid CSV: file must contain a header row with multiple columns"}

      length(lines) >= 2 ->
        :ok

      String.contains?(hd(lines), ",") ->
        :ok

      true ->
        {:error, "Invalid CSV: file must contain a header row with multiple columns"}
    end
  end

  defp validate_json(path) do
    content = File.read!(path)

    case Jason.decode(content) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  `Plug.Router` exposing `POST /api/uploads`. Enforces a 5MB size limit,
  delegates validation to `FileUpload.Validator` and storage to
  `FileUpload.Store`, and persists the file to disk under its generated UUID.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  alias FileUpload.{Store, Validator}

  @max_bytes 5_242_880

  plug :match
  plug :dispatch

  post "/api/uploads" do
    opts = conn.assigns.router_opts

    case conn.params["file"] do
      %Plug.Upload{} = upload ->
        handle_upload(conn, upload, opts)

      _ ->
        json(conn, 422, %{error: "No file provided"})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp handle_upload(conn, upload, opts) do
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    size = File.stat!(upload.path).size

    cond do
      size > @max_bytes ->
        json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})

      true ->
        case Validator.validate(upload) do
          :ok ->
            store_and_persist(conn, upload, size, store, upload_dir, base_url)

          {:error, reason} ->
            json(conn, 422, %{error: reason})
        end
    end
  end

  defp store_and_persist(conn, upload, size, store, upload_dir, base_url) do
    metadata = %{
      original_name: upload.filename,
      size: size,
      content_type: upload.content_type
    }

    {:ok, record} = Store.save(store, metadata)

    ext = Path.extname(upload.filename)
    dest = Path.join(upload_dir, record.id <> ext)
    File.cp!(upload.path, dest)

    download_url = "#{base_url}/api/uploads/#{record.id}"
    response = Map.put(record, :download_url, download_url)

    json(conn, 201, response)
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
</file>
```

## Test harness — implement the `# TODO` test

```elixir
defmodule FileUploadTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @upload_dir Path.join(System.tmp_dir!(), "file_upload_test_#{System.pid()}_#{System.unique_integer([:positive])}")

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
    tmp_path = Path.join(System.tmp_dir!(), "upload_#{System.pid()}_#{System.unique_integer([:positive])}_#{filename}")
    File.write!(tmp_path, content)

    ct =
      content_type ||
        case Path.extname(filename) do
          ".csv" -> "text/csv"
          ".json" -> "application/json"
          _ext -> "application/octet-stream"
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
    # TODO
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
```
