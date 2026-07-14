# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that stores uploaded-file metadata in memory, keyed by a
  generated UUID v4, and stamps each record with an ISO 8601 UTC timestamp.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
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
  `Plug.Router` exposing `POST /api/uploads`. Parses the multipart upload with
  `Plug.Parsers` under a 5MB request-body limit (returning 413 when exceeded),
  delegates validation to `FileUpload.Validator` and storage to
  `FileUpload.Store`, and persists the file to disk under its generated UUID.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  alias FileUpload.{Store, Validator}

  @max_bytes 5_242_880

  # Multipart parser bound to the 5MB limit. `Plug.Parsers` raises
  # `Plug.Parsers.RequestTooLargeError` (plug_status 413) once the request body
  # exceeds `:length`, which the route rescues into a clean 413 response.
  @multipart_parser Plug.Parsers.init(
                      parsers: [:multipart],
                      length: @max_bytes,
                      pass: ["*/*"]
                    )

  plug(:match)
  plug(:dispatch)

  post "/api/uploads" do
    opts = conn.assigns.router_opts

    try do
      parsed = Plug.Parsers.call(conn, @multipart_parser)

      case parsed.params["file"] do
        %Plug.Upload{} = upload ->
          handle_upload(parsed, upload, opts)

        _ ->
          json(parsed, 422, %{error: "No file provided"})
      end
    rescue
      Plug.Parsers.RequestTooLargeError ->
        json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp handle_upload(conn, upload, opts) do
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    case Validator.validate(upload) do
      :ok ->
        size = File.stat!(upload.path).size
        store_and_persist(conn, upload, size, store, upload_dir, base_url)

      {:error, reason} ->
        json(conn, 422, %{error: reason})
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
```

## New specification

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
