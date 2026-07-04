# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
<file path="lib/paginated_list/item.ex">
defmodule PaginatedList.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "items" do
    field :name, :string

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
      add :name, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:items, [:inserted_at, :id])
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

  @default_page      1
  @default_page_size 20
  @max_page_size     100

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
    page      = parse_page(params)
    page_size = parse_page_size(params)
    offset    = (page - 1) * page_size

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
        page_size:    page_size,
        total_count:  total_count,
        total_pages:  total_pages
      }
    }
  end

  defp parse_page(%{"page" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> n
      _                  -> @default_page
    end
  end
  defp parse_page(_params), do: @default_page

  defp parse_page_size(%{"page_size" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> min(n, @max_page_size)
      _                  -> @default_page_size
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
        page_size:    meta.page_size,
        total_count:  meta.total_count,
        total_pages:  meta.total_pages
      }
    })
  end

  defp serialize_item(item) do
    %{
      id:          item.id,
      name:        item.name,
      inserted_at: DateTime.to_iso8601(item.inserted_at)
    }
  end
end
</file>

<file path="lib/paginated_list_web/router.ex">
defmodule PaginatedListWeb.Router do
  use PaginatedListWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", PaginatedListWeb do
    pipe_through :api

    get "/items", ItemController, :index
  end
end
</file>
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PaginatedListWeb.ItemControllerTest do
  use PaginatedListWeb.ConnCase, async: true

  alias PaginatedList.{Repo, Item}

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp seed_items(n) do
    now = DateTime.utc_now()

    entries =
      for i <- 1..n do
        %{
          name: "Item #{String.pad_leading(Integer.to_string(i), 4, "0")}",
          inserted_at: DateTime.add(now, i, :second),
          updated_at: DateTime.add(now, i, :second)
        }
      end

    {^n, items} = Repo.insert_all(Item, entries, returning: true)
    items
  end

  # -------------------------------------------------------
  # Default pagination (no params)
  # -------------------------------------------------------

  test "returns first page with default page_size when no params given", %{conn: conn} do
    seed_items(25)

    conn = get(conn, "/api/items")
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 20
    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
    assert meta["total_count"] == 25
    assert meta["total_pages"] == 2
  end

  # -------------------------------------------------------
  # Custom page and page_size
  # -------------------------------------------------------

  test "respects page and page_size params", %{conn: conn} do
    seed_items(15)

    conn = get(conn, "/api/items", %{"page" => "2", "page_size" => "5"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 5
    assert meta["current_page"] == 2
    assert meta["page_size"] == 5
    assert meta["total_count"] == 15
    assert meta["total_pages"] == 3
  end

  test "last page returns only remaining items", %{conn: conn} do
    seed_items(12)

    conn = get(conn, "/api/items", %{"page" => "3", "page_size" => "5"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 2
    assert meta["current_page"] == 3
    assert meta["total_pages"] == 3
  end

  # -------------------------------------------------------
  # page_size clamping
  # -------------------------------------------------------

  test "clamps page_size to 100 when a larger value is given", %{conn: conn} do
    seed_items(150)

    conn = get(conn, "/api/items", %{"page_size" => "500"})
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert length(data) == 100
    assert meta["page_size"] == 100
    assert meta["total_count"] == 150
    assert meta["total_pages"] == 2
  end

  # -------------------------------------------------------
  # Page beyond total
  # -------------------------------------------------------

  test "returns empty data when page exceeds total_pages", %{conn: conn} do
    # TODO
  end

  # -------------------------------------------------------
  # Empty database
  # -------------------------------------------------------

  test "returns empty data and zero total_pages when no items exist", %{conn: conn} do
    conn = get(conn, "/api/items")
    assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

    assert data == []
    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
    assert meta["total_count"] == 0
    assert meta["total_pages"] == 0
  end

  # -------------------------------------------------------
  # Deterministic ordering
  # -------------------------------------------------------

  test "items are returned in deterministic order", %{conn: conn} do
    seed_items(10)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"data" => data} = json_response(conn, 200)

    names = Enum.map(data, & &1["name"])
    assert names == Enum.sort(names)
  end

  # -------------------------------------------------------
  # JSON shape
  # -------------------------------------------------------

  test "each item in data has the required fields", %{conn: conn} do
    seed_items(1)

    conn = get(conn, "/api/items")
    assert %{"data" => [item]} = json_response(conn, 200)

    assert Map.has_key?(item, "id")
    assert Map.has_key?(item, "name")
    assert Map.has_key?(item, "inserted_at")
  end

  # -------------------------------------------------------
  # Invalid / edge-case params
  # -------------------------------------------------------

  test "page_size of 0 or negative is treated as default", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page_size" => "0"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["page_size"] == 20

    conn = get(conn, "/api/items", %{"page_size" => "-5"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["page_size"] == 20
  end

  test "page of 0 or negative is treated as page 1", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page" => "0"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["current_page"] == 1

    conn = get(conn, "/api/items", %{"page" => "-3"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["current_page"] == 1
  end

  test "non-numeric params fall back to defaults", %{conn: conn} do
    seed_items(5)

    conn = get(conn, "/api/items", %{"page" => "abc", "page_size" => "xyz"})
    assert %{"meta" => meta} = json_response(conn, 200)

    assert meta["current_page"] == 1
    assert meta["page_size"] == 20
  end

  # -------------------------------------------------------
  # Pagination math: total_pages correctness
  # -------------------------------------------------------

  test "total_pages is correct for exact divisions", %{conn: conn} do
    seed_items(20)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["total_pages"] == 2
  end

  test "total_pages rounds up for non-exact divisions", %{conn: conn} do
    seed_items(21)

    conn = get(conn, "/api/items", %{"page_size" => "10"})
    assert %{"meta" => meta} = json_response(conn, 200)
    assert meta["total_pages"] == 3
  end

  # -------------------------------------------------------
  # Pagination window correctness
  # -------------------------------------------------------

  test "page 2 does not repeat items from page 1", %{conn: conn} do
    seed_items(10)

    conn1 = get(conn, "/api/items", %{"page" => "1", "page_size" => "5"})
    conn2 = get(conn, "/api/items", %{"page" => "2", "page_size" => "5"})

    %{"data" => page1} = json_response(conn1, 200)
    %{"data" => page2} = json_response(conn2, 200)

    page1_ids = MapSet.new(page1, & &1["id"])
    page2_ids = MapSet.new(page2, & &1["id"])

    assert MapSet.disjoint?(page1_ids, page2_ids)
    assert MapSet.size(page1_ids) == 5
    assert MapSet.size(page2_ids) == 5
  end
end
```
