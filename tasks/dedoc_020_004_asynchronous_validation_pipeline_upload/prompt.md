# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

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

  def create(server, metadata), do: GenServer.call(server, {:create, metadata})

  def update_status(server, id, status, extra),
    do: GenServer.call(server, {:update_status, id, status, extra})

  def get(server, id), do: GenServer.call(server, {:get, id})

  def list(server), do: GenServer.call(server, :list)

  @impl true
  def init(_opts), do: {:ok, %{files: %{}}}

  @impl true
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
