Implement the `create/2` controller action for `MyAppWeb.BulkItemController`, the
Phoenix action behind `POST /api/items/bulk`.

It must have two clauses:

1. A clause matching `%{"items" => items}` **guarded by `is_list(items)`**. Call
   `fetch_query_params/1` on the connection first, then look at
   `conn.query_params["partial"]`. If it is exactly the string `"true"`, delegate to
   the private `create_partial/2` helper; for any other value (including a missing
   param) delegate to `create_all_or_nothing/2`.

2. A fallback clause matching any other params — this covers a missing `"items"` key
   or an `"items"` value that is not a list. It must respond with status `400` and the
   JSON body `%{"error" => "expected a list of items"}` using `put_status/2` and
   `json/2`.

`create/2` itself does no persistence and does no JSON shaping: all of that lives in
the private helpers (`create_partial/2`, `create_all_or_nothing/2`, `item_json/1`,
`result_json/1`, `error_json/2`), which are already written.

```elixir
defmodule MyApp.Catalog.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "items" do
    field(:name, :string)
    field(:price, :integer)
    field(:description, :string)

    timestamps()
  end

  @doc """
  Validates a catalog item: name 1-255 chars, price integer > 0, optional
  description <= 1000 chars.
  """
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :price, :description])
    |> validate_required([:name, :price])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:price, greater_than: 0)
    |> validate_length(:description, max: 1000)
  end
end

defmodule MyApp.Catalog do
  @moduledoc """
  Catalog context. Bulk item creation with per-item, index-aware result reporting.
  """

  alias MyApp.Repo
  alias MyApp.Catalog.Item

  @doc """
  Bulk-create items from a list of attribute maps.

  Each entry in the returned `results` list is a 3-tuple carrying the zero-based
  position index from the original input: `{index, :ok, item}` or
  `{index, :error, changeset}`.

  Modes:
    * default (all-or-nothing) — wraps everything in a single `Repo.transaction`.
      If any item is invalid the whole transaction rolls back and
      `{:error, results}` is returned; no rows are inserted.
    * `partial: true` — inserts each valid item individually (each inside its own
      transaction) and skips invalid ones, returning `{:ok, results}`.
  """
  @spec bulk_create_items([map()], keyword()) ::
          {:ok, [{non_neg_integer(), :ok | :error, term()}]}
          | {:error, [{non_neg_integer(), :ok | :error, term()}]}
  def bulk_create_items(list_of_attrs, opts \\ []) do
    if Keyword.get(opts, :partial, false) do
      partial_create(list_of_attrs)
    else
      all_or_nothing(list_of_attrs)
    end
  end

  defp all_or_nothing(list_of_attrs) do
    Repo.transaction(fn ->
      results = insert_each(list_of_attrs)

      if Enum.any?(results, fn {_index, status, _} -> status == :error end) do
        Repo.rollback(results)
      else
        results
      end
    end)
  end

  defp partial_create(list_of_attrs) do
    results =
      list_of_attrs
      |> Enum.with_index()
      |> Enum.map(fn {attrs, index} ->
        outcome =
          Repo.transaction(fn ->
            case insert_item(attrs) do
              {:ok, item} -> item
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

        case outcome do
          {:ok, item} -> {index, :ok, item}
          {:error, changeset} -> {index, :error, changeset}
        end
      end)

    {:ok, results}
  end

  defp insert_each(list_of_attrs) do
    list_of_attrs
    |> Enum.with_index()
    |> Enum.map(fn {attrs, index} ->
      case insert_item(attrs) do
        {:ok, item} -> {index, :ok, item}
        {:error, changeset} -> {index, :error, changeset}
      end
    end)
  end

  defp insert_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end
end

defmodule MyAppWeb.BulkItemController do
  use MyAppWeb, :controller

  alias MyApp.Catalog

  def create(conn, %{"items" => items}) when is_list(items) do
    # TODO
  end

  defp create_all_or_nothing(conn, items) do
    case Catalog.bulk_create_items(items) do
      {:ok, results} ->
        conn
        |> put_status(201)
        |> json(%{"status" => "all_created", "items" => Enum.map(results, &item_json/1)})

      {:error, results} ->
        conn
        |> put_status(422)
        |> json(%{"status" => "all_failed", "errors" => Enum.map(results, &result_json/1)})
    end
  end

  defp create_partial(conn, items) do
    {:ok, results} = Catalog.bulk_create_items(items, partial: true)

    created = for {index, :ok, item} <- results, do: item_json({index, :ok, item})
    errors = for {index, :error, changeset} <- results, do: error_json(index, changeset)

    conn
    |> put_status(201)
    |> json(%{"status" => "partial", "created" => created, "errors" => errors})
  end

  # Successful validation but nothing inserted (all-or-nothing failure): mark valid.
  defp result_json({index, :ok, _item}), do: %{"index" => index, "valid" => true}
  defp result_json({index, :error, changeset}), do: error_json(index, changeset)

  defp item_json({index, :ok, item}) do
    %{
      "index" => index,
      "id" => item.id,
      "name" => item.name,
      "price" => item.price,
      "description" => item.description
    }
  end

  defp error_json(index, changeset) do
    %{"index" => index, "errors" => translate_errors(changeset)}
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", MyAppWeb do
    pipe_through(:api)

    post("/items/bulk", BulkItemController, :create)
  end
end

defmodule MyApp.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add(:name, :string, null: false)
      add(:price, :integer, null: false)
      add(:description, :text)

      timestamps()
    end
  end
end
```