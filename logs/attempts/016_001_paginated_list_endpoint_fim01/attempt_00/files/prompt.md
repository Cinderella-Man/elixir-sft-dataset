Implement the public `list_items/1` function in the `PaginatedList.Items` context.

It takes a params map (query params, so keys are strings and values are strings)
which may contain optional `"page"` and `"page_size"` keys, and it defaults to an
empty map when called with no arguments.

It must:

- Parse the requested page with `parse_page/1` and the requested page size with
  `parse_page_size/1` (both are already provided: they default `page` to 1 and
  `page_size` to 20, clamp `page_size` to a maximum of 100, and fall back to the
  defaults for unparseable or out-of-range values).
- Compute the offset for offset-based pagination from the page and page size.
- Build a base query over `PaginatedList.Item` ordered by `inserted_at` ascending
  and then `id` ascending, so ordering is deterministic.
- Compute `total_count` with `Repo.aggregate/3` (counting `:id`) over that base
  query, and derive `total_pages` using the provided `compute_total_pages/2`
  (which yields 0 when there are no items and `ceil(total_count / page_size)`
  otherwise).
- Fetch the page of items by applying `limit/2` and `offset/2` to the base query
  and running it through `Repo.all/1`. A page beyond the last page must simply
  come back as an empty list.
- Return a map with `:data` (the list of items for that page) and `:meta`, a map
  containing `:current_page`, `:page_size`, `:total_count`, and `:total_pages`.

```elixir
defmodule PaginatedList.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "items" do
    field(:name, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end

defmodule PaginatedList.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add(:name, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:items, [:inserted_at, :id]))
  end
end

defmodule PaginatedList.Items do
  @moduledoc """
  Context for managing Items with offset pagination.
  """

  import Ecto.Query, warn: false

  alias PaginatedList.Item
  alias PaginatedList.Repo

  @default_page 1
  @default_page_size 20
  @max_page_size 100

  @spec list_items(map()) :: %{
          data: [Item.t()],
          meta: %{
            current_page: pos_integer(),
            page_size: pos_integer(),
            total_count: non_neg_integer(),
            total_pages: non_neg_integer()
          }
        }
  def list_items(params \\ %{}) do
    # TODO
  end

  defp parse_page(%{"page" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> n
      _ -> @default_page
    end
  end

  defp parse_page(_params), do: @default_page

  defp parse_page_size(%{"page_size" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_params), do: @default_page_size

  defp compute_total_pages(0, _page_size), do: 0
  defp compute_total_pages(total_count, page_size), do: ceil(total_count / page_size)
end

defmodule PaginatedListWeb.ItemController do
  use PaginatedListWeb, :controller

  alias PaginatedList.Items

  def index(conn, params) do
    %{data: items, meta: meta} = Items.list_items(params)

    json(conn, %{
      data: Enum.map(items, &serialize_item/1),
      meta: %{
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_count: meta.total_count,
        total_pages: meta.total_pages
      }
    })
  end

  defp serialize_item(item) do
    %{
      id: item.id,
      name: item.name,
      inserted_at: DateTime.to_iso8601(item.inserted_at)
    }
  end
end

defmodule PaginatedListWeb.Router do
  use PaginatedListWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", PaginatedListWeb do
    pipe_through(:api)

    get("/items", ItemController, :index)
  end
end
```