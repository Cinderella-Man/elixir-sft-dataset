Implement the `handle_call/3` callbacks for the `FileUpload.Store` GenServer. This
single function (spread across several clauses, one per request tuple) is the heart
of the store's quota accounting. The state is a map `%{quota: q, files: %{}, usage: %{}}`
where `files` maps a file `id` to its record and `usage` maps an account to its
current used bytes. Implement the following clauses:

- **`{:save, account, metadata}`** — Look up the account's current `used` bytes
  (defaulting to `0`) and read `size` from `metadata.size`. If `used + size` exceeds
  `state.quota`, reply with `{:error, :quota_exceeded, %{quota: q, used: used, requested: size}}`
  and leave the state **unchanged** (atomic, all-or-nothing rejection). Otherwise
  build the record by putting a freshly generated `:id` (via `uuid_v4/0`), an
  `:uploaded_at` timestamp (ISO 8601 UTC), and the `:account` into `metadata`;
  store the record under its id in `files`, set the account's usage to `used + size`,
  and reply with `{:ok, record, %{quota: q, used: new_used}}` along with the updated state.

- **`{:delete, account, id}`** — Fetch the record for `id`. If it is missing, reply
  `{:error, :not_found}`. If it exists but its `:account` differs from `account`,
  reply `{:error, :forbidden}`. Otherwise remove the file from `files`, decrement the
  account's usage by the record's size (never below `0`), and reply
  `{:ok, %{record: record, freed: size, used: new_used}}` with the updated state.

- **`{:get, id}`** — Reply `{:ok, record}` if the file exists, else `{:error, :not_found}`.

- **`{:usage, account}`** — Reply with the account's current used bytes (`0` if unknown).

- **`:list`** — Reply with all stored metadata records (the values of `files`).

```elixir
defmodule FileUpload.Store do
  @moduledoc """
  A multi-tenant `GenServer` store that enforces a per-account byte quota. Every
  save reserves the file's bytes against the owning account's budget atomically,
  rejecting over-budget uploads without any state change; deleting a file releases
  its bytes back to the account.
  """

  use GenServer

  @doc """
  Starts the store. Accepts `:name` (registration) and `:quota_bytes` (per-account
  budget, default `10_000_000`).
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

  @doc """
  Reserves `metadata.size` against `account`'s quota and stores the record.
  Returns `{:ok, record, %{quota, used}}` or `{:error, :quota_exceeded, %{quota,
  used, requested}}` (no state change on rejection).
  """
  @spec save(GenServer.server(), String.t(), map()) ::
          {:ok, map(), map()} | {:error, :quota_exceeded, map()}
  def save(server, account, metadata), do: GenServer.call(server, {:save, account, metadata})

  @doc """
  Deletes file `id` on behalf of `account`, releasing its bytes. Returns
  `{:ok, %{record, freed, used}}`, `{:error, :forbidden}`, or `{:error, :not_found}`.
  """
  @spec delete(GenServer.server(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :forbidden} | {:error, :not_found}
  def delete(server, account, id), do: GenServer.call(server, {:delete, account, id})

  @doc """
  Fetches the stored metadata for file `id`.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(server, id), do: GenServer.call(server, {:get, id})

  @doc """
  Returns the current used bytes for `account` (0 if unknown).
  """
  @spec usage(GenServer.server(), String.t()) :: non_neg_integer()
  def usage(server, account), do: GenServer.call(server, {:usage, account})

  @doc """
  Returns all stored metadata records.
  """
  @spec list(GenServer.server()) :: [map()]
  def list(server), do: GenServer.call(server, :list)

  @impl true
  def init(opts) do
    quota = Keyword.get(opts, :quota_bytes, 10_000_000)
    {:ok, %{quota: quota, files: %{}, usage: %{}}}
  end

  @impl true
  def handle_call(request, _from, state) do
    # TODO
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
  Validates `upload`. Returns `:ok` when the file has an allowed extension and
  valid content for its type, otherwise `{:error, message}`.
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
  `Plug.Router` exposing `POST /api/uploads` and `DELETE /api/uploads/:id` with
  per-account byte quotas. The account is taken from the `x-account-id` header;
  over-budget uploads return 507 without side effects and deletes free the
  owning account's quota.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  alias FileUpload.{Store, Validator}

  @max_bytes 5_242_880

  plug :match
  plug :dispatch

  post "/api/uploads" do
    opts = conn.assigns.router_opts

    case account(conn) do
      nil ->
        json(conn, 400, %{error: "Missing account"})

      acct ->
        case conn.params["file"] do
          %Plug.Upload{} = upload -> handle_upload(conn, upload, acct, opts)
          _ -> json(conn, 422, %{error: "No file provided"})
        end
    end
  end

  delete "/api/uploads/:id" do
    opts = conn.assigns.router_opts
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)

    case account(conn) do
      nil ->
        json(conn, 400, %{error: "Missing account"})

      acct ->
        case Store.delete(store, acct, id) do
          {:ok, info} ->
            ext = Path.extname(info.record.original_name)
            File.rm(Path.join(upload_dir, info.record.id <> ext))
            json(conn, 200, %{id: info.record.id, freed_bytes: info.freed, used_bytes: info.used})

          {:error, :forbidden} ->
            json(conn, 403, %{error: "Forbidden"})

          {:error, :not_found} ->
            json(conn, 404, %{error: "Not found"})
        end
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp handle_upload(conn, upload, acct, opts) do
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    size = File.stat!(upload.path).size

    cond do
      size > @max_bytes ->
        json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})

      true ->
        case Validator.validate(upload) do
          :ok -> reserve_and_persist(conn, upload, size, acct, store, upload_dir, base_url)
          {:error, reason} -> json(conn, 422, %{error: reason})
        end
    end
  end

  defp reserve_and_persist(conn, upload, size, acct, store, upload_dir, base_url) do
    metadata = %{
      original_name: upload.filename,
      size: size,
      content_type: upload.content_type
    }

    case Store.save(store, acct, metadata) do
      {:ok, record, %{quota: quota, used: used}} ->
        ext = Path.extname(upload.filename)
        File.cp!(upload.path, Path.join(upload_dir, record.id <> ext))

        response = %{
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

        json(conn, 201, response)

      {:error, :quota_exceeded, %{quota: quota, used: used, requested: requested}} ->
        json(conn, 507, %{
          error: "Quota exceeded",
          quota_bytes: quota,
          used_bytes: used,
          requested_bytes: requested
        })
    end
  end

  defp account(conn) do
    case get_req_header(conn, "x-account-id") do
      [a | _] when is_binary(a) and a != "" -> a
      _ -> nil
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```