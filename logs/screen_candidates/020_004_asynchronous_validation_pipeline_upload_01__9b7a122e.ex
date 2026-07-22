defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that holds upload records and tracks their validation status.

  Each record is a map with at least the following keys:

    * `:id` — a UUID v4 string generated at creation time
    * `:uploaded_at` — an ISO 8601 UTC timestamp string
    * `:status` — one of `:pending`, `:valid` or `:invalid`

  Any additional metadata passed to `create/2` (for example `:original_name`,
  `:size` and `:content_type`) is merged into the record, and `update_status/4`
  can merge further data (such as a `:download_url` or an error `:reason`) as the
  asynchronous validation pipeline makes progress.

  The store is intentionally in-memory only: it is a small, dependency-free
  registry suitable for a single-node upload endpoint.
  """

  use GenServer

  @type id :: String.t()
  @type status :: :pending | :valid | :invalid
  @type record :: %{
          required(:id) => id(),
          required(:uploaded_at) => String.t(),
          required(:status) => status(),
          optional(atom()) => term()
        }

  @doc """
  Starts the store.

  Supports the usual `GenServer` options; in particular `:name` may be given so
  that the store can be referenced by name rather than by pid.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Creates a new record from `metadata`.

  A UUID v4 `:id`, an ISO 8601 UTC `:uploaded_at` timestamp and a `:pending`
  `:status` are added automatically. Returns `{:ok, record}`.
  """
  @spec create(GenServer.server(), map()) :: {:ok, record()}
  def create(server, metadata) when is_map(metadata) do
    GenServer.call(server, {:create, metadata})
  end

  @doc """
  Merges `extra` into the record identified by `id` and sets its `:status`.

  Returns `:ok` when the record exists, `{:error, :not_found}` otherwise.
  """
  @spec update_status(GenServer.server(), id(), status(), map()) :: :ok | {:error, :not_found}
  def update_status(server, id, status, extra \\ %{}) when is_map(extra) do
    GenServer.call(server, {:update_status, id, status, extra})
  end

  @doc """
  Fetches the record identified by `id`.
  """
  @spec get(GenServer.server(), id()) :: {:ok, record()} | {:error, :not_found}
  def get(server, id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Returns every record currently held by the store.
  """
  @spec list(GenServer.server()) :: [record()]
  def list(server) do
    GenServer.call(server, :list)
  end

  @doc """
  Generates a random UUID v4 string using `:crypto`.
  """
  @spec generate_uuid() :: String.t()
  def generate_uuid do
    <<a::32, b::16, _::4, c::12, _::2, d::30, e::32>> = :crypto.strong_rand_bytes(16)

    [
      encode_hex(a, 8),
      encode_hex(b, 4),
      encode_hex(0x4000 ||| c, 4),
      encode_hex(0x8000 ||| Bitwise.bsr(d, 16), 4),
      encode_hex(Bitwise.band(d, 0xFFFF), 4) <> encode_hex(e, 8)
    ]
    |> Enum.join("-")
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:create, metadata}, _from, records) do
    record =
      metadata
      |> Map.put(:id, generate_uuid())
      |> Map.put(:uploaded_at, timestamp())
      |> Map.put(:status, :pending)

    {:reply, {:ok, record}, Map.put(records, record.id, record)}
  end

  def handle_call({:update_status, id, status, extra}, _from, records) do
    case Map.fetch(records, id) do
      {:ok, record} ->
        updated =
          record
          |> Map.merge(extra)
          |> Map.put(:status, status)

        {:reply, :ok, Map.put(records, id, updated)}

      :error ->
        {:reply, {:error, :not_found}, records}
    end
  end

  def handle_call({:get, id}, _from, records) do
    case Map.fetch(records, id) do
      {:ok, record} -> {:reply, {:ok, record}, records}
      :error -> {:reply, {:error, :not_found}, records}
    end
  end

  def handle_call(:list, _from, records) do
    {:reply, Map.values(records), records}
  end

  import Bitwise, only: [|||: 2]

  defp encode_hex(value, width) do
    value
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(width, "0")
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end

defmodule FileUpload.Validator do
  @moduledoc """
  Content validation for uploaded files.

  Validation is deliberately decoupled from the HTTP request cycle: the router
  persists the upload first and then runs this module asynchronously, so a slow
  or expensive check never blocks the client.

  Three rules are applied, in order:

    1. the extension must be `.csv` or `.json` (case-insensitive);
    2. a `.csv` file must look like it has a header row — either at least two
       lines, or a single line containing a comma;
    3. a `.json` file must be decodable by `Jason`.
  """

  @allowed_extensions ~w(.csv .json)

  @type reason :: String.t()

  @doc """
  Validates the file referenced by a `%Plug.Upload{}`.

  The `:path` of the upload (or, when the upload has already been persisted, the
  path it was copied to) is read from disk. Returns `:ok` when the file passes
  every rule, `{:error, reason}` with a human-readable reason otherwise.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, reason()}
  def validate(%Plug.Upload{} = upload) do
    extension =
      upload.filename
      |> to_string()
      |> Path.extname()
      |> String.downcase()

    if extension in @allowed_extensions do
      validate_content(extension, upload.path)
    else
      {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

  defp validate_content(extension, path) do
    case File.read(path) do
      {:ok, contents} -> validate_contents(extension, contents)
      {:error, posix} -> {:error, "Could not read file: #{:file.format_error(posix)}"}
    end
  end

  defp validate_contents(".csv", contents) do
    lines =
      contents
      |> String.split(~r/\r\n|\r|\n/, trim: true)
      |> Enum.reject(&(String.trim(&1) == ""))

    cond do
      length(lines) >= 2 -> :ok
      match?([single] when is_binary(single), lines) and String.contains?(hd(lines), ",") -> :ok
      true -> {:error, "Invalid CSV: file must contain a header row with multiple columns"}
    end
  end

  defp validate_contents(".json", contents) do
    case Jason.decode(contents) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  A `Plug.Router` exposing an asynchronous, status-polled file upload endpoint.

  ## Endpoints

    * `POST /api/uploads` — accepts a multipart upload under the form field
      `"file"`. Structural problems are rejected synchronously: a file larger
      than 5 MB yields `413`, a missing field yields `422`. Otherwise the upload
      is recorded as `pending`, copied into `:upload_dir` as `<id><ext>`, and a
      `Task` is spawned to validate it. The response is `202 Accepted` and
      carries a `status_url` the client can poll.

    * `GET /api/uploads/:id` — returns the current record. While validation is in
      flight the status is `"pending"`; afterwards it becomes `"valid"` (with a
      `"download_url"`) or `"invalid"` (with an `"error"`). Unknown ids yield
      `404`.

  ## Options

    * `:store` — pid or name of the `FileUpload.Store` `GenServer`
    * `:upload_dir` — directory the persisted files are written to
    * `:base_url` — URL prefix used to build `status_url` and `download_url`
  """

  use Plug.Router

  @max_bytes 5_242_880

  plug :match

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason,
    length: 20_000_000

  plug :dispatch, builder_opts()

  @doc """
  Returns the maximum accepted upload size, in bytes.
  """
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  post "/api/uploads" do
    case conn.params["file"] do
      %Plug.Upload{} = upload ->
        handle_upload(conn, upload, opts)

      _other ->
        send_json(conn, 422, %{error: "No file provided"})
    end
  end

  get "/api/uploads/:id" do
    store = fetch_option(opts, :store)

    case FileUpload.Store.get(store, id) do
      {:ok, record} -> send_json(conn, 200, render(record))
      {:error, :not_found} -> send_json(conn, 404, %{error: "Not found"})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  defp handle_upload(conn, %Plug.Upload{} = upload, opts) do
    size = file_size(upload.path)

    if size > @max_bytes do
      send_json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})
    else
      accept_upload(conn, upload, size, opts)
    end
  end

  defp accept_upload(conn, %Plug.Upload{} = upload, size, opts) do
    store = fetch_option(opts, :store)
    upload_dir = fetch_option(opts, :upload_dir)
    base_url = fetch_option(opts, :base_url)

    metadata = %{
      original_name: upload.filename,
      size: size,
      content_type: upload.content_type
    }

    {:ok, record} = FileUpload.Store.create(store, metadata)

    extension =
      upload.filename
      |> to_string()
      |> Path.extname()

    destination = Path.join(upload_dir, record.id <> extension)

    File.mkdir_p!(upload_dir)
    File.cp!(upload.path, destination)

    persisted = %Plug.Upload{upload | path: destination}
    start_validation(store, record.id, persisted, base_url)

    body =
      record
      |> render()
      |> Map.put("status_url", status_url(base_url, record.id))

    send_json(conn, 202, body)
  end

  defp start_validation(store, id, %Plug.Upload{} = upload, base_url) do
    Task.start(fn ->
      case FileUpload.Validator.validate(upload) do
        :ok ->
          extra = %{download_url: download_url(base_url, id)}
          FileUpload.Store.update_status(store, id, :valid, extra)

        {:error, reason} ->
          FileUpload.Store.update_status(store, id, :invalid, %{reason: reason})
      end
    end)

    :ok
  end

  defp render(record) do
    base = %{
      "id" => record.id,
      "original_name" => Map.get(record, :original_name),
      "size" => Map.get(record, :size),
      "content_type" => Map.get(record, :content_type),
      "uploaded_at" => record.uploaded_at,
      "status" => Atom.to_string(record.status)
    }

    case record.status do
      :valid -> Map.put(base, "download_url", Map.get(record, :download_url))
      :invalid -> Map.put(base, "error", Map.get(record, :reason))
      _pending -> base
    end
  end

  defp status_url(base_url, id), do: "#{trim_slash(base_url)}/api/uploads/#{id}"

  defp download_url(base_url, id), do: "#{trim_slash(base_url)}/api/uploads/#{id}/download"

  defp trim_slash(base_url), do: String.trim_trailing(to_string(base_url), "/")

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _reason} -> 0
    end
  end

  defp fetch_option(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp fetch_option(opts, key) when is_map(opts), do: Map.get(opts, key)

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end