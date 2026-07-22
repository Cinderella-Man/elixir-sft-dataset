defmodule FileUpload.Validator do
  @moduledoc """
  Validation rules for incoming `%Plug.Upload{}` structs.

  Two checks are performed, in order:

    1. The file extension must be `.csv` or `.json` (case-insensitive).
    2. The file contents must be structurally valid for that extension:
       * CSV — at least two lines, or a single line containing a comma.
       * JSON — must parse successfully with `Jason.decode/1`.

  Every failure is reported as `{:error, message}` with a human readable
  message that is safe to hand straight back to the client.
  """

  @allowed_extensions ~w(.csv .json)

  @type reason :: String.t()

  @doc """
  Validates an upload.

  Returns `:ok` when the file has an allowed extension and its contents parse
  as the corresponding format, otherwise `{:error, reason}` where `reason` is a
  descriptive, client-safe message.

  ## Examples

      iex> FileUpload.Validator.validate(%Plug.Upload{filename: "a.txt", path: "/tmp/a"})
      {:error, "File type not allowed. Only .csv and .json files are accepted"}

  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, reason()}
  def validate(%Plug.Upload{filename: filename, path: path}) do
    extension = filename |> Path.extname() |> String.downcase()

    if extension in @allowed_extensions do
      validate_contents(extension, path)
    else
      {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

  @spec validate_contents(String.t(), Path.t()) :: :ok | {:error, reason()}
  defp validate_contents(extension, path) do
    case File.read(path) do
      {:ok, contents} -> validate_body(extension, contents)
      {:error, posix} -> {:error, "Could not read uploaded file: #{:file.format_error(posix)}"}
    end
  end

  @spec validate_body(String.t(), binary()) :: :ok | {:error, reason()}
  defp validate_body(".csv", contents), do: validate_csv(contents)
  defp validate_body(".json", contents), do: validate_json(contents)

  @spec validate_csv(binary()) :: :ok | {:error, reason()}
  defp validate_csv(contents) do
    lines =
      contents
      |> String.split(~r/\r\n|\r|\n/, trim: true)
      |> Enum.reject(&(String.trim(&1) == ""))

    multiple_lines? = length(lines) >= 2
    has_comma? = Enum.any?(lines, &String.contains?(&1, ","))

    if multiple_lines? or has_comma? do
      :ok
    else
      {:error, "Invalid CSV: file must contain a header row with multiple columns"}
    end
  end

  @spec validate_json(binary()) :: :ok | {:error, reason()}
  defp validate_json(contents) do
    case Jason.decode(contents) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end
end

defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` holding upload metadata keyed by the SHA-256 hash of the file
  contents (content-addressable storage).

  Because the key is derived from the bytes themselves, uploading identical
  content twice — even under different filenames — resolves to the same record.
  In that case only the `:upload_count` changes: the original `:id`,
  `:original_name` and `:uploaded_at` are preserved, and the caller is told the
  record already existed so that it can skip writing the file to disk again.

  State is an in-memory map of `hash => metadata`.
  """

  use GenServer

  @type hash :: String.t()
  @type metadata :: %{optional(atom()) => term()}

  # --- Client API ---------------------------------------------------------

  @doc """
  Starts the store.

  Accepts the usual `GenServer` options; `:name` is commonly used to register
  the process so that routers can refer to it by name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Saves `metadata` under `hash`.

  When `hash` has not been seen before the record is created — `:id` is set to
  the hash, `:uploaded_at` to the current UTC time in ISO 8601 form and
  `:upload_count` to `1` — and `{:ok, :created, record}` is returned.

  When `hash` is already present the stored record's `:upload_count` is
  incremented and `{:ok, :exists, record}` is returned; the original `:id`,
  `:original_name` and `:uploaded_at` are left untouched.
  """
  @spec save(GenServer.server(), hash(), metadata()) ::
          {:ok, :created | :exists, metadata()}
  def save(server, hash, metadata) when is_binary(hash) and is_map(metadata) do
    GenServer.call(server, {:save, hash, metadata})
  end

  @doc """
  Fetches the metadata stored under `id` (the content hash).

  Returns `{:ok, metadata}` or `{:error, :not_found}`.
  """
  @spec get(GenServer.server(), hash()) :: {:ok, metadata()} | {:error, :not_found}
  def get(server, id) when is_binary(id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Returns every stored metadata record as a list.
  """
  @spec list(GenServer.server()) :: [metadata()]
  def list(server) do
    GenServer.call(server, :list)
  end

  # --- Server callbacks ---------------------------------------------------

  @impl GenServer
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:save, hash, metadata}, _from, state) do
    case Map.fetch(state, hash) do
      {:ok, existing} ->
        record = Map.update(existing, :upload_count, 1, &(&1 + 1))
        {:reply, {:ok, :exists, record}, Map.put(state, hash, record)}

      :error ->
        record =
          metadata
          |> Map.put(:id, hash)
          |> Map.put(:uploaded_at, timestamp())
          |> Map.put(:upload_count, 1)

        {:reply, {:ok, :created, record}, Map.put(state, hash, record)}
    end
  end

  @impl GenServer
  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state, id) do
      {:ok, metadata} -> {:reply, {:ok, metadata}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state), state}
  end

  @spec timestamp() :: String.t()
  defp timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  A `Plug.Router` exposing a content-addressable, deduplicating upload endpoint
  at `POST /api/uploads`.

  A file's identity is the SHA-256 hash of its bytes, so uploading the same
  content twice never produces a second record or a second file on disk: the
  duplicate request is answered with `200` and the existing metadata, with
  `deduplicated` set to `true` and `upload_count` incremented. A brand new hash
  is answered with `201`, `deduplicated: false` and `upload_count: 1`, and the
  bytes are written to `<upload_dir>/<hash><ext>`.

  Requests larger than 5MB are rejected with `413`; anything the
  `FileUpload.Validator` rejects yields `422`.

  ## Options

    * `:store` — PID or registered name of the `FileUpload.Store` GenServer.
    * `:upload_dir` — directory in which files are stored on disk.
    * `:base_url` — URL prefix used to build the `download_url`.

  ## Usage

      plug FileUpload.Router,
        store: FileUpload.Store,
        upload_dir: "priv/uploads",
        base_url: "http://localhost:4000"

  """

  use Plug.Router

  @max_bytes 5_242_880

  plug :match

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: @max_bytes,
    json_decoder: Jason

  plug :dispatch, builder_opts()

  @doc """
  Returns the maximum accepted upload size, in bytes.
  """
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  post "/api/uploads" do
    handle_upload(conn, opts)
  end

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  @doc """
  Converts errors raised by the plug pipeline into JSON responses.

  A `Plug.Parsers.RequestTooLargeError` (raised when the body exceeds
  #{@max_bytes} bytes) becomes a `413` with the maximum size, everything else a
  generic `500`.
  """
  @spec handle_errors(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handle_errors(conn, %{reason: reason}) do
    case reason do
      %Plug.Parsers.RequestTooLargeError{} ->
        send_json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})

      _other ->
        send_json(conn, 500, %{error: "Internal server error"})
    end
  end

  use Plug.ErrorHandler

  # --- Upload pipeline ----------------------------------------------------

  @spec handle_upload(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  defp handle_upload(conn, opts) do
    case fetch_upload(conn) do
      {:ok, upload} -> process_upload(conn, upload, opts)
      {:error, :missing} -> send_json(conn, 422, %{error: "No file provided"})
    end
  end

  @spec fetch_upload(Plug.Conn.t()) :: {:ok, Plug.Upload.t()} | {:error, :missing}
  defp fetch_upload(%Plug.Conn{body_params: params}) when is_map(params) do
    case Map.get(params, "file") do
      %Plug.Upload{} = upload -> {:ok, upload}
      _other -> {:error, :missing}
    end
  end

  defp fetch_upload(_conn), do: {:error, :missing}

  @spec process_upload(Plug.Conn.t(), Plug.Upload.t(), keyword()) :: Plug.Conn.t()
  defp process_upload(conn, upload, opts) do
    with :ok <- validate_size(upload),
         :ok <- FileUpload.Validator.validate(upload),
         {:ok, contents} <- read_upload(upload) do
      store_upload(conn, upload, contents, opts)
    else
      {:error, :too_large} ->
        send_json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})

      {:error, reason} when is_binary(reason) ->
        send_json(conn, 422, %{error: reason})
    end
  end

  @spec validate_size(Plug.Upload.t()) :: :ok | {:error, :too_large}
  defp validate_size(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when size > @max_bytes -> {:error, :too_large}
      _other -> :ok
    end
  end

  @spec read_upload(Plug.Upload.t()) :: {:ok, binary()} | {:error, String.t()}
  defp read_upload(%Plug.Upload{path: path}) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, posix} -> {:error, "Could not read uploaded file: #{:file.format_error(posix)}"}
    end
  end

  @spec store_upload(Plug.Conn.t(), Plug.Upload.t(), binary(), keyword()) :: Plug.Conn.t()
  defp store_upload(conn, upload, contents, opts) do
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    hash = sha256_hex(contents)

    metadata = %{
      original_name: upload.filename,
      size: byte_size(contents),
      content_type: upload.content_type || "application/octet-stream"
    }

    {:ok, status, record} = FileUpload.Store.save(store, hash, metadata)

    case status do
      :created ->
        case write_to_disk(upload_dir, hash, upload.filename, contents) do
          :ok ->
            send_json(conn, 201, render(record, base_url, false))

          {:error, posix} ->
            send_json(conn, 500, %{error: "Could not store file: #{:file.format_error(posix)}"})
        end

      :exists ->
        send_json(conn, 200, render(record, base_url, true))
    end
  end

  @spec write_to_disk(Path.t(), String.t(), String.t(), binary()) :: :ok | {:error, atom()}
  defp write_to_disk(upload_dir, hash, filename, contents) do
    extension = filename |> Path.extname() |> String.downcase()
    destination = Path.join(upload_dir, hash <> extension)

    with :ok <- File.mkdir_p(upload_dir) do
      File.write(destination, contents)
    end
  end

  @spec sha256_hex(binary()) :: String.t()
  defp sha256_hex(contents) do
    :sha256
    |> :crypto.hash(contents)
    |> Base.encode16(case: :lower)
  end

  @spec render(FileUpload.Store.metadata(), String.t(), boolean()) :: map()
  defp render(record, base_url, deduplicated?) do
    %{
      id: record.id,
      original_name: record.original_name,
      size: record.size,
      content_type: record.content_type,
      uploaded_at: record.uploaded_at,
      upload_count: record.upload_count,
      deduplicated: deduplicated?,
      download_url: download_url(base_url, record.id)
    }
  end

  @spec download_url(String.t(), String.t()) :: String.t()
  defp download_url(base_url, id) do
    String.trim_trailing(base_url, "/") <> "/api/uploads/" <> id
  end

  @spec send_json(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end