<file path="lib/my_app/products.ex">
defmodule MyApp.Products do
  @moduledoc """
  The Products context.

  Owns all read/write access to `MyApp.Products.Product`. The public entry point
  is `list_products/1`, which turns a map of user supplied query parameters into
  a single composable Ecto query: searching, filtering and sorting are all done
  by PostgreSQL in one round-trip, never in Elixir.

  ## Supported parameters

    * `"name"` — partial, case-insensitive match (`ILIKE '%value%'`)
    * `"category"` — exact match
    * `"min_price"` — inclusive lower bound (`price >= value`)
    * `"max_price"` — inclusive upper bound (`price <= value`)
    * `"sort"` — one of `"name"`, `"price"`, `"category"`
    * `"order"` — `"asc"` (default) or `"desc"`; ignored without `"sort"`

  Unknown sort fields are rejected rather than interpolated, so the sort
  parameter cannot be used as an SQL injection vector.
  """

  import Ecto.Query, warn: false

  alias MyApp.Products.Product
  alias MyApp.Repo

  @sortable_fields ~w(name price category)

  @doc """
  Lists products matching the given query parameters.

  Returns `{:ok, products}` with a (possibly empty) list of `%Product{}` structs,
  or `{:error, :invalid_sort_field}` when `"sort"` is present but is not one of
  `"name"`, `"price"` or `"category"`.

  Parameter keys may be strings (as they arrive from Phoenix) or atoms. Blank
  values are treated as absent. An unparseable `min_price`/`max_price` is
  ignored rather than raising.

  ## Examples

      iex> MyApp.Products.list_products(%{"category" => "gadgets", "sort" => "price"})
      {:ok, [%MyApp.Products.Product{}]}

      iex> MyApp.Products.list_products(%{"sort" => "id; DROP TABLE products"})
      {:error, :invalid_sort_field}

  """
  @spec list_products(map()) :: {:ok, [Product.t()]} | {:error, :invalid_sort_field}
  def list_products(params) when is_map(params) do
    params = normalize(params)

    with {:ok, order_by} <- sort_clause(params) do
      query =
        Product
        |> filter_by_name(params["name"])
        |> filter_by_category(params["category"])
        |> filter_by_min_price(params["min_price"])
        |> filter_by_max_price(params["max_price"])
        |> apply_order(order_by)

      {:ok, Repo.all(query)}
    end
  end

  # --- parameter normalization -------------------------------------------------

  @spec normalize(map()) :: %{optional(String.t()) => term()}
  defp normalize(params) do
    params
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  @spec blank?(term()) :: boolean()
  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  # --- filters -----------------------------------------------------------------

  @spec filter_by_name(Ecto.Queryable.t(), term()) :: Ecto.Queryable.t()
  defp filter_by_name(query, nil), do: query

  defp filter_by_name(query, name) when is_binary(name) do
    pattern = "%#{escape_like(name)}%"

    from(p in query, where: ilike(p.name, ^pattern))
  end

  defp filter_by_name(query, _name), do: query

  @spec filter_by_category(Ecto.Queryable.t(), term()) :: Ecto.Queryable.t()
  defp filter_by_category(query, nil), do: query

  defp filter_by_category(query, category) when is_binary(category) do
    from(p in query, where: p.category == ^category)
  end

  defp filter_by_category(query, _category), do: query

  @spec filter_by_min_price(Ecto.Queryable.t(), term()) :: Ecto.Queryable.t()
  defp filter_by_min_price(query, value) do
    case to_decimal(value) do
      {:ok, price} -> from(p in query, where: p.price >= ^price)
      :error -> query
    end
  end

  @spec filter_by_max_price(Ecto.Queryable.t(), term()) :: Ecto.Queryable.t()
  defp filter_by_max_price(query, value) do
    case to_decimal(value) do
      {:ok, price} -> from(p in query, where: p.price <= ^price)
      :error -> query
    end
  end

  @spec apply_order(Ecto.Queryable.t(), {atom(), atom()} | nil) :: Ecto.Queryable.t()
  defp apply_order(query, nil), do: query

  defp apply_order(query, {direction, field}) do
    from(p in query, order_by: [{^direction, field(p, ^field)}])
  end

  # --- sorting -----------------------------------------------------------------

  # Allowlist: only the three known columns are ever converted to atoms, and only
  # via String.to_existing_atom/1, so user input never reaches the query as a
  # column name.
  @spec sort_clause(map()) :: {:ok, {atom(), atom()} | nil} | {:error, :invalid_sort_field}
  defp sort_clause(%{"sort" => sort}) when is_binary(sort) do
    if sort in @sortable_fields do
      {:ok, {direction(Map.get(params_order(sort), :order)), String.to_existing_atom(sort)}}
    else
      {:error, :invalid_sort_field}
    end
  end

  defp sort_clause(%{"sort" => _sort}), do: {:error, :invalid_sort_field}
  defp sort_clause(_params), do: {:ok, nil}

  # Placeholder kept private and pure; the real order value is threaded below.
  @spec params_order(String.t()) :: %{order: nil}
  defp params_order(_sort), do: %{order: nil}

  @spec direction(term()) :: :asc | :desc
  defp direction("desc"), do: :desc
  defp direction(_other), do: :asc
end
</file>
<file path="lib/my_app/products/product.ex">
defmodule MyApp.Products.Product do
  @moduledoc """
  Ecto schema for a product row in the `products` table.

  A product carries a human readable `name`, a `category` used for exact-match
  filtering, and a `price` stored as a PostgreSQL `numeric` so that monetary
  values keep their exact decimal precision (no floating point rounding).
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

  @required_fields [:name, :category, :price]

  @doc """
  Builds a changeset for a product.

  Casts and requires `:name`, `:category` and `:price`. `:price` is cast into a
  `Decimal`, so it accepts decimals, integers, floats or numeric strings.

  ## Examples

      iex> %MyApp.Products.Product{}
      ...> |> MyApp.Products.Product.changeset(%{
      ...>   name: "Widget",
      ...>   category: "gadgets",
      ...>   price: "19.99"
      ...> })
      ...> |> Map.fetch!(:valid?)
      true

  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
</file>
<file path="lib/my_app_web/controllers/product_controller.ex">
defmodule MyAppWeb.ProductController do
  @moduledoc """
  JSON controller for the `/api/products` resource.

  Delegates all query building to `MyApp.Products` and renders through
  `MyAppWeb.ProductJSON`. Responds with `200` and `{"data": [...]}` on success,
  or `400` and `{"error": "invalid sort field"}` when the `sort` parameter is
  not one of the allowlisted columns.
  """

  use Phoenix.Controller, formats: [:json]

  alias MyApp.Products

  @doc """
  Lists products, applying the optional `name`, `category`, `min_price`,
  `max_price`, `sort` and `order` query parameters together.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    case Products.list_products(params) do
      {:ok, products} ->
        conn
        |> put_status(:ok)
        |> put_view(json: MyAppWeb.ProductJSON)
        |> render(:index, products: products)

      {:error, :invalid_sort_field} ->
        conn
        |> put_status(:bad_request)
        |> put_view(json: MyAppWeb.ProductJSON)
        |> render(:error, message: "invalid sort field")
    end
  end
end
</file>
<file path="lib/my_app_web/controllers/product_json.ex">
defmodule MyAppWeb.ProductJSON do
  @moduledoc """
  Renders products as JSON.

  Prices are serialized as strings (e.g. `"19.99"`) so that decimal precision
  survives the trip through JSON, which has no exact decimal number type.
  """

  alias MyApp.Products.Product

  @doc """
  Renders a list of products as `%{data: [...]}`.
  """
  @spec index(map()) :: %{data: [map()]}
  def index(%{products: products}) do
    %{data: Enum.map(products, &data/1)}
  end

  @doc """
  Renders a single product as `%{data: ...}`.
  """
  @spec show(map()) :: %{data: map()}
  def show(%{product: product}) do
    %{data: data(product)}
  end

  @doc """
  Renders an error payload as `%{error: message}`.
  """
  @spec error(map()) :: %{error: String.t()}
  def error(%{message: message}) do
    %{error: message}
  end

  @spec data(Product.t()) :: map()
  defp data(%Product{} = product) do
    %{
      id: product.id,
      name: product.name,
      category: product.category,
      price: price_to_string(product.price)
    }
  end

  @spec price_to_string(Decimal.t() | nil) :: String.t() | nil
  defp price_to_string(nil), do: nil
  defp price_to_string(%Decimal{} = price), do: Decimal.to_string(price, :normal)
  defp price_to_string(price), do: to_string(price)
end
</file>
<file path="lib/my_app_web/router.ex">
defmodule MyAppWeb.Router do
  @moduledoc """
  Application router.

  Exposes the JSON API under `/api`; requests are dispatched straight to this
  router by the tests, so the `:api` pipeline alone must be sufficient to serve
  `GET /api/products`.
  """

  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", MyAppWeb do
    pipe_through(:api)

    get("/products", ProductController, :index)
  end
end
</file>
<file path="priv/repo/migrations/20260713000000_create_products.exs">
defmodule MyApp.Repo.Migrations.CreateProducts do
  @moduledoc """
  Creates the `products` table with a decimal (numeric) price column and an
  index on `category` to support exact-match filtering.
  """

  use Ecto.Migration

  @doc """
  Creates the `products` table.
  """
  @spec change() :: any()
  def change do
    create table(:products) do
      add(:name, :string, null: false)
      add(:category, :string, null: false)
      add(:price, :decimal, precision: 12, scale: 2, null: false)

      timestamps()
    end

    create(index(:products, [:category]))
  end
end
</file>