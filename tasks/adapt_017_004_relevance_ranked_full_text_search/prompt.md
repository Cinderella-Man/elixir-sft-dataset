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

# Task 17 — V3: Relevance-Ranked Full-Text Search

Write me a self-contained Elixir context module `Catalog.Ranked` that searches a product catalog by **free-text relevance**: it tokenizes a query, scores each product across weighted fields (name weighted higher than description), and orders results by that relevance score — replacing the base task's simple `ILIKE` substring filter with an actual ranking algorithm.

To keep the module dependency-free and autotestable it operates over an **in-memory list of product maps**. Each product is:

```elixir
%{id: 1, name: "Running Shoes", description: "Lightweight shoes for running and trail",
  category: "footwear", price_cents: 8999}
```

Prices are stored as **integer cents** (no floats, no Decimal).

## Public API

Implement `Catalog.Ranked.search(products, params)` returning:

- `{:ok, %{data: [...]}}`, or
- `{:error, :invalid_sort_field}`.

`params` is a string-keyed map. Each `data` item is `%{id, name, category, price, score}` where `price` is a two-decimal dollar string and `score` is the computed integer relevance score.

## Search & scoring

- **`"q"`** — the free-text query. Tokenize by downcasing and splitting on any run of non-alphanumeric characters (so `"Running, shoes!"` ⇒ `["running", "shoes"]`).
- Tokenize each product's `name` and `description` the same way.
- **Prefix matching**: a query token matches a document token when the document token **starts with** the query token (so `"run"` matches `"running"`, and `"work"` matches `"workouts"`).
- **Score** = for each query token, `3 × (number of name tokens it prefix-matches) + 1 × (number of description tokens it prefix-matches)`, summed over all query tokens. Name matches are weighted 3×; multiple matches accumulate.
- When `"q"` is present and non-empty, **only products with a score greater than 0 are returned** (it acts as the search filter). When `"q"` is absent or empty, all products pass with score `0`.

## Pre-filters (applied before scoring)

- **`"category"`** — exact match.
- **`"min_price"` / `"max_price"`** — inclusive integer-cent string bounds; unparseable/blank ignored.

## Sorting

- **`"sort"`** — allowlist of exactly `"relevance"`, `"name"`, `"price"`. Any other value ⇒ `{:error, :invalid_sort_field}`. Absent ⇒ defaults to `"relevance"`.
- **`"order"`** — `"asc"` or `"desc"`.
  - For `"relevance"`, the default direction is **descending** (highest score first); an explicit `"asc"` reverses it. Ties broken by `name` ascending, then `id` ascending.
  - For `"name"` / `"price"`, the default is ascending; ties broken by `id` ascending.

## Constraints

- Pure Elixir, standard library only. No Ecto/Decimal/Phoenix.
- Scoring, prefix matching, field weighting, and ordering all happen inside the module.
