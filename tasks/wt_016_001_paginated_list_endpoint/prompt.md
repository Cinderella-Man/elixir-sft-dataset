# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me a Phoenix controller module called `PaginatedListWeb.ItemController` that serves a `GET /api/items` endpoint returning paginated results from an Ecto schema.

I need the following pieces:

- An Ecto schema `PaginatedList.Item` backed by an `items` table with at minimum `:name` (string) and `:inserted_at` (utc_datetime_usec) fields. Include a basic migration to create the table.

- A context module `PaginatedList.Items` with a function `list_items(params)` that accepts a map with optional `"page"` and `"page_size"` string keys (as they come from query params). It should default `page` to 1 and `page_size` to 20. If `page_size` exceeds 100, clamp it to 100. If `page` or `page_size` are less than 1, default them to 1 and 20 respectively. The function must return a map with `:data` (the list of items for that page), `:meta` containing `:current_page`, `:page_size`, `:total_count`, and `:total_pages`. Items should be ordered by `inserted_at` ascending then by `id` ascending for deterministic ordering.

- A controller `PaginatedListWeb.ItemController` with an `index/2` action that reads `page` and `page_size` from `conn.params`, calls the context, and renders the JSON response. The JSON shape must be exactly:
  ```json
  {
    "data": [{"id": 1, "name": "...", "inserted_at": "..."}],
    "meta": {
      "current_page": 1,
      "page_size": 20,
      "total_count": 50,
      "total_pages": 3
    }
  }
  ```

- A JSON view or `Phoenix.Controller.json/2` call to render the response — either approach is fine.

- A router scope that mounts the endpoint at `/api/items`.

`total_pages` must be computed as `ceil(total_count / page_size)`. When there are zero items, `total_pages` should be 0. When the requested page is beyond `total_pages`, return an empty `data` list but still include correct metadata.

Use only standard Phoenix/Ecto — no external pagination libraries. Give me all the modules in separate files.
## Additional interface contract

- Use exactly these module names: router `PaginatedListWeb.Router`, schema `PaginatedList.Item`, repo `PaginatedList.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The schema must also have an `:updated_at` field (utc_datetime_usec): test fixtures are bulk-inserted with `Repo.insert_all(Item, entries, returning: true)` where each entry sets `:name`, `:inserted_at`, and `:updated_at`.
- The tests dispatch requests straight to `PaginatedListWeb.Router` with `Plug.Test` (no endpoint in front), so `GET /api/items` must be servable by the router pipeline alone.

## Module under test

```elixir
<file path="lib/paginated_list/item.ex">
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
</file>

<file path="priv/repo/migrations/20240101000000_create_items.exs">
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
</file>

<file path="lib/paginated_list/items.ex">
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
    page = parse_page(params)
    page_size = parse_page_size(params)
    offset = (page - 1) * page_size

    base_query = from(i in Item, order_by: [asc: i.inserted_at, asc: i.id])

    total_count = Repo.aggregate(base_query, :count, :id)
    total_pages = compute_total_pages(total_count, page_size)

    items =
      base_query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    %{
      data: items,
      meta: %{
        current_page: page,
        page_size: page_size,
        total_count: total_count,
        total_pages: total_pages
      }
    }
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
</file>

<file path="lib/paginated_list_web/controllers/item_controller.ex">
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
</file>

<file path="lib/paginated_list_web/router.ex">
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
</file>
```
