# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

```elixir
<file path="priv/repo/migrations/20260402000000_create_products.exs">
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add(:name, :string, null: false)
      add(:category, :string, null: false)
      add(:price, :numeric, null: false)

      timestamps()
    end

    create(index(:products, [:category]))
    create(index(:products, [:price]))
  end
end
</file>

<file path="lib/my_app/products/product.ex">
defmodule MyApp.Products.Product do
  @moduledoc """
  Ecto schema for a catalog product: a `name`, a `category`, and a non-negative
  `price`, plus insertion/update timestamps.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          category: String.t() | nil,
          price: Decimal.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "products" do
    field(:name, :string)
    field(:category, :string)
    field(:price, :decimal)

    timestamps()
  end

  @required_fields ~w(name category price)a

  @doc """
  Builds a changeset casting `name`, `category`, and `price`, requiring all three
  and enforcing a non-negative price.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end
end
</file>

<file path="lib/my_app/products.ex">
defmodule MyApp.Products do
  @moduledoc """
  The Products context: read-side querying of the catalog with optional
  case-insensitive name search, exact category filtering, a price range, and
  sorting on a whitelisted set of fields.
  """

  import Ecto.Query

  alias MyApp.Repo
  alias MyApp.Products.Product

  @allowed_sort_fields ~w(name price category)

  @doc """
  Lists products matching the string-keyed `params` map.

  Supported keys: `"name"` (case-insensitive substring), `"category"` (exact),
  `"min_price"`/`"max_price"` (inclusive bounds), and `"sort"` + `"order"`
  (`"asc"`/`"desc"`) over #{Enum.join(@allowed_sort_fields, ", ")}.

  Returns `{:ok, products}`, or `{:error, :invalid_sort_field}` when `"sort"` is
  not one of the allowed fields.
  """
  @spec list_products(map()) :: {:ok, [Product.t()]} | {:error, :invalid_sort_field}
  def list_products(params) when is_map(params) do
    case validate_sort(params) do
      {:error, _} = err ->
        err

      :ok ->
        products =
          Product
          |> filter_by_name(params)
          |> filter_by_category(params)
          |> filter_by_min_price(params)
          |> filter_by_max_price(params)
          |> apply_sorting(params)
          |> Repo.all()

        {:ok, products}
    end
  end

  defp validate_sort(%{"sort" => field}) when field not in @allowed_sort_fields do
    {:error, :invalid_sort_field}
  end

  defp validate_sort(_params), do: :ok

  defp filter_by_name(query, %{"name" => name}) when is_binary(name) and name != "" do
    wildcard = "%" <> name <> "%"
    where(query, [p], ilike(p.name, ^wildcard))
  end

  defp filter_by_name(query, _params), do: query

  defp filter_by_category(query, %{"category" => category})
       when is_binary(category) and category != "" do
    where(query, [p], p.category == ^category)
  end

  defp filter_by_category(query, _params), do: query

  defp filter_by_min_price(query, %{"min_price" => min}) when is_binary(min) and min != "" do
    case Decimal.parse(min) do
      {decimal, ""} -> where(query, [p], p.price >= ^decimal)
      _ -> query
    end
  end

  defp filter_by_min_price(query, _params), do: query

  defp filter_by_max_price(query, %{"max_price" => max}) when is_binary(max) and max != "" do
    case Decimal.parse(max) do
      {decimal, ""} -> where(query, [p], p.price <= ^decimal)
      _ -> query
    end
  end

  defp filter_by_max_price(query, _params), do: query

  defp apply_sorting(query, %{"sort" => field} = params) when field in @allowed_sort_fields do
    direction =
      case Map.get(params, "order", "asc") do
        "desc" -> :desc
        _ -> :asc
      end

    sort_atom = String.to_existing_atom(field)
    order_by(query, [p], [{^direction, field(p, ^sort_atom)}])
  end

  defp apply_sorting(query, _params), do: query
end
</file>

<file path="lib/my_app_web/controllers/product_controller.ex">
defmodule MyAppWeb.ProductController do
  @moduledoc """
  JSON endpoint for listing products. Delegates filtering/sorting to the
  `MyApp.Products` context and renders via `MyAppWeb.ProductJSON`.
  """

  use MyAppWeb, :controller

  alias MyApp.Products

  @doc "GET /api/products — renders the filtered list, or 400 on an invalid sort field."
  def index(conn, params) do
    case Products.list_products(params) do
      {:ok, products} ->
        conn
        |> put_status(:ok)
        |> json(MyAppWeb.ProductJSON.index(%{products: products}))

      {:error, :invalid_sort_field} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid sort field"})
    end
  end
end
</file>

<file path="lib/my_app_web/controllers/product_json.ex">
defmodule MyAppWeb.ProductJSON do
  @moduledoc "Serializes products into the `%{data: [...]}` JSON response shape."

  alias MyApp.Products.Product

  @doc "Renders the product list as `%{data: [product_map]}`."
  def index(%{products: products}) do
    %{data: Enum.map(products, &product/1)}
  end

  defp product(%Product{} = p) do
    %{
      id: p.id,
      name: p.name,
      category: p.category,
      price: Decimal.to_string(p.price)
    }
  end
end
</file>

<file path="lib/my_app_web/router.ex">
defmodule MyAppWeb.Router do
  @moduledoc false
  use MyAppWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", MyAppWeb do
    pipe_through(:api)

    get("/products", ProductController, :index)
  end
end
</file>
```

## New specification

# Task 17 — V1: Keyset (Cursor) Pagination Search

Write me a self-contained Elixir context module `Catalog.KeysetSearch` that searches, filters, sorts, and **paginates** a product catalog using **keyset (cursor) pagination** instead of returning the whole result set.

To keep the module dependency-free and autotestable, it operates over an **in-memory list of product maps** rather than a live database. Each product is a map:

```elixir
%{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999}
```

Prices are stored as **integer cents** to preserve precision (no floats, no Decimal).

## Public API

Implement `Catalog.KeysetSearch.search(products, params)` where `products` is a list of the maps above and `params` is a string-keyed map (like decoded query params). It returns:

- `{:ok, %{data: [...], next_cursor: cursor_or_nil, has_more: boolean}}` on success, or
- `{:error, :invalid_sort_field}` / `{:error, :invalid_cursor}` on failure.

## Filtering (all applied together when present)

- **`"name"`** — partial, case-insensitive substring match on the product name.
- **`"category"`** — exact match on the category field.
- **`"min_price"`** — inclusive lower bound, an integer-cents string (e.g. `"1000"` = $10.00). Unparseable/blank values are ignored.
- **`"max_price"`** — inclusive upper bound, integer-cents string. Unparseable/blank values are ignored.

## Sorting

- **`"sort"`** — allowlist of exactly `"name"`, `"price"`, `"id"`. Any other value ⇒ `{:error, :invalid_sort_field}`. Absent ⇒ defaults to `"id"`.
- **`"order"`** — `"asc"` (default) or `"desc"`.
- Sorting is **stable and total**: ties on the sort field are broken by `id` in the same direction as `order`.

## Keyset pagination

- **`"limit"`** — page size (integer or integer string). Default `3`, clamped to a max of `100`; non-positive/garbage falls back to the default.
- **`"cursor"`** — an **opaque** token. When present, the page contains only the items that fall **strictly after** the cursor in the current ordering (by `(sort_value, id)`), never using numeric offsets.
- `next_cursor` is a fresh opaque token derived from the **last item on the returned page**, or `nil` when no further items remain. `has_more` reflects whether items remain beyond this page.
- The cursor must encode the **sort field** it was produced under. If a cursor is presented alongside a *different* `sort`, return `{:error, :invalid_cursor}`. A structurally malformed cursor is also `{:error, :invalid_cursor}`. A cursor whose decoded payload carries a value of the wrong type for its sort field (e.g. a non-integer where price cents or an id are expected) is likewise `{:error, :invalid_cursor}`, rather than being trusted to slice the page. This prevents callers from paginating incoherently across mismatched orderings.

## Response format

Each item in `data` is `%{id: ..., name: ..., category: ..., price: ...}` where `price` is a dollar string like `"29.99"` (cents formatted with two decimal places). An empty page returns `%{data: [], next_cursor: nil, has_more: false}`.

## Constraints

- Pure Elixir, standard library only. No Ecto, no Decimal, no Phoenix.
- Cursors must be self-describing and validated (do not trust arbitrary decoded content).
- Filtering, sorting, and cursor slicing must all be handled in the module — the caller passes params and gets a page back.
