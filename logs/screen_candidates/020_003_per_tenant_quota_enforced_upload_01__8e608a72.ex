defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that tracks per-account byte usage and stored file metadata.

  Each account has a fixed total-bytes budget (`:quota_bytes`). Saving a file
  is atomic and all-or-nothing: a save that would push an account over its
  budget is rejected without consuming any quota or storing any metadata.
  Deleting a file releases its bytes back to the owning account's budget.
  """

  use GenServer

  @type server :: GenServer.server()
  @type account :: String.t()
  @type metadata :: map()

  @default_quota 10_000_000

  @doc """
  Starts the store.

  Accepts `:name` (registration name) and `:quota_bytes` (the per-account
  budget, defaulting to `#{@default_quota}`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    quota = Keyword.get(opts, :quota_bytes, @default_quota)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{quota: quota}, server_opts)
  end

  @doc """
  Atomically reserves quota for `account` and stores `metadata`.

  Returns `{:ok, record, %{quota: q, used: new_used}}` on success, where the
  record is enriched with `:id`, `:uploaded_at` and `:account`. Returns
  `{:error, :quota_exceeded, %{quota: q, used: used, requested: size}}` (with
  no state change) when the account's budget would be exceeded.
  """
  @spec save(server(), account(), metadata()) ::
          {:ok, metadata(), map()} | {:error, :quota_exceeded, map()}
  def save(server, account, metadata) do
    GenServer.call(server, {:save, account, metadata})
  end

  @doc """
  Deletes the file `id` on behalf of `account`, releasing its reserved bytes.

  Returns `{:ok, %{record: record, freed: size, used: new_used}}` on success,
  `{:error, :forbidden}` if `id` belongs to another account, or
  `{:error, :not_found}` when unknown.
  """
  @spec delete(server(), account(), String.t()) ::
          {:ok, map()} | {:error, :forbidden | :not_found}
  def delete(server, account, id) do
    GenServer.call(server, {:delete, account, id})
  end

  @doc """
  Fetches the stored metadata for `id`.
  """
  @spec get(server(), String.t()) :: {:ok, metadata()} | {:error, :not_found}
  def get(server, id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Returns the current used bytes for `account` (0 when unknown).
  """
  @spec usage(server(), account()) :: non_neg_integer()
  def usage(server, account) do
    GenServer.call(server, {:usage, account})
  end

  @doc """
  Returns all stored metadata records.
  """
  @spec list(server()) :: [metadata()]
  def list(server) do
    GenServer.call(server, :list)
  end

  @impl GenServer
  @spec init(map()) :: {:ok, map()}
  def init(state) do
    {:ok, Map.merge(%{usage: %{}, records: %{}}, state)}
  end

  @impl GenServer
  def handle_call({:save, account, metadata}, _from, state) do
    size = Map.get(metadata, :size, 0)
    used = Map.get(state.usage, account, 0)

    if used + size > state.quota do
      error = {:error, :quota_exceeded, %{quota: state.quota, used: used, requested: size}}
      {:reply, error, state}
    else
      id = uuid4()

      record =
        metadata
        |> Map.put(:id, id)
        |> Map.put(:uploaded_at, now_iso8601())
        |> Map.put(:account, account)

      new_used = used + size

      new_state = %{
        state
        | usage: Map.put(state.usage, account, new_used),
          records: Map.put(state.records, id, record)
      }

      {:reply, {:ok, record, %{quota: state.quota, used: new_used}}, new_state}
    end
  end

  def handle_call({:delete, account, id}, _from, state) do
    case Map.fetch(state.records, id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{account: owner}} when owner != account ->
        {:reply, {:error, :forbidden}, state}

      {:ok, record} ->
        size = Map.get(record, :size, 0)
        used = Map.get(state.usage, account, 0)
        new_used = max(used - size, 0)

        new_state = %{
          state
          | usage: Map.put(state.usage, account, new_used),
            records: Map.delete(state.records, id)
        }

        reply = {:ok, %{record: record, freed: size, used: new_used}}
        {:reply, reply, new_state}
    end
  end

  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state.records, id) do
      {:ok, record} -> {:reply, {:ok, record}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:usage, account}, _from, state) do
    {:reply, Map.get(state.usage, account, 0), state}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.records), state}
  end

  import Bitwise

  @spec uuid4() :: String.t()
  defp uuid4 do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c2 = c |> band(0x0FFF) |> bor(0x4000)
    d2 = d |> band(0x3FFF) |> bor(0x8000)

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c2, d2, e]
    )
    |> IO.iodata_to_binary()
  end

  @spec now_iso8601() :: String.t()
  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end
end

defmodule FileUpload.Validator do
  @moduledoc """
  Validates uploaded files by extension and content.

  Only `.csv` and `.json` files (case-insensitive) are accepted. CSV files
  must contain at least two lines or one comma-containing line. JSON files
  must parse via `Jason.decode/1`.
  """

  @type reason :: String.t()

  @doc """
  Validates the given `%Plug.Upload{}`, returning `:ok` or `{:error, reason}`.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, reason()}
  def validate(%Plug.Upload{} = upload) do
    ext = upload.filename |> to_string() |> Path.extname() |> String.downcase()

    case ext do
      ".csv" -> validate_csv(upload.path)
      ".json" -> validate_json(upload.path)
      _ -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

  @spec validate_csv(String.t()) :: :ok | {:error, reason()}
  defp validate_csv(path) do
    lines = path |> File.read!() |> String.split(~r/\r?\n/, trim: true)

    cond do
      length(lines) >= 2 -> :ok
      Enum.any?(lines, &String.contains?(&1, ",")) -> :ok
      true -> {:error, "Invalid CSV: file must contain a header row with multiple columns"}
    end
  end

  @spec validate_json(String.t()) :: :ok | {:error, reason()}
  defp validate_json(path) do
    case path |> File.read!() |> Jason.decode() do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  A `Plug.Router` exposing a multi-tenant, quota-enforced file upload API.

  Every request is attributed to an account via the `x-account-id` header.
  `POST /api/uploads` validates and stores a single `"file"` field, rejecting
  oversized files (413), invalid files (422) and quota-exceeding uploads (507)
  without side effects. `DELETE /api/uploads/:id` releases quota and removes
  the file, enforcing that only the owning account may delete it.

  Options (via `plug FileUpload.Router, opts`):

    * `:store` — PID or name of the `FileUpload.Store` GenServer.
    * `:upload_dir` — directory where files are saved.
    * `:base_url` — URL prefix for download URLs.
  """

  use Plug.Router

  alias FileUpload.{Store, Validator}

  @max_bytes 5_242_880

  plug Plug.Parsers, parsers: [:multipart], pass: ["*/*"], length: 20_000_000
  plug :match
  plug :dispatch, builder_opts()

  post "/api/uploads" do
    do_post(conn, opts)
  end

  delete "/api/uploads/:id" do
    do_delete(conn, id, opts)
  end

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  @spec do_post(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  defp do_post(conn, opts) do
    case account_id(conn) do
      nil -> send_json(conn, 400, %{error: "Missing account"})
      account -> handle_upload(conn, account, opts)
    end
  end

  @spec handle_upload(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  defp handle_upload(conn, account, opts) do
    case conn.params["file"] do
      %Plug.Upload{} = upload -> store_upload(conn, account, upload, opts)
      _ -> send_json(conn, 422, %{error: "No file provided"})
    end
  end

  @spec store_upload(Plug.Conn.t(), String.t(), Plug.Upload.t(), keyword()) ::
          Plug.Conn.t()
  defp store_upload(conn, account, upload, opts) do
    size = file_size(upload.path)

    cond do
      size > @max_bytes ->
        send_json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})

      match?({:error, _}, Validator.validate(upload)) ->
        {:error, message} = Validator.validate(upload)
        send_json(conn, 422, %{error: message})

      true ->
        persist(conn, account, upload, size, opts)
    end
  end

  @spec persist(Plug.Conn.t(), String.t(), Plug.Upload.t(), non_neg_integer(), keyword()) ::
          Plug.Conn.t()
  defp persist(conn, account, upload, size, opts) do
    store = Keyword.fetch!(opts, :store)
    dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    metadata = %{
      size: size,
      original_name: to_string(upload.filename),
      content_type: upload.content_type
    }

    case Store.save(store, account, metadata) do
      {:ok, record, %{quota: quota, used: used}} ->
        write_file(dir, record, upload)
        send_json(conn, 201, upload_body(record, used, quota, base_url))

      {:error, :quota_exceeded, %{quota: quota, used: used, requested: requested}} ->
        body = %{
          error: "Quota exceeded",
          quota_bytes: quota,
          used_bytes: used,
          requested_bytes: requested
        }

        send_json(conn, 507, body)
    end
  end

  @spec upload_body(map(), non_neg_integer(), non_neg_integer(), String.t()) :: map()
  defp upload_body(record, used, quota, base_url) do
    %{
      id: record.id,
      original_name: record.original_name,
      size: record.size,
      content_type: record.content_type,
      uploaded_at: record.uploaded_at,
      account_id: record.account,
      used_bytes: used,
      quota_bytes: quota,
      download_url: "#{base_url}/api/uploads/#{record.id}"
    }
  end

  @spec do_delete(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  defp do_delete(conn, id, opts) do
    case account_id(conn) do
      nil -> send_json(conn, 400, %{error: "Missing account"})
      account -> handle_delete(conn, account, id, opts)
    end
  end

  @spec handle_delete(Plug.Conn.t(), String.t(), String.t(), keyword()) :: Plug.Conn.t()
  defp handle_delete(conn, account, id, opts) do
    store = Keyword.fetch!(opts, :store)
    dir = Keyword.fetch!(opts, :upload_dir)

    case Store.delete(store, account, id) do
      {:ok, %{record: record, freed: freed, used: used}} ->
        remove_file(dir, record)
        send_json(conn, 200, %{id: id, freed_bytes: freed, used_bytes: used})

      {:error, :forbidden} ->
        send_json(conn, 403, %{error: "Forbidden"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Not found"})
    end
  end

  @spec write_file(String.t(), map(), Plug.Upload.t()) :: :ok
  defp write_file(dir, record, upload) do
    File.mkdir_p!(dir)
    File.cp!(upload.path, disk_path(dir, record))
    :ok
  end

  @spec remove_file(String.t(), map()) :: :ok
  defp remove_file(dir, record) do
    _ = File.rm(disk_path(dir, record))
    :ok
  end

  @spec disk_path(String.t(), map()) :: String.t()
  defp disk_path(dir, record) do
    ext = record |> Map.get(:original_name, "") |> Path.extname()
    Path.join(dir, record.id <> ext)
  end

  @spec account_id(Plug.Conn.t()) :: String.t() | nil
  defp account_id(conn) do
    case get_req_header(conn, "x-account-id") do
      [value | _] -> normalize(value)
      [] -> nil
    end
  end

  @spec normalize(String.t()) :: String.t() | nil
  defp normalize(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @spec file_size(String.t()) :: non_neg_integer()
  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> 0
    end
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end