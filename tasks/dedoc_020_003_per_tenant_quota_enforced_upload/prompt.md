# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule FileUpload.Store do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def save(server, account, metadata), do: GenServer.call(server, {:save, account, metadata})

  def delete(server, account, id), do: GenServer.call(server, {:delete, account, id})

  def get(server, id), do: GenServer.call(server, {:get, id})

  def usage(server, account), do: GenServer.call(server, {:usage, account})

  def list(server), do: GenServer.call(server, :list)

  @impl true
  def init(opts) do
    quota = Keyword.get(opts, :quota_bytes, 10_000_000)
    {:ok, %{quota: quota, files: %{}, usage: %{}}}
  end

  @impl true
  def handle_call({:save, account, metadata}, _from, state) do
    used = Map.get(state.usage, account, 0)
    size = metadata.size

    if used + size > state.quota do
      info = %{quota: state.quota, used: used, requested: size}
      {:reply, {:error, :quota_exceeded, info}, state}
    else
      record =
        metadata
        |> Map.put(:id, uuid_v4())
        |> Map.put(:uploaded_at, DateTime.utc_now() |> DateTime.to_iso8601())
        |> Map.put(:account, account)

      new_used = used + size

      state =
        state
        |> put_in([:files, record.id], record)
        |> put_in([:usage, account], new_used)

      {:reply, {:ok, record, %{quota: state.quota, used: new_used}}, state}
    end
  end

  def handle_call({:delete, account, id}, _from, state) do
    case Map.fetch(state.files, id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{account: owner}} when owner != account ->
        {:reply, {:error, :forbidden}, state}

      {:ok, record} ->
        used = Map.get(state.usage, account, 0)
        new_used = max(used - record.size, 0)

        state =
          state
          |> update_in([:files], &Map.delete(&1, id))
          |> put_in([:usage, account], new_used)

        {:reply, {:ok, %{record: record, freed: record.size, used: new_used}}, state}
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
  use Plug.Router, copy_opts_to_assign: :router_opts

  alias FileUpload.{Store, Validator}

  @max_bytes 5_242_880

  plug(:match)
  plug(:dispatch)

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
