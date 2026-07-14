# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

# Task 17 — V2: Faceted Search with Multi-Value Filters and Facet Counts

Write me a self-contained Elixir context module `Catalog.Faceted` that implements **faceted search** over a product catalog: multi-value (OR) category filters, multi-tag (AND) filters, and — the defining feature — **facet counts** returned alongside the results so a UI can render "drill-down" filters without dead-ends.

To keep the module dependency-free and autotestable it operates over an **in-memory list of product maps**. Each product is:

```elixir
%{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999, tags: ["wireless", "office"]}
```

Prices are stored as **integer cents** (no floats, no Decimal).

## Public API

Implement `Catalog.Faceted.search(products, params)` returning:

- `{:ok, %{data: [...], facets: %{categories: %{...}, tags: %{...}}, total: integer}}`, or
- `{:error, :invalid_sort_field}`.

`params` is a string-keyed map.

## Filtering

- **`"name"`** — partial, case-insensitive substring match on the name.
- **`"categories"`** — a **list** of category strings; a product matches if its category is **any** of them (OR). Absent/empty list ⇒ no category constraint.
- **`"tags"`** — a **list** of tag strings; a product matches only if it contains **all** of them (AND). Absent/empty list ⇒ no tag constraint.
- **`"min_price"` / `"max_price"`** — inclusive integer-cent string bounds; unparseable/blank values are ignored.

`total` is the count of products passing **all** filters, and `data` is that same fully-filtered set (sorted).

## Facet counts (the key semantics)

Each facet reports how many products **would** match if the caller added values to *that* facet, so a facet's own selection must **not** constrain its own counts, while **every other** active filter still applies:

- **`facets.categories`** — a map of `category => count` computed over products passing every filter **except** the `"categories"` filter.
- **`facets.tags`** — a map of `tag => count` (each product contributes to one entry per tag it carries) computed over products passing every filter **except** the `"tags"` filter.

So selecting a category must not zero-out the other categories in `facets.categories` (the user can still widen the OR), but selecting a tag *does* shrink `facets.categories`, because the tag filter is a "different" filter that still applies. Facets never include entries with a zero count.

## Sorting

- **`"sort"`** — allowlist of exactly `"name"`, `"price"`, `"id"`, `"category"`. Any other value ⇒ `{:error, :invalid_sort_field}`. Absent ⇒ defaults to `"id"`.
- **`"order"`** — `"asc"` (default) or `"desc"`; ties broken by `id` in the same direction.

## Response format

Each item in `data` is `%{id, name, category, price, tags}` where `price` is a two-decimal dollar string. An empty result returns `data: []`, `total: 0`, and facets reflecting the remaining source sets.

## Constraints

- Pure Elixir, standard library only. No Ecto/Decimal/Phoenix.
- Facet counts must be computed by excluding exactly the corresponding facet's own filter and no other.

## Additional interface contract

- `search/2`'s params argument is optional: `search(products)` must behave exactly like `search(products, %{})` (declare the second parameter with a `\\ %{}` default).
