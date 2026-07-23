defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that stores file metadata keyed by SHA-256 content hash.

  The store is the source of truth for deduplication: each unique content hash
  maps to a single metadata record. Re-saving an existing hash increments an
  `:upload_count` counter instead of creating a new record, which lets callers
  recognise duplicate uploads without touching disk twice.
  """

  use GenServer

  @typedoc "A metadata map keyed by string keys, as stored by the server."
  @type metadata :: %{optional(String.t()) => term()}

  # ---- Client API --------------------------------------------------------

  @doc """
  Starts the store.

  Accepts a `:name` option for process registration; any other options are
  ignored. Returns the standard `GenServer.on_start/0` result.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Saves `metadata` under `hash`.

  When `hash` is new, the record is enriched with `"id"` (equal to `hash`), an
  ISO 8601 UTC `"uploaded_at"` timestamp and an `"upload_count"` of `1`, and
  `{:ok, :created, record}` is returned. When `hash` already exists, the stored
  `"upload_count"` is incremented and `{:ok, :exists, record}` is returned,
  preserving the original `"id"`, `"original_name"` and `"uploaded_at"`.
  """
  @spec save(GenServer.server(), String.t(), metadata()) ::
          {:ok, :created | :exists, metadata()}
  def save(server, hash, metadata) do
    GenServer.call(server, {:save, hash, metadata})
  end

  @doc """
  Fetches the metadata stored under `id`.

  Returns `{:ok, metadata}` when present, otherwise `{:error, :not_found}`.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, metadata()} | {:error, :not_found}
  def get(server, id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Returns every stored metadata record as a list.
  """
  @spec list(GenServer.server()) :: [metadata()]
  def list(server) do
    GenServer.call(server, :list)
  end

  # ---- Server callbacks --------------------------------------------------

  @impl true
  @spec init(map()) :: {:ok, map()}
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:save, hash, metadata}, _from, state) do
    case Map.get(state, hash) do
      nil ->
        record =
          metadata
          |> Map.put("id", hash)
          |> Map.put("uploaded_at", utc_now_iso8601())
          |> Map.put("upload_count", 1)

        {:reply, {:ok, :created, record}, Map.put(state, hash, record)}

      existing ->
        record =
          existing
          |> Map.update("upload_count", 1, &(&1 + 1))

        {:reply, {:ok, :exists, record}, Map.put(state, hash, record)}
    end
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    case Map.get(state, id) do
      nil -> {:reply, {:error, :not_found}, state}
      metadata -> {:reply, {:ok, metadata}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state), state}
  end

  # ---- Internal helpers --------------------------------------------------

  @spec utc_now_iso8601() :: String.t()
  defp utc_now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end

defmodule FileUpload.Validator do
  @moduledoc """
  Validates uploaded files by extension and content.

  Only `.csv` and `.json` files are accepted. CSV files must look like they
  contain a header row (two or more lines, or at least one comma). JSON files
  must parse cleanly via `Jason.decode/1`.
  """

  @allowed_extensions [".csv", ".json"]

  @doc """
  Validates a `%Plug.Upload{}` struct.

  Returns `:ok` when the upload passes extension and content checks, otherwise
  `{:error, reason}` with a human-readable reason string.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, String.t()}
  def validate(%Plug.Upload{filename: filename, path: path}) do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in @allowed_extensions do
      validate_content(ext, path)
    else
      {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

  @spec validate_content(String.t(), String.t()) :: :ok | {:error, String.t()}
  defp validate_content(".csv", path) do
    contents = read_file(path)

    lines =
      contents
      |> String.split(["\r\n", "\n", "\r"], trim: true)

    cond do
      length(lines) >= 2 -> :ok
      Enum.any?(lines, &String.contains?(&1, ",")) -> :ok
      true -> {:error, "Invalid CSV: file must contain a header row with multiple columns"}
    end
  end

  defp validate_content(".json", path) do
    contents = read_file(path)

    case Jason.decode(contents) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end

  @spec read_file(String.t()) :: binary()
  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, _reason} -> ""
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  A `Plug.Router` exposing a content-addressable, deduplicating upload endpoint.

  `POST /api/uploads` accepts a single multipart file under the form field
  `"file"`. The file's identity is the SHA-256 hash of its bytes, so uploading
  identical content twice — even under different names — reuses the existing
  record and stored file instead of creating duplicates.

  Router options (via `plug FileUpload.Router, opts`):

    * `:store` — PID or registered name of a `FileUpload.Store`.
    * `:upload_dir` — directory where files are written to disk.
    * `:base_url` — URL prefix used to build the `download_url`.
  """

  use Plug.Router

  @max_bytes 5_242_880

  plug Plug.Parsers,
    parsers: [:multipart],
    length: @max_bytes,
    pass: ["*/*"]

  plug :match
  plug :dispatch

  @doc """
  Initialises router options, returning them unchanged as a keyword list.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Invokes the router for `conn`, translating oversized requests to HTTP 413.

  Delegates to the generated `Plug.Router` implementation and rescues the
  `Plug.Parsers.RequestTooLargeError` raised when a body exceeds the configured
  maximum size.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    super(conn, opts)
  rescue
    Plug.Parsers.RequestTooLargeError ->
      send_json(conn, 413, %{"error" => "File too large", "max_bytes" => @max_bytes})
  end

  post "/api/uploads" do
    handle_upload(conn, Map.get(conn.body_params, "file"))
  end

  match _ do
    send_json(conn, 404, %{"error" => "Not found"})
  end

  # ---- Request handling --------------------------------------------------

  @spec handle_upload(Plug.Conn.t(), Plug.Upload.t() | nil) :: Plug.Conn.t()
  defp handle_upload(conn, %Plug.Upload{} = upload) do
    case FileUpload.Validator.validate(upload) do
      :ok -> store_upload(conn, upload)
      {:error, reason} -> send_json(conn, 422, %{"error" => reason})
    end
  end

  defp handle_upload(conn, _missing) do
    send_json(conn, 422, %{"error" => "No file provided"})
  end

  @spec store_upload(Plug.Conn.t(), Plug.Upload.t()) :: Plug.Conn.t()
  defp store_upload(conn, upload) do
    contents = File.read!(upload.path)
    hash = sha256_hex(contents)
    opts = conn.private[:file_upload_opts] || conn.assigns[:file_upload_opts] || router_opts(conn)

    metadata = %{
      "original_name" => upload.filename,
      "size" => byte_size(contents),
      "content_type" => upload.content_type,
      "download_url" => download_url(opts[:base_url], hash)
    }

    case FileUpload.Store.save(opts[:store], hash, metadata) do
      {:ok, :created, record} ->
        write_file(opts[:upload_dir], hash, upload.filename, contents)
        send_json(conn, 201, response_body(record, false))

      {:ok, :exists, record} ->
        send_json(conn, 200, response_body(record, true))
    end
  end

  @spec router_opts(Plug.Conn.t()) :: keyword()
  defp router_opts(conn) do
    conn.private[:plug_router_opts] || []
  end

  @spec response_body(map(), boolean()) :: map()
  defp response_body(record, deduplicated) do
    %{
      "id" => record["id"],
      "original_name" => record["original_name"],
      "size" => record["size"],
      "content_type" => record["content_type"],
      "uploaded_at" => record["uploaded_at"],
      "upload_count" => record["upload_count"],
      "deduplicated" => deduplicated,
      "download_url" => record["download_url"]
    }
  end

  @spec write_file(String.t(), String.t(), String.t(), binary()) :: :ok
  defp write_file(upload_dir, hash, filename, contents) do
    File.mkdir_p!(upload_dir)
    ext = filename |> Path.extname() |> String.downcase()
    File.write!(Path.join(upload_dir, hash <> ext), contents)
    :ok
  end

  @spec download_url(String.t(), String.t()) :: String.t()
  defp download_url(base_url, hash) do
    String.trim_trailing(base_url, "/") <> "/api/uploads/" <> hash
  end

  @spec sha256_hex(binary()) :: String.t()
  defp sha256_hex(contents) do
    :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end