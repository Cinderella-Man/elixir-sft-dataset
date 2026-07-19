# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `json` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir application composed of a few modules that implements a **content-addressable, deduplicating** file upload endpoint with validation, using only `Plug` (no Phoenix). The main entry point is a `Plug.Router` module called `FileUpload.Router` that exposes `POST /api/uploads`.

The defining feature of this variation is **content-addressable storage with deduplication**: a file's identity is the SHA-256 hash of its bytes. Uploading the same content twice (even under different filenames) must NOT create a second stored record or a second file on disk — the second request is recognized as a duplicate and returns the existing metadata.

Here's what I need:

**`FileUpload.Router`** — a `Plug.Router` that:

- Accepts a single file upload under the form field name `"file"`.
- Enforces a maximum file size of 5MB (`5_242_880` bytes). If a request exceeds this, return HTTP 413 with JSON body `{"error": "File too large", "max_bytes": 5242880}`.
- Delegates validation to `FileUpload.Validator` and storage to `FileUpload.Store`.
- Computes the SHA-256 hash of the file's contents (lowercase hex, 64 chars) and uses it as the file `id`.
- On a **new** upload (hash not seen before), returns HTTP 201 with JSON metadata: `{"id", "original_name", "size", "content_type", "uploaded_at", "upload_count", "deduplicated", "download_url"}` where `deduplicated` is `false` and `upload_count` is `1`. The file is written to disk once, named `<hash><ext>`.
- On a **duplicate** upload (hash already stored), returns HTTP 200 with the SAME metadata, `deduplicated` set to `true`, and `upload_count` incremented. NO new disk file is written.
- On validation failure, returns HTTP 422 with JSON body `{"error": "<descriptive message>"}`.
- If the `"file"` field is missing, return HTTP 422 with `{"error": "No file provided"}`.

The router must accept these options at init time via `plug FileUpload.Router, opts`:
- `:store` — the PID or name of the `FileUpload.Store` GenServer.
- `:upload_dir` — the directory path where files are saved to disk.
- `:base_url` — the URL prefix for generating download URLs (e.g. `"http://localhost:4000"`). The download URL is `"<base_url>/api/uploads/<hash>"`.

**`FileUpload.Validator`** — a module with a single public function `validate(upload)` where `upload` is a `%Plug.Upload{}` struct. It returns `:ok` or `{:error, reason_string}`:
  1. **File type**: only `.csv` and `.json` extensions are allowed (check the `filename` field, case-insensitive). If not, return `{:error, "File type not allowed. Only .csv and .json files are accepted"}`.
  2. **Content validity for CSV**: read the file, and confirm it has at least two lines OR at least one line containing a comma. Otherwise return `{:error, "Invalid CSV: file must contain a header row with multiple columns"}`.
  3. **Content validity for JSON**: read the file and attempt `Jason.decode`. If it fails, return `{:error, "Invalid JSON: " <> description}`.

**`FileUpload.Store`** — a GenServer keyed by content hash:

- `start_link(opts)` accepts a `:name` option for process registration.
- `save(server, hash, metadata)` stores metadata under `hash`. If the hash is new, it adds `:id` (= hash), an `:uploaded_at` ISO 8601 UTC timestamp, and `:upload_count` of `1`, returning `{:ok, :created, record}`. If the hash already exists, it increments `:upload_count` and returns `{:ok, :exists, record}` (preserving the original `:id`, `:original_name`, and `:uploaded_at`).
- `get(server, id)` returns `{:ok, metadata}` or `{:error, :not_found}`.
- `list(server)` returns all stored metadata as a list.

Use `Jason` for JSON, `:crypto`/`Base` for hashing. Only standard OTP plus `Plug` and `Jason`. Keep everything in a single file, clearly separated into the three modules, each with a `@moduledoc`.

## The module with `json` missing

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

  defp json(conn, status, data) do
    # TODO
  end
end
```

Give me only the complete implementation of `json` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
