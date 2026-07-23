defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that stores upload metadata keyed by the SHA-256 content hash.

  The store is the source of truth for deduplication: the first time a hash is
  seen a record is created with an `:id`, an `:uploaded_at` timestamp and an
  `:upload_count` of `1`. Subsequent saves of the same hash simply increment the
  `:upload_count`, preserving the original identity fields.
  """

  use GenServer

  @typedoc "Arbitrary upload metadata stored under a content hash."
  @type metadata :: map()

  @doc """
  Starts the store.

  Accepts a `:name` option used to register the process. When omitted, the
  process is started unregistered.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{}, gen_opts)
  end

  @doc """
  Saves `metadata` under `hash`.

  Returns `{:ok, :created, record}` when the hash is new (adding `:id`,
  `:uploaded_at` and `:upload_count`) or `{:ok, :exists, record}` when the hash
  already exists, incrementing `:upload_count` while keeping the original
  `:id`, `:original_name` and `:uploaded_at`.
  """
  @spec save(GenServer.server(), String.t(), metadata()) ::
          {:ok, :created | :exists, metadata()}
  def save(server, hash, metadata) do
    GenServer.call(server, {:save, hash, metadata})
  end

  @doc """
  Fetches the metadata stored under `id`.

  Returns `{:ok, metadata}` or `{:error, :not_found}`.
  """
  @spec get(GenServer.server(), String.t()) ::
          {:ok, metadata()} | {:error, :not_found}
  def get(server, id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Returns all stored metadata records as a list.
  """
  @spec list(GenServer.server()) :: [metadata()]
  def list(server) do
    GenServer.call(server, :list)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:save, hash, metadata}, _from, state) do
    case Map.get(state, hash) do
      nil ->
        record =
          metadata
          |> Map.put(:id, hash)
          |> Map.put(:uploaded_at, timestamp())
          |> Map.put(:upload_count, 1)

        {:reply, {:ok, :created, record}, Map.put(state, hash, record)}

      existing ->
        updated = Map.update!(existing, :upload_count, &(&1 + 1))
        {:reply, {:ok, :exists, updated}, Map.put(state, hash, updated)}
    end
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    case Map.get(state, id) do
      nil -> {:reply, {:error, :not_found}, state}
      record -> {:reply, {:ok, record}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state), state}
  end

  @spec timestamp() :: String.t()
  defp timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end
end

defmodule FileUpload.Validator do
  @moduledoc """
  Validation rules for incoming uploads.

  Enforces an allow-list of file extensions (`.csv` and `.json`) and performs a
  lightweight content check appropriate to the detected type.
  """

  @allowed_extensions [".csv", ".json"]

  @doc """
  Validates a `%Plug.Upload{}` struct.

  Returns `:ok` when the file has an allowed extension and its contents pass the
  type-specific check, otherwise `{:error, reason}` with a descriptive message.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, String.t()}
  def validate(%Plug.Upload{} = upload) do
    ext = upload.filename |> Path.extname() |> String.downcase()

    with :ok <- validate_extension(ext) do
      validate_content(ext, upload)
    end
  end

  @spec validate_extension(String.t()) :: :ok | {:error, String.t()}
  defp validate_extension(ext) when ext in @allowed_extensions, do: :ok

  defp validate_extension(_ext) do
    {:error, "File type not allowed. Only .csv and .json files are accepted"}
  end

  @spec validate_content(String.t(), Plug.Upload.t()) ::
          :ok | {:error, String.t()}
  defp validate_content(".csv", upload), do: validate_csv(upload)
  defp validate_content(".json", upload), do: validate_json(upload)
  defp validate_content(_ext, _upload), do: :ok

  @spec validate_csv(Plug.Upload.t()) :: :ok | {:error, String.t()}
  defp validate_csv(upload) do
    invalid = {:error, "Invalid CSV: file must contain a header row with multiple columns"}

    case File.read(upload.path) do
      {:ok, contents} ->
        lines =
          contents
          |> String.split(["\r\n", "\n"])
          |> Enum.reject(&(&1 == ""))

        cond do
          length(lines) >= 2 -> :ok
          Enum.any?(lines, &String.contains?(&1, ",")) -> :ok
          true -> invalid
        end

      {:error, _reason} ->
        invalid
    end
  end

  @spec validate_json(Plug.Upload.t()) :: :ok | {:error, String.t()}
  defp validate_json(upload) do
    case File.read(upload.path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, _decoded} -> :ok
          {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
        end

      {:error, reason} ->
        {:error, "Invalid JSON: " <> to_string(:file.format_error(reason))}
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  A `Plug.Router` exposing a content-addressable, deduplicating file upload API.

  `POST /api/uploads` accepts a single multipart file under the form field
  `"file"`, validates it, and stores it by the SHA-256 hash of its bytes. The
  same content uploaded twice is recognised as a duplicate: no second disk file
  or record is created and the existing metadata is returned with an incremented
  upload count.

  Runtime options (via `plug FileUpload.Router, opts`):

    * `:store` — PID or name of the `FileUpload.Store` GenServer.
    * `:upload_dir` — directory where new files are written.
    * `:base_url` — URL prefix for generated download URLs.
  """

  use Plug.Router
  import Plug.Conn

  @max_bytes 5_242_880

  plug(:match)
  plug(:dispatch)

  post "/api/uploads" do
    case parse_body(conn) do
      {:ok, parsed} ->
        handle_upload(parsed, opts)

      {:error, :too_large} ->
        send_json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  @spec parse_body(Plug.Conn.t()) :: {:ok, Plug.Conn.t()} | {:error, :too_large}
  defp parse_body(conn) do
    parser_opts =
      Plug.Parsers.init(parsers: [:multipart], pass: ["*/*"], length: @max_bytes)

    {:ok, Plug.Parsers.call(conn, parser_opts)}
  rescue
    Plug.Parsers.RequestTooLargeError -> {:error, :too_large}
  end

  @spec handle_upload(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  defp handle_upload(conn, opts) do
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    case Map.get(conn.params, "file") do
      %Plug.Upload{} = upload ->
        process_upload(conn, upload, store, upload_dir, base_url)

      _other ->
        send_json(conn, 422, %{error: "No file provided"})
    end
  end

  @spec process_upload(
          Plug.Conn.t(),
          Plug.Upload.t(),
          GenServer.server(),
          String.t(),
          String.t()
        ) :: Plug.Conn.t()
  defp process_upload(conn, upload, store, upload_dir, base_url) do
    case FileUpload.Validator.validate(upload) do
      :ok ->
        store_upload(conn, upload, store, upload_dir, base_url)

      {:error, reason} ->
        send_json(conn, 422, %{error: reason})
    end
  end

  @spec store_upload(
          Plug.Conn.t(),
          Plug.Upload.t(),
          GenServer.server(),
          String.t(),
          String.t()
        ) :: Plug.Conn.t()
  defp store_upload(conn, upload, store, upload_dir, base_url) do
    contents = File.read!(upload.path)
    hash = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
    ext = upload.filename |> Path.extname() |> String.downcase()

    metadata = %{
      original_name: upload.filename,
      size: byte_size(contents),
      content_type: upload.content_type
    }

    case FileUpload.Store.save(store, hash, metadata) do
      {:ok, :created, record} ->
        write_file(upload_dir, hash, ext, contents)
        send_json(conn, 201, build_response(record, false, base_url))

      {:ok, :exists, record} ->
        send_json(conn, 200, build_response(record, true, base_url))
    end
  end

  @spec write_file(String.t(), String.t(), String.t(), binary()) :: :ok
  defp write_file(dir, hash, ext, contents) do
    File.mkdir_p!(dir)
    path = Path.join(dir, hash <> ext)
    File.write!(path, contents)
    :ok
  end

  @spec build_response(map(), boolean(), String.t()) :: map()
  defp build_response(record, deduplicated, base_url) do
    %{
      id: record.id,
      original_name: record.original_name,
      size: record.size,
      content_type: record.content_type,
      uploaded_at: record.uploaded_at,
      upload_count: record.upload_count,
      deduplicated: deduplicated,
      download_url: base_url <> "/api/uploads/" <> record.id
    }
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end