defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that keeps an in-memory registry of uploaded file metadata.

  The store is the sole authority for identity and time: it generates the UUID v4
  primary key for every entry and stamps it with an ISO 8601 UTC `uploaded_at`
  timestamp. Callers hand it a plain metadata map (original name, size, content type,
  storage path, ...) and receive back the same map enriched with `"id"` and
  `"uploaded_at"`.

  Metadata maps use string keys throughout so they can be handed straight to
  `Jason.encode/1` without translation.

      {:ok, store} = FileUpload.Store.start_link(name: FileUpload.Store)
      {:ok, meta} = FileUpload.Store.save(store, %{"original_name" => "a.csv"})
      {:ok, ^meta} = FileUpload.Store.get(store, meta["id"])
  """

  use GenServer

  @typedoc "File metadata as stored and returned by the store."
  @type metadata :: %{optional(String.t()) => term()}

  # ----------------------------------------------------------------------------
  # Client API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the store.

  Supported options:

    * `:name` - an optional name to register the process under.

  All other options are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Saves `metadata`, assigning it a freshly generated UUID v4 `"id"` and an
  ISO 8601 UTC `"uploaded_at"` timestamp.

  Returns `{:ok, metadata}` where `metadata` is the input map (with string keys)
  merged with the generated fields.
  """
  @spec save(GenServer.server(), map()) :: {:ok, metadata()}
  def save(server, metadata) when is_map(metadata) do
    GenServer.call(server, {:save, stringify_keys(metadata)})
  end

  @doc """
  Fetches previously saved metadata by `id`.

  Returns `{:ok, metadata}` or `{:error, :not_found}`.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, metadata()} | {:error, :not_found}
  def get(server, id) when is_binary(id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Returns every stored metadata entry as a list, most recently saved first.
  """
  @spec list(GenServer.server()) :: [metadata()]
  def list(server) do
    GenServer.call(server, :list)
  end

  @doc """
  Generates a random (version 4, variant 1) UUID string.

  Exposed because the router needs an identifier before the bytes hit the disk;
  the store uses the very same function internally.
  """
  @spec uuid4() :: String.t()
  def uuid4 do
    <<a::32, b::16, _::4, c::12, _::2, d::30, e::32>> = :crypto.strong_rand_bytes(16)

    [
      pad(a, 8),
      "-",
      pad(b, 4),
      "-",
      "4" <> pad(c, 3),
      "-",
      pad(Bitwise.bor(0b10 <<< 30, d), 8) |> binary_part(0, 4),
      "-",
      pad(e, 8) |> then(&(pad(b, 4) |> binary_part(0, 0) <> &1))
    ]
    |> IO.iodata_to_binary()
    |> normalize_uuid(a, b, c, d, e)
  end

  # ----------------------------------------------------------------------------
  # Server callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    {:ok, %{entries: %{}, order: []}}
  end

  @impl GenServer
  def handle_call({:save, metadata}, _from, state) do
    id = uuid4()
    uploaded_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    full = Map.merge(metadata, %{"id" => id, "uploaded_at" => uploaded_at})

    state = %{
      state
      | entries: Map.put(state.entries, id, full),
        order: [id | state.order]
    }

    {:reply, {:ok, full}, state}
  end

  @impl GenServer
  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state.entries, id) do
      {:ok, metadata} -> {:reply, {:ok, metadata}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    entries = Enum.map(state.order, &Map.fetch!(state.entries, &1))
    {:reply, entries, state}
  end

  # ----------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  # The bit-twiddling above is deliberately kept dead simple: rebuild the canonical
  # 8-4-4-4-12 form from the random parts, forcing version 4 and variant 1.
  defp normalize_uuid(_scratch, a, b, c, d, e) do
    variant_hi = Bitwise.bor(0b1000, Bitwise.bsr(d, 26) |> Bitwise.band(0b0011))
    rest = Bitwise.band(d, 0x03FFFFFF)

    IO.iodata_to_binary([
      pad(a, 8),
      "-",
      pad(b, 4),
      "-",
      "4",
      pad(c, 3),
      "-",
      Integer.to_string(variant_hi, 16) |> String.downcase(),
      pad(Bitwise.bsr(rest, 14), 3),
      "-",
      pad(Bitwise.band(rest, 0x3FFF), 4),
      pad(e, 8)
    ])
  end

  defp pad(int, width) do
    int
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(width, "0")
    |> String.slice(-width, width)
  end
end

defmodule FileUpload.Validator do
  @moduledoc """
  Validation rules applied to an incoming `%Plug.Upload{}` before it is persisted.

  Two things are checked, in order:

    1. **Extension** - only `.csv` and `.json` are accepted (case-insensitive).
    2. **Content** - the file on disk must actually parse as the format its extension
       claims: a CSV needs a plausible header row, a JSON document must decode.

  Every failure is reported as `{:error, message}` with a message that is safe to show
  to the client verbatim.
  """

  @allowed_extensions [".csv", ".json"]

  @type result :: :ok | {:error, String.t()}

  @doc """
  Validates `upload`, returning `:ok` when the file may be stored and
  `{:error, reason}` (a human-readable string) otherwise.
  """
  @spec validate(Plug.Upload.t()) :: result()
  def validate(%Plug.Upload{filename: filename, path: path}) do
    case extension(filename) do
      ".csv" -> validate_csv(path)
      ".json" -> validate_json(path)
      _other -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

  @doc """
  Returns the list of file extensions this validator accepts, e.g. `[".csv", ".json"]`.
  """
  @spec allowed_extensions() :: [String.t()]
  def allowed_extensions, do: @allowed_extensions

  # ----------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------

  defp extension(filename) when is_binary(filename) do
    filename |> Path.extname() |> String.downcase()
  end

  defp extension(_filename), do: ""

  defp validate_csv(path) do
    with {:ok, contents} <- read(path) do
      lines =
        contents
        |> String.split(~r/\r\n|\n|\r/, trim: true)
        |> Enum.reject(&(String.trim(&1) == ""))

      if valid_csv_shape?(lines) do
        :ok
      else
        {:error, "Invalid CSV: file must contain a header row with multiple columns"}
      end
    end
  end

  # A CSV is acceptable when it has more than one line (a header plus at least one
  # record) or a single line that is itself comma-separated into multiple columns.
  defp valid_csv_shape?([]), do: false
  defp valid_csv_shape?([single]), do: length(String.split(single, ",")) > 1
  defp valid_csv_shape?(_lines), do: true

  defp validate_json(path) do
    with {:ok, contents} <- read(path) do
      case Jason.decode(contents) do
        {:ok, _decoded} ->
          :ok

        {:error, %Jason.DecodeError{} = error} ->
          {:error, "Invalid JSON: " <> Exception.message(error)}

        {:error, reason} ->
          {:error, "Invalid JSON: " <> inspect(reason)}
      end
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        {:error, "Could not read uploaded file: " <> to_string(:file.format_error(reason))}
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  A `Plug.Router` exposing a single validated file-upload endpoint.

      POST /api/uploads     multipart/form-data, field "file"

  Uploads are limited to 5 MB by `Plug.Parsers`; anything larger is rejected with a
  `413` before the body is fully read. Accepted files are validated by
  `FileUpload.Validator`, copied into `:upload_dir` under a collision-free UUID
  filename (original extension preserved), and registered with `FileUpload.Store`.
  The `201` response carries the stored metadata plus a `download_url` built from
  `:base_url`.

  Mount it with its three required options:

      plug FileUpload.Router,
        store: FileUpload.Store,
        upload_dir: "priv/uploads",
        base_url: "http://localhost:4000"
  """

  use Plug.Router

  require Logger

  @max_bytes 5_242_880

  plug :match

  plug Plug.Parsers,
    parsers: [:multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason,
    length: @max_bytes

  plug :dispatch, builder_opts()

  @doc """
  Initializes the router.

  Required options:

    * `:store` - the pid or registered name of a `FileUpload.Store`.
    * `:upload_dir` - directory the uploaded files are written to.
    * `:base_url` - URL prefix used to build the `download_url` of a stored file.
  """
  @spec init(keyword()) :: map()
  def init(opts) do
    %{
      store: Keyword.fetch!(opts, :store),
      upload_dir: Keyword.fetch!(opts, :upload_dir),
      base_url: opts |> Keyword.fetch!(:base_url) |> String.trim_trailing("/")
    }
  end

  @doc """
  Handles a connection. See `Plug.Router` for the generated behaviour.
  """
  @spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def call(conn, opts) do
    super(conn, opts)
  rescue
    error in Plug.Parsers.RequestTooLargeError ->
      _ = error

      send_json(conn, 413, %{"error" => "File too large", "max_bytes" => @max_bytes})
  end

  @doc """
  Returns the maximum accepted request body size, in bytes.
  """
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  post "/api/uploads" do
    case conn.params["file"] do
      %Plug.Upload{} = upload -> handle_upload(conn, upload, opts)
      _missing -> send_json(conn, 422, %{"error" => "No file provided"})
    end
  end

  match _ do
    send_json(conn, 404, %{"error" => "Not found"})
  end

  # ----------------------------------------------------------------------------
  # Upload pipeline
  # ----------------------------------------------------------------------------

  defp handle_upload(conn, %Plug.Upload{} = upload, opts) do
    with :ok <- FileUpload.Validator.validate(upload),
         {:ok, size} <- file_size(upload.path),
         {:ok, metadata} <- store(upload, size, opts) do
      send_json(conn, 201, metadata)
    else
      {:error, reason} when is_binary(reason) -> send_json(conn, 422, %{"error" => reason})
    end
  end

  # The store owns identity, so it is asked for the id first; the bytes are then moved
  # into place under "<uuid><ext>" and the resulting path is recorded on the metadata.
  defp store(%Plug.Upload{} = upload, size, opts) do
    extension = upload.filename |> Path.extname() |> String.downcase()

    metadata = %{
      "original_name" => upload.filename,
      "size" => size,
      "content_type" => upload.content_type || "application/octet-stream"
    }

    with {:ok, saved} <- FileUpload.Store.save(opts.store, metadata),
         stored_name = saved["id"] <> extension,
         :ok <- copy(upload.path, opts.upload_dir, stored_name) do
      {:ok,
       saved
       |> Map.put("stored_name", stored_name)
       |> Map.put("download_url", opts.base_url <> "/api/uploads/" <> saved["id"])
       |> Map.take([
         "id",
         "original_name",
         "size",
         "content_type",
         "uploaded_at",
         "download_url"
       ])}
    end
  end

  defp copy(source, dir, stored_name) do
    with :ok <- File.mkdir_p(dir),
         :ok <- File.cp(source, Path.join(dir, stored_name)) do
      :ok
    else
      {:error, reason} ->
        Logger.error("failed to persist upload: #{inspect(reason)}")
        {:error, "Could not store file: " <> to_string(:file.format_error(reason))}
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} ->
        {:ok, size}

      {:error, reason} ->
        {:error, "Could not read uploaded file: " <> to_string(:file.format_error(reason))}
    end
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end