# Fill-in-the-Middle: `FileUpload.Router.store_and_persist/6`

Implement the private `store_and_persist/6` function in `FileUpload.Router`.

This function is called after a `%Plug.Upload{}` has passed size and validation
checks and is responsible for recording the upload's metadata, persisting the
file to disk, and returning the success response. Its signature is
`store_and_persist(conn, upload, size, store, upload_dir, base_url)`.

It should:

1. Build a metadata map from the upload with the keys `:original_name` (the
   upload's `filename`), `:size` (the given `size`), and `:content_type` (the
   upload's `content_type`).
2. Persist that metadata by calling `Store.save(store, metadata)`, which returns
   `{:ok, record}` where `record` includes the store-generated `:id` (a UUID v4)
   and an `:uploaded_at` ISO 8601 timestamp.
3. Copy the uploaded temp file (`upload.path`) onto disk under `upload_dir`,
   using the generated `record.id` as the filename while preserving the original
   file extension (via `Path.extname(upload.filename)`). Use `File.cp!/2`.
4. Construct a download URL of the form `"#{base_url}/api/uploads/#{record.id}"`
   and add it to the record under the `:download_url` key.
5. Respond with HTTP 201 and the resulting map as JSON, using the private
   `json/3` helper.

```elixir
defmodule FileUpload.Store do
  @moduledoc """
  A `GenServer` that stores uploaded-file metadata in memory, keyed by a
  generated UUID v4, and stamps each record with an ISO 8601 UTC timestamp.
  """

  use GenServer

  @max_bytes 5_242_880

  def max_bytes, do: @max_bytes

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
  `Plug.Router` exposing `POST /api/uploads`. Enforces a 5MB size limit,
  delegates validation to `FileUpload.Validator` and storage to
  `FileUpload.Store`, and persists the file to disk under its generated UUID.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  alias FileUpload.{Store, Validator}

  @max_bytes 5_242_880

  plug :match
  plug :dispatch

  post "/api/uploads" do
    opts = conn.assigns.router_opts

    case conn.params["file"] do
      %Plug.Upload{} = upload ->
        handle_upload(conn, upload, opts)

      _ ->
        json(conn, 422, %{error: "No file provided"})
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
          :ok ->
            store_and_persist(conn, upload, size, store, upload_dir, base_url)

          {:error, reason} ->
            json(conn, 422, %{error: reason})
        end
    end
  end

  defp store_and_persist(conn, upload, size, store, upload_dir, base_url) do
    # TODO
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```