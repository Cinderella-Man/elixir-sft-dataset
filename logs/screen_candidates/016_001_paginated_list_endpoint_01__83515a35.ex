<file path="lib/paginated_list/item.ex">
defmodule PaginatedList.Item do
  @moduledoc """
  Ecto schema for a row in the `items` table.

  An item carries a human readable `:name` plus microsecond-precision
  `:inserted_at` / `:updated_at` timestamps. The timestamps are declared with
  `utc_datetime_usec` so bulk inserts through `Ecto.Repo.insert_all/3` can supply
  `DateTime` values directly, and so ordering by `:inserted_at` stays stable even
  when many rows are created within the same second.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "items" do
    field :name, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for an item.

  Casts and requires `:name`. Timestamps are managed by `Ecto` (or supplied
  explicitly by bulk inserts) and are therefore not castable here.

  ## Examples

      iex> PaginatedList.Item.changeset(%PaginatedList.Item{}, %{name: "widget"}).valid?
      true

      iex> PaginatedList.Item.changeset(%PaginatedList.Item{}, %{}).valid?
      false

  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
</file>
<file path="lib/paginated_list/items.ex">
defmodule PaginatedList.Items do
  @moduledoc """
  Context for reading `PaginatedList.Item` records.

  The only entry point is `list_items/1`, which turns raw query-string parameters
  into a bounded, deterministic page of items plus pagination metadata. All
  pagination is implemented with plain `Ecto.Query` `limit`/`offset` — no external
  pagination library is involved.
  """

  import Ecto.Query, warn: false

  alias PaginatedList.Item
  alias PaginatedList.Repo

  @default_page 1
  @default_page_size 20
  @max_page_size 100

  @type meta :: %{
          current_page: pos_integer(),
          page_size: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: non_neg_integer()
        }

  @type result :: %{data: [Item.t()], meta: meta()}

  @doc """
  Lists a single page of items together with pagination metadata.

  `params` is the raw parameter map as it arrives from a query string, so the
  `"page"` and `"page_size"` keys are expected to be strings; atom keys and
  integers are also accepted for convenience.

  Normalisation rules:

    * missing / unparseable `"page"` falls back to `#{@default_page}`
    * missing / unparseable `"page_size"` falls back to `#{@default_page_size}`
    * `page_size` greater than `#{@max_page_size}` is clamped to `#{@max_page_size}`
    * `page` below 1 falls back to `#{@default_page}`
    * `page_size` below 1 falls back to `#{@default_page_size}`

  Items are ordered by `:inserted_at` ascending, then `:id` ascending, which makes
  paging deterministic even for rows sharing a timestamp.

  `total_pages` is `ceil(total_count / page_size)`, so it is `0` when there are no
  items at all. Requesting a page beyond the last one yields an empty `:data` list
  while `:meta` still reports the true totals.

  ## Examples

      iex> %{data: data, meta: meta} = PaginatedList.Items.list_items(%{"page" => "2"})
      iex> is_list(data) and meta.current_page == 2
      true

  """
  @spec list_items(map()) :: result()
  def list_items(params) when is_map(params) do
    page = normalize_page(fetch_param(params, "page"))
    page_size = normalize_page_size(fetch_param(params, "page_size"))

    total_count = Repo.aggregate(Item, :count, :id)
    total_pages = total_pages(total_count, page_size)

    data =
      Item
      |> order_by([i], asc: i.inserted_at, asc: i.id)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()

    %{
      data: data,
      meta: %{
        current_page: page,
        page_size: page_size,
        total_count: total_count,
        total_pages: total_pages
      }
    }
  end

  @spec fetch_param(map(), String.t()) :: term()
  defp fetch_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> value
      :error -> Map.get(params, String.to_existing_atom(key))
    end
  rescue
    ArgumentError -> nil
  end

  @spec normalize_page(term()) :: pos_integer()
  defp normalize_page(value) do
    case to_integer(value) do
      integer when is_integer(integer) and integer >= 1 -> integer
      _other -> @default_page
    end
  end

  @spec normalize_page_size(term()) :: pos_integer()
  defp normalize_page_size(value) do
    case to_integer(value) do
      integer when is_integer(integer) and integer >= 1 -> min(integer, @max_page_size)
      _other -> @default_page_size
    end
  end

  @spec to_integer(term()) :: integer() | nil
  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp to_integer(_value), do: nil

  @spec total_pages(non_neg_integer(), pos_integer()) :: non_neg_integer()
  defp total_pages(0, _page_size), do: 0
  defp total_pages(total_count, page_size), do: ceil(total_count / page_size)
end
</file>
<file path="lib/paginated_list_web/controllers/item_controller.ex">
defmodule PaginatedListWeb.ItemController do
  @moduledoc """
  JSON controller exposing `GET /api/items`.

  The `index/2` action pulls the `page` / `page_size` query parameters straight
  off `conn.params`, delegates the actual work to `PaginatedList.Items`, and renders
  the result through `PaginatedListWeb.ItemJSON`.
  """

  use Phoenix.Controller, formats: [:json]

  alias PaginatedList.Items
  alias PaginatedListWeb.ItemJSON

  @doc """
  Renders a page of items as JSON.

  Responds with a `"data"` list of items and a `"meta"` object carrying
  `current_page`, `page_size`, `total_count` and `total_pages`.

  ## Examples

      GET /api/items?page=2&page_size=10

  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    params = Map.take(conn.params, ["page", "page_size"])
    %{data: data, meta: meta} = Items.list_items(params)

    json(conn, ItemJSON.index(%{items: data, meta: meta}))
  end
end
</file>
<file path="lib/paginated_list_web/controllers/item_json.ex">
defmodule PaginatedListWeb.ItemJSON do
  @moduledoc """
  Renders `PaginatedList.Item` records and pagination metadata as plain maps
  ready for JSON encoding.
  """

  alias PaginatedList.Item

  @type meta :: %{
          current_page: pos_integer(),
          page_size: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: non_neg_integer()
        }

  @doc """
  Renders a page of items plus its metadata.

  Expects `%{items: [%Item{}], meta: map()}` and returns a map shaped as
  `%{data: [...], meta: %{...}}`.

  ## Examples

      iex> PaginatedListWeb.ItemJSON.index(%{items: [], meta: %{current_page: 1,
      ...>   page_size: 20, total_count: 0, total_pages: 0}})
      %{data: [], meta: %{current_page: 1, page_size: 20, total_count: 0, total_pages: 0}}

  """
  @spec index(%{items: [Item.t()], meta: meta()}) :: %{data: [map()], meta: meta()}
  def index(%{items: items, meta: meta}) do
    %{data: Enum.map(items, &data/1), meta: meta}
  end

  @doc """
  Renders a single item as a map with `:id`, `:name` and `:inserted_at`.

  The timestamp is emitted in ISO 8601 form.
  """
  @spec data(Item.t()) :: %{id: integer(), name: String.t() | nil, inserted_at: String.t() | nil}
  def data(%Item{} = item) do
    %{
      id: item.id,
      name: item.name,
      inserted_at: encode_timestamp(item.inserted_at)
    }
  end

  @spec encode_timestamp(DateTime.t() | nil) :: String.t() | nil
  defp encode_timestamp(nil), do: nil
  defp encode_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
</file>
<file path="lib/paginated_list_web/router.ex">
defmodule PaginatedListWeb.Router do
  @moduledoc """
  Router for the JSON API.

  Mounts `PaginatedListWeb.ItemController` under the `/api` scope, so the paginated
  listing lives at `GET /api/items`. The `:api` pipeline only negotiates the JSON
  format, which keeps the router directly dispatchable with `Plug.Test` — no
  endpoint required in front of it.
  """

  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", PaginatedListWeb do
    pipe_through :api

    get "/items", ItemController, :index
  end
end
</file>
<file path="priv/repo/migrations/20260713000000_create_items.exs">
defmodule PaginatedList.Repo.Migrations.CreateItems do
  @moduledoc """
  Creates the `items` table backing `PaginatedList.Item`.

  Timestamps use microsecond precision (`:utc_datetime_usec`) so that rows inserted
  in quick succession keep a stable, distinguishable ordering. An index on
  `(inserted_at, id)` matches the pagination query's `ORDER BY`.
  """

  use Ecto.Migration

  @doc """
  Creates the `items` table and its pagination index.
  """
  @spec change() :: any()
  def change do
    create table(:items) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:items, [:inserted_at, :id])
  end
end
</file>