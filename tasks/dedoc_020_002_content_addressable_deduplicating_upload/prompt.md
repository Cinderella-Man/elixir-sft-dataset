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

  def save(server, hash, metadata), do: GenServer.call(server, {:save, hash, metadata})

  def get(server, id), do: GenServer.call(server, {:get, id})

  def list(server), do: GenServer.call(server, :list)

  @impl true
  def init(_opts), do: {:ok, %{files: %{}}}

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
      %Plug.Upload{} = upload -> handle_upload(conn, upload, opts)
      _ -> json(conn, 422, %{error: "No file provided"})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

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
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```
