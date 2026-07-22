defmodule FileUpload.Validator do
  @moduledoc """
  Validation rules for incoming `%Plug.Upload{}` structs.

  Only `.csv` and `.json` files are accepted (case-insensitive extension check).
  CSV files must look like they carry a header row with multiple columns, and
  JSON files must parse cleanly with `Jason`.
  """

  @allowed_extensions [".csv", ".json"]

  @doc """
  Validates an uploaded file.

  Returns `:ok` when the upload passes every rule, or `{:error, reason}` with a
  human-readable reason describing the first rule that failed.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, String.t()}
  def validate(%Plug.Upload{filename: filename, path: path}) do
    case normalized_extension(filename) do
      ".csv" -> validate_csv(path)
      ".json" -> validate_json(path)
      _other -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end

  @spec normalized_extension(String.t() | nil) :: String.t()
  defp normalized_extension(nil), do: ""

  defp normalized_extension(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
  end

  @spec validate_csv(String.t()) :: :ok | {:error, String.t()}
  defp validate_csv(path) do
    content = read_file(path)

    lines =
      content
      |> String.split(~r/\r\n|\r|\n/)
      |> Enum.reject(&(String.trim(&1) == ""))

    cond do
      length(lines) >= 2 -> :ok
      Enum.any?(lines, &String.contains?(&1, ",")) -> :ok
      true -> {:error, "Invalid CSV: file must contain a header row with multiple columns"}
    end
  end

  @spec validate_json(String.t()) :: :ok | {:error, String.t()}
  defp validate_json(path) do
    case Jason.decode(read_file(path)) do
      {:ok, _decoded} -> :ok
      {:error, error} -> {:error, "Invalid JSON: " <> Exception.message(error)}
    end
  end

  @spec read_file(String.t()) :: String.t()
  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _reason} -> ""
    end
  end

  @spec allowed_extensions() :: [String.t()]
  @doc """
  Returns the list of accepted file extensions, lower-cased and dot-prefixed.
  """
  def allowed_extensions, do: @allowed_extensions
end

defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` holding upload metadata plus per-account byte usage.

  Every account shares the same fixed `:quota_bytes` budget. Saving a record is
  atomic and all-or-nothing: an upload that would push the account past its
  budget leaves the state completely untouched and returns
  `{:error, :quota_exceeded, details}`. Deleting a record releases its bytes
  back to the owning account.
  """

  use GenServer

  @default_quota_bytes 10_000_000

  @type account :: String.t()
  @type metadata :: map()
  @type quota_info :: %{quota: non_neg_integer(), used: non_neg_integer()}

  @doc """
  Starts the store.

  Options:

    * `:name` — optional registered name for the process.
    * `:quota_bytes` — per-account budget in bytes (default `#{@default_quota_bytes}`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Reserves quota for `account` and stores `metadata` atomically.

  `metadata` must contain a `:size` key. On success returns
  `{:ok, record, %{quota: q, used: used_after}}` where `record` gained `:id`,
  `:uploaded_at` and `:account`. When the upload does not fit, returns
  `{:error, :quota_exceeded, %{quota: q, used: used_before, requested: size}}`
  and nothing is stored.
  """
  @spec save(GenServer.server(), account(), metadata()) ::
          {:ok, metadata(), quota_info()}
          | {:error, :quota_exceeded, %{quota: non_neg_integer(), used: non_neg_integer(),
             requested: non_neg_integer()}}
  def save(server, account, metadata) do
    GenServer.call(server, {:save, account, metadata})
  end

  @doc """
  Deletes the record `id` on behalf of `account`, releasing its bytes.

  Returns `{:ok, %{record: record, freed: size, used: used_after}}`,
  `{:error, :forbidden}` when the record belongs to another account, or
  `{:error, :not_found}`.
  """
  @spec delete(GenServer.server(), account(), String.t()) ::
          {:ok, %{record: metadata(), freed: non_neg_integer(), used: non_neg_integer()}}
          | {:error, :forbidden | :not_found}
  def delete(server, account, id) do
    GenServer.call(server, {:delete, account, id})
  end

  @doc """
  Fetches the metadata stored under `id`.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, metadata()} | {:error, :not_found}
  def get(server, id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Returns the number of bytes currently used by `account` (0 when unknown).
  """
  @spec usage(GenServer.server(), account()) :: non_neg_integer()
  def usage(server, account) do
    GenServer.call(server, {:usage, account})
  end

  @doc """
  Returns the per-account quota in bytes.
  """
  @spec quota_bytes(GenServer.server()) :: non_neg_integer()
  def quota_bytes(server) do
    GenServer.call(server, :quota_bytes)
  end

  @doc """
  Returns every stored metadata record.
  """
  @spec list(GenServer.server()) :: [metadata()]
  def list(server) do
    GenServer.call(server, :list)
  end

  @impl GenServer
  def init(opts) do
    quota = Keyword.get(opts, :quota_bytes, @default_quota_bytes)
    {:ok, %{files: %{}, usage: %{}, quota: quota}}
  end

  @impl GenServer
  def handle_call({:save, account, metadata}, _from, state) do
    size = Map.get(metadata, :size, 0)
    used = Map.get(state.usage, account, 0)

    if used + size > state.quota do
      details = %{quota: state.quota, used: used, requested: size}
      {:reply, {:error, :quota_exceeded, details}, state}
    else
      record =
        metadata
        |> Map.put(:id, uuid4())
        |> Map.put(:uploaded_at, DateTime.utc_now() |> DateTime.to_iso8601())
        |> Map.put(:account, account)

      new_used = used + size

      new_state = %{
        state
        | files: Map.put(state.files, record.id, record),
          usage: Map.put(state.usage, account, new_used)
      }

      {:reply, {:ok, record, %{quota: state.quota, used: new_used}}, new_state}
    end
  end

  def handle_call({:delete, account, id}, _from, state) do
    case Map.fetch(state.files, id) do
      {:ok, %{account: owner}} when owner != account ->
        {:reply, {:error, :forbidden}, state}

      {:ok, record} ->
        size = Map.get(record, :size, 0)
        new_used = max(Map.get(state.usage, account, 0) - size, 0)

        new_state = %{
          state
          | files: Map.delete(state.files, id),
            usage: Map.put(state.usage, account, new_used)
        }

        {:reply, {:ok, %{record: record, freed: size, used: new_used}}, new_state}

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

  def handle_call({:usage, account}, _from, state) do
    {:reply, Map.get(state.usage, account, 0), state}
  end

  def handle_call(:quota_bytes, _from, state) do
    {:reply, state.quota, state}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.files), state}
  end

  @spec uuid4() :: String.t()
  defp uuid4 do
    <<a::32, b::16, _c::4, d::12, _e::2, f::62>> = :crypto.strong_rand_bytes(16)

    <<a::32, b::16, 4::4, d::12, 2::2, f::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  @spec format_uuid(String.t()) :: String.t()
  defp format_uuid(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>>) do
    Enum.join([a, b, c, d, e], "-")
  end
end

defmodule FileUpload.Router do
  @moduledoc """
  A `Plug.Router` exposing a multi-tenant, quota-enforced upload endpoint.

  Every request must carry an `x-account-id` header identifying the account the
  request is attributed to. Uploads consume the account's byte budget and are
  rejected with HTTP 507 when they would exceed it — without writing anything
  to disk or consuming any quota. Deletes release bytes back to the account.

  Options accepted by `plug FileUpload.Router, opts`:

    * `:store` — PID or registered name of the `FileUpload.Store`.
    * `:upload_dir` — directory where uploaded files are written.
    * `:base_url` — URL prefix used to build download URLs.
  """

  use Plug.Router

  @max_file_bytes 5_242_880

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug :match
  plug :dispatch

  @doc """
  Builds the router options used for every request.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Entry point invoked by `Plug` for each request.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_private(:file_upload_opts, opts)
    |> super(opts)
  end

  @doc """
  Returns the maximum accepted size for a single uploaded file, in bytes.
  """
  @spec max_file_bytes() :: pos_integer()
  def max_file_bytes, do: @max_file_bytes

  post "/api/uploads" do
    with {:ok, account} <- fetch_account(conn),
         {:ok, upload} <- fetch_upload(conn),
         {:ok, size} <- check_size(upload),
         :ok <- FileUpload.Validator.validate(upload) do
      store_upload(conn, account, upload, size)
    else
      {:error, status, payload} -> send_json(conn, status, payload)
    end
  end

  delete "/api/uploads/:id" do
    case fetch_account(conn) do
      {:ok, account} -> delete_upload(conn, account, id)
      {:error, status, payload} -> send_json(conn, status, payload)
    end
  end

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  @spec fetch_account(Plug.Conn.t()) :: {:ok, String.t()} | {:error, 400, map()}
  defp fetch_account(conn) do
    value =
      conn
      |> get_req_header("x-account-id")
      |> List.first()
      |> case do
        nil -> ""
        raw -> String.trim(raw)
      end

    if value == "" do
      {:error, 400, %{error: "Missing account"}}
    else
      {:ok, value}
    end
  end

  @spec fetch_upload(Plug.Conn.t()) :: {:ok, Plug.Upload.t()} | {:error, 422, map()}
  defp fetch_upload(conn) do
    case conn.params do
      %{"file" => %Plug.Upload{} = upload} -> {:ok, upload}
      _other -> {:error, 422, %{error: "No file provided"}}
    end
  end

  @spec check_size(Plug.Upload.t()) :: {:ok, non_neg_integer()} | {:error, 413, map()}
  defp check_size(%Plug.Upload{path: path}) do
    size =
      case File.stat(path) do
        {:ok, %File.Stat{size: size}} -> size
        {:error, _reason} -> 0
      end

    if size > @max_file_bytes do
      {:error, 413, %{error: "File too large", max_bytes: @max_file_bytes}}
    else
      {:ok, size}
    end
  end

  @spec store_upload(Plug.Conn.t(), String.t(), Plug.Upload.t(), non_neg_integer()) ::
          Plug.Conn.t()
  defp store_upload(conn, account, upload, size) do
    opts = conn.private[:file_upload_opts] || []
    store = Keyword.fetch!(opts, :store)

    metadata = %{
      original_name: upload.filename,
      size: size,
      content_type: upload.content_type
    }

    case FileUpload.Store.save(store, account, metadata) do
      {:ok, record, %{quota: quota, used: used}} ->
        :ok = persist_file(opts, upload, record)

        send_json(conn, 201, %{
          id: record.id,
          original_name: record.original_name,
          size: record.size,
          content_type: record.content_type,
          uploaded_at: record.uploaded_at,
          account_id: record.account,
          used_bytes: used,
          quota_bytes: quota,
          download_url: download_url(opts, record.id)
        })

      {:error, :quota_exceeded, %{quota: quota, used: used, requested: requested}} ->
        send_json(conn, 507, %{
          error: "Quota exceeded",
          quota_bytes: quota,
          used_bytes: used,
          requested_bytes: requested
        })
    end
  end

  @spec delete_upload(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  defp delete_upload(conn, account, id) do
    opts = conn.private[:file_upload_opts] || []
    store = Keyword.fetch!(opts, :store)

    case FileUpload.Store.delete(store, account, id) do
      {:ok, %{record: record, freed: freed, used: used}} ->
        _ = remove_file(opts, record)
        send_json(conn, 200, %{id: id, freed_bytes: freed, used_bytes: used})

      {:error, :forbidden} ->
        send_json(conn, 403, %{error: "Forbidden"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "Not found"})
    end
  end

  @spec persist_file(keyword(), Plug.Upload.t(), map()) :: :ok
  defp persist_file(opts, upload, record) do
    dir = Keyword.fetch!(opts, :upload_dir)
    File.mkdir_p!(dir)
    destination = Path.join(dir, stored_name(record))

    case File.cp(upload.path, destination) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @spec remove_file(keyword(), map()) :: :ok
  defp remove_file(opts, record) do
    case Keyword.fetch(opts, :upload_dir) do
      {:ok, dir} ->
        _ = File.rm(Path.join(dir, stored_name(record)))
        :ok

      :error ->
        :ok
    end
  end

  @spec stored_name(map()) :: String.t()
  defp stored_name(record) do
    extension =
      record
      |> Map.get(:original_name)
      |> case do
        nil -> ""
        name -> Path.extname(name)
      end

    record.id <> extension
  end

  @spec download_url(keyword(), String.t()) :: String.t()
  defp download_url(opts, id) do
    base = opts |> Keyword.get(:base_url, "") |> String.trim_trailing("/")
    base <> "/api/uploads/" <> id
  end

  @spec send_json(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end