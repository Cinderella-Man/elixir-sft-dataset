# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `create` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `create` missing

```elixir
defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` holding upload records through an asynchronous validation
  lifecycle. Records are created in the `:pending` status and later transitioned
  to `:valid` or `:invalid` by an out-of-band task via `update_status/4`.
  """

  use GenServer

  @doc """
  Starts the store `GenServer`. Accepts a `:name` option used to register the
  process. Returns the standard `GenServer.on_start/0` result.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def create(server, metadata) do
    # TODO
  end

  @doc """
  Merges `extra` into the record and sets its `:status`. Returns `:ok` or
  `{:error, :not_found}`.
  """
  @spec update_status(GenServer.server(), String.t(), atom(), map()) ::
          :ok | {:error, :not_found}
  def update_status(server, id, status, extra),
    do: GenServer.call(server, {:update_status, id, status, extra})

  @doc """
  Fetches a record by `id`. Returns `{:ok, record}` or `{:error, :not_found}`.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(server, id), do: GenServer.call(server, {:get, id})

  @doc """
  Returns all records currently held by the store.
  """
  @spec list(GenServer.server()) :: [map()]
  def list(server), do: GenServer.call(server, :list)

  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts), do: {:ok, %{files: %{}}}

  @doc false
  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:create, metadata}, _from, state) do
    record =
      metadata
      |> Map.put(:id, uuid_v4())
      |> Map.put(:uploaded_at, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put(:status, :pending)

    {:reply, {:ok, record}, put_in(state.files[record.id], record)}
  end

  def handle_call({:update_status, id, status, extra}, _from, state) do
    case Map.fetch(state.files, id) do
      {:ok, record} ->
        updated = record |> Map.merge(extra) |> Map.put(:status, status)
        {:reply, :ok, put_in(state.files[id], updated)}

      :error ->
        {:reply, {:error, :not_found}, state}
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

  @doc """
  Validates the persisted upload. Returns `:ok` when the file type is allowed
  and its contents pass the per-type checks, otherwise `{:error, reason}`.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, String.t()}
  def validate(%Plug.Upload{filename: filename, path: path}) do
    case filename |> Path.extname() |> String.downcase() do
      ".csv" -> validate_csv(path)
      ".json" -> validate_json(path)
      _ -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

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

  defp validate_json(path) do
    case Jason.decode(File.read!(path)) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  `Plug.Router` exposing `POST /api/uploads` (accept-and-defer) and
  `GET /api/uploads/:id` (status poll). Uploads are persisted immediately and
  returned as `202 pending`; a spawned task validates the persisted file and
  transitions the record to `valid` or `invalid`.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  alias FileUpload.{Store, Validator}

  @max_bytes 5_242_880

  plug(:match)
  plug(:dispatch)

  post "/api/uploads" do
    opts = conn.assigns.router_opts

    case conn.params["file"] do
      %Plug.Upload{} = upload -> accept_upload(conn, upload, opts)
      _ -> json(conn, 422, %{error: "No file provided"})
    end
  end

  get "/api/uploads/:id" do
    opts = conn.assigns.router_opts
    store = Keyword.fetch!(opts, :store)

    case Store.get(store, id) do
      {:ok, record} -> json(conn, 200, status_body(record))
      {:error, :not_found} -> json(conn, 404, %{error: "Not found"})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp accept_upload(conn, upload, opts) do
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    size = File.stat!(upload.path).size

    cond do
      size > @max_bytes ->
        json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})

      true ->
        metadata = %{
          original_name: upload.filename,
          size: size,
          content_type: upload.content_type
        }

        {:ok, record} = Store.create(store, metadata)

        ext = Path.extname(upload.filename)
        dest = Path.join(upload_dir, record.id <> ext)
        File.cp!(upload.path, dest)

        spawn_validation(store, record, dest, base_url)

        response = %{
          id: record.id,
          original_name: record.original_name,
          size: record.size,
          content_type: record.content_type,
          status: "pending",
          uploaded_at: record.uploaded_at,
          status_url: "#{base_url}/api/uploads/#{record.id}"
        }

        json(conn, 202, response)
    end
  end

  defp spawn_validation(store, record, dest, base_url) do
    Task.start(fn ->
      persisted = %Plug.Upload{
        filename: record.original_name,
        path: dest,
        content_type: record.content_type
      }

      case Validator.validate(persisted) do
        :ok ->
          Store.update_status(store, record.id, :valid, %{
            download_url: "#{base_url}/api/uploads/#{record.id}/download"
          })

        {:error, reason} ->
          Store.update_status(store, record.id, :invalid, %{error: reason})
      end
    end)
  end

  defp status_body(record) do
    base = %{
      id: record.id,
      original_name: record.original_name,
      size: record.size,
      content_type: record.content_type,
      uploaded_at: record.uploaded_at,
      status: Atom.to_string(record.status)
    }

    case record.status do
      :valid -> Map.put(base, :download_url, Map.get(record, :download_url))
      :invalid -> Map.put(base, :error, Map.get(record, :error))
      _ -> base
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

Give me only the complete implementation of `create` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
