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
<file path="lib/my_app/catalog/item.ex">
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
</file>

<file path="lib/my_app/catalog.ex">
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
</file>

<file path="lib/my_app_web/controllers/bulk_item_controller.ex">
defmodule MyAppWeb.BulkItemController do
  use MyAppWeb, :controller

  alias MyApp.Catalog

  def create(conn, %{"items" => items}) when is_list(items) do
    conn = fetch_query_params(conn)

    if conn.query_params["partial"] == "true" do
      create_partial(conn, items)
    else
      create_all_or_nothing(conn, items)
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{"error" => "expected a list of items"})
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
</file>

<file path="lib/my_app_web/router.ex">
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
</file>

<file path="priv/repo/migrations/20240101000000_create_items.exs">
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
</file>
```

## New specification

Write me a self-contained Elixir context module `Inventory` that performs a **bulk upsert** into an in-memory store keyed by a unique `"sku"`, with configurable conflict-resolution policies and per-item, index-aware result reporting.

This is a variation on a create-only bulk endpoint: here each item either **inserts** (new sku) or **updates** (existing sku), and the caller chooses how updates combine with the existing record.

**Store**
- Back the module with a named `Agent` started via `Inventory.start_link/0` (registered under the module name).
- Provide `Inventory.all/0`, `Inventory.count/0`, and `Inventory.get/1` (by sku).
- Each stored record is `%{sku: String.t(), name: String.t(), price: integer, qty: integer}`.

**Input shape**
- Each attribute map: `"sku"` (required, non-empty), `"name"` (required, 1–100 chars), `"price"` (required integer > 0), `"qty"` (optional non-negative integer, default `0`).

**`Inventory.bulk_upsert(list_of_attrs, opts \\ [])`**
- `opts[:on_conflict]` (default `:replace`) selects the update policy; anything other than `:replace | :merge | :skip` raises `ArgumentError`.
  - `:replace` — an existing sku is overwritten with the incoming record (qty = incoming qty).
  - `:merge` — an existing sku keeps its identity; `name`/`price` take the incoming values and `qty` **accumulates** (`existing.qty + incoming.qty`). This makes stock-receiving batches additive.
  - `:skip` — an existing sku is left untouched and reported as skipped.
- Processing is **in order**, so a repeated sku *within the same batch* is treated as a conflict against the running state (e.g., two `:merge` entries for the same sku accumulate).
- `opts[:partial]` (default `false`) selects the failure mode.
- Result tuples carry the zero-based input index: `{index, :inserted, record}`, `{index, :updated, record}`, `{index, :skipped, record}`, or `{index, :error, errors_map}`.
- The `errors_map` is keyed by the offending field's **string** name exactly as it appears in the input attrs, and each value is a list of human-readable message strings — e.g. `%{"name" => ["can't be blank"]}`.
- **Default (all-or-nothing):** if any item fails validation, write nothing and return `{:error, results}` where valid items appear as `{index, :ok, :valid}` and invalid ones as `{index, :error, errors}`. Otherwise apply all items in order and return `{:ok, results}`.
- **`partial: true`:** apply every valid item in order (insert/update/skip per policy and existence), report invalid items as errors, and return `{:ok, results}`.

Use only Elixir/OTP standard library — no external dependencies.
