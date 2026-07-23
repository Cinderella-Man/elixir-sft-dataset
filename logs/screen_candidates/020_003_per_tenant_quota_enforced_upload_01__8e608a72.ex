defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that tracks per-account byte usage against a fixed quota.

  The store keeps an in-memory map of upload records keyed by id and a map of
  per-account usage in bytes. All quota accounting happens inside the server
  process, giving `save/3` and `delete/3` atomic, all-or-nothing semantics: an
  upload that would exceed an account's budget is rejected without mutating any
  state, so no quota is consumed and (in the router) nothing is written to disk.
  """

  use GenServer

  @default_quota 10_000_000

  @doc """
  Starts the store.

  Options:

    * `:name` — an optional registered name for the process.
    * `:quota_bytes` — the per-account budget in bytes (default `10_000_000`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    quota = Keyword.get(opts, :quota_bytes, @default_quota)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{quota: quota}, gen_opts)
  end

  @doc """
  Reserves quota for and stores an upload described by `metadata`.

  `metadata` must contain `:size`. If storing would push the account over its
  quota, returns `{:error, :quota_exceeded, %{quota: q, used: u, requested: s}}`
  and leaves all state untouched. Otherwise a UUID v4 `:id`, an ISO 8601
  `:uploaded_at` timestamp and the `:account` are added, the record is stored,
  and `{:ok, record, %{quota: q, used: new_used}}` is returned.
  """
  @spec save(GenServer.server(), String.t(), map()) ::
          {:ok, map(), map()} | {:error, :quota_exceeded, map()}
  def save(server, account, metadata) do
    GenServer.call(server, {:save, account, metadata})
  end

  @doc """
  Deletes the upload `id` on behalf of `account`, releasing its bytes.

  Returns `{:ok, %{record: record, freed: size, used: new_used}}` on success,
  `{:error, :forbidden}` when `id` belongs to a different account, or
  `{:error, :not_found}` when no such upload exists.
  """
  @spec delete(GenServer.server(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :forbidden | :not_found}
  def delete(server, account, id) do
    GenServer.call(server, {:delete, account, id})
  end

  @doc """
  Fetches the metadata for upload `id`.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(server, id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Returns the current used bytes for `account` (0 if the account is unknown).
  """
  @spec usage(GenServer.server(), String.t()) :: non_neg_integer()
  def usage(server, account) do
    GenServer.call(server, {:usage, account})
  end

  @doc """
  Returns every stored upload's metadata.
  """
  @spec list(GenServer.server()) :: [map()]
  def list(server) do
    GenServer.call(server, :list)
  end

  @impl true
  @doc false
  @spec init(%{quota: non_neg_integer()}) :: {:ok, map()}
  def init(%{quota: quota}) do
    {:ok, %{quota: quota, records: %{}, usage: %{}}}
  end

  @impl true
  @doc false
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:save, account, metadata}, _from, state) do
    size = Map.fetch!(metadata, :size)
    quota = state.quota
    used = Map.get(state.usage, account, 0)

    if used + size > quota do
      reason = %{quota: quota, used: used, requested: size}
      {:reply, {:error, :quota_exceeded, reason}, state}
    else
      id = generate_uuid()

      record =
        metadata
        |> Map.put(:id, id)
        |> Map.put(:account, account)
        |> Map.put(:uploaded_at, iso_now())

      new_used = used + size

      new_state = %{
        state
        | records: Map.put(state.records, id, record),
          usage: Map.put(state.usage, account, new_used)
      }

      {:reply, {:ok, record, %{quota: quota, used: new_used}}, new_state}
    end
  end

  def handle_call({:delete, account, id}, _from, state) do
    case Map.fetch(state.records, id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{account: owner}} when owner != account ->
        {:reply, {:error, :forbidden}, state}

      {:ok, record} ->
        size = Map.fetch!(record, :size)
        used = Map.get(state.usage, account, 0)
        new_used = max(used - size, 0)

        new_state = %{
          state
          | records: Map.delete(state.records, id),
            usage: Map.put(state.usage, account, new_used)
        }

        reply = %{record: record, freed: size, used: new_used}
        {:reply, {:ok, reply}, new_state}
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

  @spec iso_now() :: String.t()
  defp iso_now do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  @spec generate_uuid() :: String.t()
  defp generate_uuid do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    raw = <<u0::48, 4::4, u1::12, 2::2, u2::62>>

    <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
      e::binary-size(6)>> = raw

    Enum.map_join([a, b, c, d, e], "-", fn part -> Base.encode16(part, case: :lower) end)
  end
end

defmodule FileUpload.Validator do
  @moduledoc """
  Content validation for uploaded files.

  Only `.csv` and `.json` files (case-insensitive extension) are accepted. CSV
  files must look like tabular data (at least two lines, or a single line that
  contains a comma). JSON files must parse cleanly with `Jason`.
  """

  @allowed_exts ~w(.csv .json)

  @doc """
  Validates a `%Plug.Upload{}`, returning `:ok` or `{:error, reason}`.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, String.t()}
  def validate(%Plug.Upload{filename: filename, path: path}) do
    ext = filename |> Path.extname() |> String.downcase()

    cond do
      ext not in @allowed_exts ->
        {:error, "File type not allowed. Only .csv and .json files are accepted"}

      ext == ".csv" ->
        validate_csv(path)

      true ->
        validate_json(path)
    end
  end

  @spec validate_csv(String.t()) :: :ok | {:error, String.t()}
  defp validate_csv(path) do
    lines =
      path
      |> File.read!()
      |> String.split(["\r\n", "\n"], trim: true)

    multiple_lines? = length(lines) >= 2
    comma_line? = Enum.any?(lines, &String.contains?(&1, ","))

    if multiple_lines? or comma_line? do
      :ok
    else
      {:error, "Invalid CSV: file must contain a header row with multiple columns"}
    end
  end

  @spec validate_json(String.t()) :: :ok | {:error, String.t()}
  defp validate_json(path) do
    case path |> File.read!() |> Jason.decode() do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  A `Plug.Router` exposing a multi-tenant, quota-enforced upload API.

  Every request must carry an `x-account-id` header identifying the owning
  account. `POST /api/uploads` accepts a single multipart file under the field
  name `"file"`, validates it, and reserves quota through `FileUpload.Store`
  before writing it to disk as `<id><ext>`. When an upload would exceed the
  account's budget it is rejected with HTTP 507 and nothing is written or
  reserved. `DELETE /api/uploads/:id` removes an upload owned by the account and
  releases its bytes back to the budget.

  Options (via `plug FileUpload.Router, opts`):

    * `:store` — the pid or name of the `FileUpload.Store` GenServer.
    * `:upload_dir` — the directory where files are saved.
    * `:base_url` — the URL prefix used to build download URLs.
  """

  use Plug.Router

  @max_file_bytes 5_242_880

  plug(Plug.Parsers,
    parsers: [:multipart, :urlencoded],
    pass: ["*/*"],
    length: 25_000_000
  )

  plug(:put_router_opts, builder_opts())
  plug(:match)
  plug(:dispatch)

  @doc """
  Plug callback that normalizes and stashes the router options on the conn so
  route handlers can read them at runtime.
  """
  @spec put_router_opts(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def put_router_opts(conn, opts) do
    normalized = %{
      store: Keyword.get(opts, :store),
      upload_dir: Keyword.get(opts, :upload_dir, System.tmp_dir!()),
      base_url: Keyword.get(opts, :base_url, "")
    }

    Plug.Conn.put_private(conn, :fu_opts, normalized)
  end

  post "/api/uploads" do
    handle_upload(conn)
  end

  delete "/api/uploads/:id" do
    handle_delete(conn, id)
  end

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  @spec handle_upload(Plug.Conn.t()) :: Plug.Conn.t()
  defp handle_upload(conn) do
    case account_id(conn) do
      :error ->
        send_json(conn, 400, %{error: "Missing account"})

      {:ok, account} ->
        opts = conn.private.fu_opts

        case Map.get(conn.params, "file") do
          %Plug.Upload{} = upload -> process_upload(conn, account, upload, opts)
          _other -> send_json(conn, 422, %{error: "No file provided"})
        end
    end
  end

  @spec process_upload(Plug.Conn.t(), String.t(), Plug.Upload.t(), map()) :: Plug.Conn.t()
  defp process_upload(conn, account, upload, opts) do
    size = file_size(upload)

    cond do
      size > @max_file_bytes ->
        send_json(conn, 413, %{error: "File too large", max_bytes: @max_file_bytes})

      match?({:error, _reason}, FileUpload.Validator.validate(upload)) ->
        {:error, reason} = FileUpload.Validator.validate(upload)
        send_json(conn, 422, %{error: reason})

      true ->
        store_and_respond(conn, account, upload, size, opts)
    end
  end

  @spec store_and_respond(Plug.Conn.t(), String.t(), Plug.Upload.t(), non_neg_integer(), map()) ::
          Plug.Conn.t()
  defp store_and_respond(conn, account, upload, size, opts) do
    metadata = %{
      size: size,
      original_name: upload.filename,
      content_type: upload.content_type
    }

    case FileUpload.Store.save(opts.store, account, metadata) do
      {:error, :quota_exceeded, %{quota: quota, used: used, requested: requested}} ->
        send_json(conn, 507, %{
          error: "Quota exceeded",
          quota_bytes: quota,
          used_bytes: used,
          requested_bytes: requested
        })

      {:ok, record, %{quota: quota, used: used}} ->
        :ok = write_file(upload, record, opts.upload_dir)

        send_json(conn, 201, %{
          id: record.id,
          original_name: record.original_name,
          size: record.size,
          content_type: record.content_type,
          uploaded_at: record.uploaded_at,
          account_id: account,
          used_bytes: used,
          quota_bytes: quota,
          download_url: download_url(opts.base_url, record.id)
        })
    end
  end

  @spec handle_delete(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp handle_delete(conn, id) do
    case account_id(conn) do
      :error ->
        send_json(conn, 400, %{error: "Missing account"})

      {:ok, account} ->
        opts = conn.private.fu_opts

        case FileUpload.Store.delete(opts.store, account, id) do
          {:ok, %{record: record, freed: freed, used: used}} ->
            remove_file(record, opts.upload_dir)
            send_json(conn, 200, %{id: id, freed_bytes: freed, used_bytes: used})

          {:error, :forbidden} ->
            send_json(conn, 403, %{error: "Forbidden"})

          {:error, :not_found} ->
            send_json(conn, 404, %{error: "Not found"})
        end
    end
  end

  @spec account_id(Plug.Conn.t()) :: {:ok, String.t()} | :error
  defp account_id(conn) do
    case get_req_header(conn, "x-account-id") do
      [value | _rest] ->
        trimmed = String.trim(value)
        if trimmed == "", do: :error, else: {:ok, trimmed}

      [] ->
        :error
    end
  end

  @spec file_size(Plug.Upload.t()) :: non_neg_integer()
  defp file_size(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _other -> 0
    end
  end

  @spec write_file(Plug.Upload.t(), map(), String.t()) :: :ok
  defp write_file(upload, record, dir) do
    File.mkdir_p!(dir)
    ext = Path.extname(record.original_name)
    dest = Path.join(dir, record.id <> ext)
    File.cp!(upload.path, dest)
    :ok
  end

  @spec remove_file(map(), String.t()) :: :ok
  defp remove_file(record, dir) do
    ext = Path.extname(record.original_name)
    dest = Path.join(dir, record.id <> ext)
    _ = File.rm(dest)
    :ok
  end

  @spec download_url(String.t(), String.t()) :: String.t()
  defp download_url(base_url, id) do
    "#{base_url}/api/uploads/#{id}"
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end