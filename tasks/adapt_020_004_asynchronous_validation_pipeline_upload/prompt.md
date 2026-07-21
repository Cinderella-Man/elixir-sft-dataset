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

Write me an Elixir application composed of a few modules that implements an **asynchronous, status-polled** file upload endpoint with validation, using only `Plug` (no Phoenix). The main entry point is a `Plug.Router` module called `FileUpload.Router` that exposes `POST /api/uploads` and `GET /api/uploads/:id`.

The defining feature of this variation is a **deferred validation pipeline**: the upload is accepted and persisted to disk immediately, the response is HTTP 202 with a `pending` status, and validation runs asynchronously in a separate process. Clients poll the status endpoint to observe the file transition to `valid` or `invalid`. (Only structural failures the server can reject up-front — oversize files and a missing `"file"` field — are handled synchronously; content/type validation is deferred.)

Here's what I need:

**`FileUpload.Router`** — a `Plug.Router` that:

- **POST /api/uploads**: accepts a single file upload under the form field name `"file"`.
  - Enforces a maximum file size of 5MB (`5_242_880` bytes) → HTTP 413 `{"error": "File too large", "max_bytes": 5242880}` (synchronous, before acceptance).
  - If the `"file"` field is missing → HTTP 422 `{"error": "No file provided"}`.
  - Otherwise: create a `pending` record in `FileUpload.Store` (getting a UUID v4 `id`), copy the file to disk as `<id><ext>`, spawn an asynchronous task that validates the persisted file and updates the record's status, and return HTTP **202 Accepted** with `{"id", "original_name", "size", "content_type", "status": "pending", "uploaded_at", "status_url"}` where `status_url` is `"<base_url>/api/uploads/<id>"`.
  - The asynchronous task calls `FileUpload.Validator` on the persisted file. On `:ok` it sets the status to `valid` and stores a `download_url` of `"<base_url>/api/uploads/<id>/download"`. On `{:error, reason}` it sets the status to `invalid` and stores the `reason`.
- **GET /api/uploads/:id**: returns HTTP 200 with the current record as JSON: always `{"id", "original_name", "size", "content_type", "uploaded_at", "status"}` where `status` is one of `"pending"`, `"valid"`, `"invalid"`. When `valid`, also include `"download_url"`. When `invalid`, also include `"error"`. If the id is unknown, HTTP 404 `{"error": "Not found"}`.

The router accepts these options via `plug FileUpload.Router, opts`:
- `:store` — the PID or name of the `FileUpload.Store` GenServer.
- `:upload_dir` — the directory where files are saved.
- `:base_url` — the URL prefix used to build `status_url` and `download_url`.

**`FileUpload.Validator`** — `validate(upload)` on a `%Plug.Upload{}`, returning `:ok` or `{:error, reason}`:
  1. Only `.csv`/`.json` (case-insensitive) → else `{:error, "File type not allowed. Only .csv and .json files are accepted"}`.
  2. CSV: at least two lines OR one comma-containing line, else `{:error, "Invalid CSV: file must contain a header row with multiple columns"}`.
  3. JSON: must `Jason.decode`, else `{:error, "Invalid JSON: " <> description}`.

**`FileUpload.Store`** — a GenServer holding upload records and their status:

- `start_link(opts)` accepts a `:name` option.
- `create(server, metadata)` generates a UUID v4 `:id`, adds `:uploaded_at` (ISO 8601 UTC) and `:status` of `:pending`, stores and returns `{:ok, record}`.
- `update_status(server, id, status, extra)` merges `extra` (a map) into the record and sets its `:status`; returns `:ok`. For an unknown `id` it returns `{:error, :not_found}` — it must not crash and must not report `:ok`.
- `get(server, id)` → `{:ok, record}` | `{:error, :not_found}`.
- `list(server)` → all records.

Use `Jason` for JSON, `:crypto` for the UUID, and a plain process (`Task.start`) for the async validation so the request returns immediately. Only standard OTP plus `Plug` and `Jason`. One file, three modules, each with a `@moduledoc`.
