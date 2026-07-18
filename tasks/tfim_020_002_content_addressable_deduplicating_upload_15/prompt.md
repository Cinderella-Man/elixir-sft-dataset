# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule FileUpload.Store do
  @moduledoc """
  A content-addressable `GenServer` store: uploaded-file metadata is keyed by the
  SHA-256 hash of the file's bytes. Re-storing the same hash does not create a new
  record — it increments an `:upload_count` and returns the existing metadata,
  giving deduplication semantics.
  """

  use GenServer

  @doc """
  Starts the store. Accepts a `:name` option for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Returns the supervisor child specification for this store.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Stores `metadata` under `hash`. Returns `{:ok, :created, record}` for a new hash
  (adding `:id`, `:uploaded_at`, `:upload_count` = 1) or `{:ok, :exists, record}`
  for a known hash (incrementing `:upload_count`, preserving original fields).
  """
  @spec save(GenServer.server(), String.t(), map()) :: {:ok, :created | :exists, map()}
  def save(server, hash, metadata), do: GenServer.call(server, {:save, hash, metadata})

  @doc """
  Fetches stored metadata by `id`, returning `{:ok, metadata}` or
  `{:error, :not_found}`.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(server, id), do: GenServer.call(server, {:get, id})

  @doc """
  Lists all stored metadata records.
  """
  @spec list(GenServer.server()) :: [map()]
  def list(server), do: GenServer.call(server, :list)

  @doc """
  Initializes the store with an empty file map.
  """
  @spec init(keyword()) :: {:ok, %{files: map()}}
  @impl true
  def init(_opts), do: {:ok, %{files: %{}}}

  @doc """
  Handles the store's `save`, `get` and `list` synchronous calls.
  """
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  @impl true
  def handle_call({:save, hash, metadata}, _from, state) do
    case Map.fetch(state.files, hash) do
      {:ok, record} ->
        updated = %{record | upload_count: record.upload_count + 1}
        {:reply, {:ok, :exists, updated}, put_in(state.files[hash], updated)}

      :error ->
        record =
          metadata
          |> Map.put(:id, hash)
          |> Map.put(:uploaded_at, DateTime.utc_now() |> DateTime.to_iso8601())
          |> Map.put(:upload_count, 1)

        {:reply, {:ok, :created, record}, put_in(state.files[hash], record)}
    end
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
end

defmodule FileUpload.Validator do
  @moduledoc """
  Validates a `%Plug.Upload{}`: enforces the allowed extension set (`.csv`,
  `.json`, case-insensitive) and checks basic content validity per type.
  """

  @doc """
  Validates the given upload, returning `:ok` or `{:error, reason_string}`.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, String.t()}
  def validate(%Plug.Upload{filename: filename, path: path}) do
    case filename |> Path.extname() |> String.downcase() do
      ".csv" -> validate_csv(path)
      ".json" -> validate_json(path)
      _ -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

  @spec validate_csv(Path.t()) :: :ok | {:error, String.t()}
  defp validate_csv(path) do
    lines = path |> File.read!() |> String.split(~r/\r?\n/, trim: true)

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

  @spec validate_json(Path.t()) :: :ok | {:error, String.t()}
  defp validate_json(path) do
    case Jason.decode(File.read!(path)) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  `Plug.Router` exposing `POST /api/uploads` with content-addressable
  deduplication: the SHA-256 of the file's bytes is its id. New content is stored
  and returns 201; already-seen content returns 200 with `deduplicated` = true and
  never re-writes the disk file.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  alias FileUpload.{Store, Validator}

  @max_bytes 5_242_880

  plug(:match)
  plug(:dispatch)

  post "/api/uploads" do
    opts = conn.assigns.router_opts

    case conn.params["file"] do
      %Plug.Upload{} = upload -> handle_upload(conn, upload, opts)
      _ -> json(conn, 422, %{error: "No file provided"})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  @spec handle_upload(Plug.Conn.t(), Plug.Upload.t(), keyword()) :: Plug.Conn.t()
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
          :ok -> store_and_persist(conn, upload, size, store, upload_dir, base_url)
          {:error, reason} -> json(conn, 422, %{error: reason})
        end
    end
  end

  @spec store_and_persist(
          Plug.Conn.t(),
          Plug.Upload.t(),
          non_neg_integer(),
          GenServer.server(),
          Path.t(),
          String.t()
        ) :: Plug.Conn.t()
  defp store_and_persist(conn, upload, size, store, upload_dir, base_url) do
    content = File.read!(upload.path)
    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    metadata = %{
      original_name: upload.filename,
      size: size,
      content_type: upload.content_type
    }

    {status_code, dedup?, record} =
      case Store.save(store, hash, metadata) do
        {:ok, :created, record} ->
          ext = Path.extname(upload.filename)
          File.cp!(upload.path, Path.join(upload_dir, hash <> ext))
          {201, false, record}

        {:ok, :exists, record} ->
          {200, true, record}
      end

    response = %{
      id: record.id,
      original_name: record.original_name,
      size: record.size,
      content_type: record.content_type,
      uploaded_at: record.uploaded_at,
      upload_count: record.upload_count,
      deduplicated: dedup?,
      download_url: "#{base_url}/api/uploads/#{record.id}"
    }

    json(conn, status_code, response)
  end

  @spec json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
  end

  test "uploaded_at is a valid ISO 8601 string and stable across dedup", %{opts: opts} do
    content = "a,b\n1,2\n"
    b1 = json_body(call_upload(opts, "t1.csv", content))
    b2 = json_body(call_upload(opts, "t2.csv", content))
    assert {:ok, _dt, _} = DateTime.from_iso8601(b1["uploaded_at"])
    assert b1["uploaded_at"] == b2["uploaded_at"]
  end
end
```
