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

Write me an Elixir Phoenix JSON API endpoint at `POST /api/items/bulk` that accepts a JSON array of items to create, validates each item independently, and reports per-item success or failure with position indices.

I need the following pieces:

**Schema & Validation (`MyApp.Catalog.Item`):**
- Fields: `name` (string, required, 1–255 chars), `price` (integer, required, must be > 0), `description` (string, optional, max 1000 chars).
- Standard Ecto schema with a `changeset/2` function enforcing those validations.
- Timestamps.

**Context module (`MyApp.Catalog`):**
- `bulk_create_items(list_of_attrs, opts \\ [])` — takes a list of attribute maps and an options keyword list.
- When `partial: true` is **not** in opts (the default), wrap everything in a single `Repo.transaction`. If any item fails validation, roll back the entire transaction and return `{:error, results}` where `results` is a list of `{index, :ok, item}` or `{index, :error, changeset}` tuples. No rows should be inserted.
- When `partial: true` is in opts, insert each valid item individually (still inside a transaction per item for safety) and skip invalid ones. Return `{:ok, results}` with the same tuple format. Valid items are persisted; invalid ones are not.
- In both modes every entry in the results list must include the zero-based position index from the original input so the caller knows exactly which items succeeded or failed.

**Controller (`MyAppWeb.BulkItemController`):**
- `create/2` action handling `POST /api/items/bulk`.
- Read the `partial` query param (`?partial=true`). Anything other than the literal string `"true"` means all-or-nothing mode.
- Request body shape: `{"items": [ {…}, {…}, … ]}`. If the `"items"` key is missing or is not a list, return 400 with `{"error": "expected a list of items"}`.
- On all-or-nothing success: respond 201 with `{"status": "all_created", "items": [...]}` where each entry has `"index"`, `"id"`, `"name"`, `"price"`, `"description"`.
- On all-or-nothing failure: respond 422 with `{"status": "all_failed", "errors": [...]}` where each failed entry has `"index"` and `"errors"` (a map of field → list of messages), and each successful validation still appears with `"index"` and `"valid": true` (but nothing was inserted).
- On partial mode: respond 201 with `{"status": "partial", "created": [...], "errors": [...]}`. `created` holds the successfully inserted items with their indices; `errors` holds the failures with indices and per-field error messages.

**Router:** Mount the route as `post "/api/items/bulk", BulkItemController, :create` inside an `/api` scope with the `:api` pipeline.

Give me the complete modules in separate files. Use only Phoenix, Ecto, and standard library — no external dependencies. Assume a Postgres repo at `MyApp.Repo` already exists and is configured.

## Additional interface contract

- Module names: router `MyAppWeb.Router`, schema `MyApp.Catalog.Item`, repo `MyApp.Repo` (provided, already configured and started, by the test environment). The tests dispatch requests straight to `MyAppWeb.Router` with `Plug.Test` and parse the JSON request body with `Plug.Parsers` (no endpoint in front).

## Module under test

```elixir
<file path="lib/my_app/catalog/item.ex">
defmodule MyApp.Catalog.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "items" do
    field :name, :string
    field :price, :integer
    field :description, :string

    timestamps()
  end

  @doc "Validates a catalog item: name 1-255 chars, price integer > 0, optional description <= 1000 chars."
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
    plug :accepts, ["json"]
  end

  scope "/api", MyAppWeb do
    pipe_through :api

    post "/items/bulk", BulkItemController, :create
  end
end
</file>

<file path="priv/repo/migrations/20240101000000_create_items.exs">
defmodule MyApp.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add :name, :string, null: false
      add :price, :integer, null: false
      add :description, :text

      timestamps()
    end
  end
end
</file>
```
