Implement the `handle_call/3` GenServer callbacks for `FileUpload.Store`. This one
function (three clauses, matching `{:save, hash, metadata}`, `{:get, id}`, and
`:list`) drives the content-addressable, deduplicating store. Each clause receives
the `from` reference (unused) and the current `state`, a map of the form
`%{files: %{}}` where `files` maps a content hash to its metadata record. Every
clause must return a `{:reply, reply, state}` tuple.

- **`{:save, hash, metadata}`** — look up `hash` in `state.files`.
  - If a record already exists for that hash (a duplicate upload), increment its
    `:upload_count` by 1, write the updated record back into `state.files` under
    `hash`, and reply with `{:ok, :exists, updated_record}`. All other fields of the
    existing record (including `:id`, `:original_name`, and `:uploaded_at`) must be
    preserved unchanged.
  - If the hash is new, build a fresh record from `metadata` by adding `:id` (equal
    to `hash`), `:uploaded_at` (the current UTC time as an ISO 8601 string), and
    `:upload_count` of `1`. Store it under `hash` and reply with
    `{:ok, :created, record}`.

- **`{:get, id}`** — look up `id` in `state.files`. Reply with `{:ok, record}` if
  found, or `{:error, :not_found}` otherwise. The state is unchanged.

- **`:list`** — reply with all stored metadata records as a list (the values of
  `state.files`). The state is unchanged.

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
  def handle_call({:save, hash, metadata}, _from, state) do
    # TODO
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