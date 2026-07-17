# Task 17 — Fill in the Middle: `search/2`

Implement the public `search/2` function for `Catalog.KeysetSearch`. Every other
function in the module (validation, filtering, sorting, key comparison, cursor
encoding/decoding, and rendering helpers) is already provided — your job is to
wire them together into the paginated search pipeline.

`search/2` takes a list of product maps and a string-keyed `params` map and must:

1. First **validate the sort field** with `validate_sort/1`; if it fails, return
   its `{:error, :invalid_sort_field}` unchanged.
2. Then **decode the cursor** with `decode_cursor/2`, passing `params` and the
   current sort field (`sort_field/1`). This yields `{:ok, nil}` when no cursor is
   present, `{:ok, {value, id}}` for a valid cursor, or `{:error, :invalid_cursor}`
   (which must be returned unchanged). Use a `with` chain so either error short-circuits.
3. **Filter** the products with `matches?/2`, then **sort** them with the comparator
   from `sorter/1`.
4. Apply the cursor by keeping only items that fall **strictly after** it: when the
   decoded cursor is `nil`, keep the whole sorted list; otherwise `Enum.drop_while/2`
   over the sorted list, dropping every product whose key
   (`compare_key(order(params), key_of(p, params), key)`) is not `:after` the cursor
   key — i.e. drop until you reach the first item strictly after the cursor.
5. **Take** at most `limit(params)` items as the page, and compute how many items
   `remaining` beyond the page (length of the post-cursor list minus the page length).
6. Compute `next_cursor`: when `remaining > 0` and the page is non-empty, encode a
   fresh cursor from the **last item on the page** via `encode_cursor/2`; otherwise `nil`.
7. Return `{:ok, %{data: ..., next_cursor: ..., has_more: ...}}` where `data` is the
   page mapped through `render/1`, and `has_more` is `remaining > 0`.

```elixir
defmodule Catalog.KeysetSearch do
  @moduledoc """
  Searches, filters, sorts, and paginates an in-memory product catalog using
  keyset (cursor) pagination.

  The module operates over a list of product maps of the shape

      %{id: 3, name: "Wireless Mouse", category: "electronics", price_cents: 2999}

  and never returns the whole result set: callers receive one page at a time
  plus an opaque cursor that encodes the last item of the page under the
  current ordering. Prices are handled as integer cents to preserve precision
  and are rendered as two-decimal dollar strings on the way out.
  """

  @allowed_sort ~w(name price id)
  @default_limit 3
  @max_limit 100

  @typedoc "A product record in the catalog."
  @type product :: %{
          required(:id) => integer(),
          required(:name) => String.t(),
          required(:category) => String.t(),
          required(:price_cents) => integer()
        }

  @typedoc "A single rendered item on a page."
  @type item :: %{
          id: integer(),
          name: String.t(),
          category: String.t(),
          price: String.t()
        }

  @typedoc "A successful page of results."
  @type page :: %{
          data: [item()],
          next_cursor: String.t() | nil,
          has_more: boolean()
        }

  @doc """
  Searches, filters, sorts, and paginates `products` according to `params`.

  `params` is a string-keyed map (like decoded query params) supporting
  `"name"`, `"category"`, `"min_price"`, `"max_price"`, `"sort"`, `"order"`,
  `"limit"`, and `"cursor"`.

  Returns `{:ok, page}` on success, `{:error, :invalid_sort_field}` when the
  requested sort field is not allowed, or `{:error, :invalid_cursor}` when the
  supplied cursor is malformed, carries a wrongly typed payload, or was
  produced under a different sort.
  """
  @spec search([product()], map()) ::
          {:ok, page()} | {:error, :invalid_sort_field | :invalid_cursor}
  def search(products, params \\ %{}) when is_list(products) and is_map(params) do
    # TODO
  end

  # -- Sort validation ------------------------------------------------------

  defp validate_sort(%{"sort" => s}) when s not in @allowed_sort,
    do: {:error, :invalid_sort_field}

  defp validate_sort(_), do: :ok

  defp sort_field(params), do: Map.get(params, "sort", "id")

  defp order(params) do
    case Map.get(params, "order") do
      "desc" -> :desc
      _ -> :asc
    end
  end

  defp limit(params) do
    case Map.get(params, "limit") do
      nil ->
        @default_limit

      v when is_integer(v) ->
        clamp(v)

      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, ""} -> clamp(n)
          _ -> @default_limit
        end

      _ ->
        @default_limit
    end
  end

  defp clamp(n) when n < 1, do: @default_limit
  defp clamp(n) when n > @max_limit, do: @max_limit
  defp clamp(n), do: n

  # -- Filtering ------------------------------------------------------------

  defp matches?(p, params) do
    name_match?(p, params) and category_match?(p, params) and price_match?(p, params)
  end

  defp name_match?(p, %{"name" => n}) when is_binary(n) and n != "" do
    String.contains?(String.downcase(p.name), String.downcase(n))
  end

  defp name_match?(_, _), do: true

  defp category_match?(p, %{"category" => c}) when is_binary(c) and c != "" do
    p.category == c
  end

  defp category_match?(_, _), do: true

  defp price_match?(p, params) do
    min_ok =
      case parse_price(Map.get(params, "min_price")) do
        {:ok, cents} -> p.price_cents >= cents
        :error -> true
      end

    max_ok =
      case parse_price(Map.get(params, "max_price")) do
        {:ok, cents} -> p.price_cents <= cents
        :error -> true
      end

    min_ok and max_ok
  end

  defp parse_price(nil), do: :error
  defp parse_price(v) when is_integer(v), do: {:ok, v}

  defp parse_price(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_price(_), do: :error

  # -- Sorting / keys -------------------------------------------------------

  defp sorter(params) do
    ord = order(params)

    fn a, b ->
      compare_key(ord, key_of(a, params), key_of(b, params)) != :after
    end
  end

  defp key_of(p, params), do: {sort_value(p, sort_field(params)), p.id}

  defp sort_value(p, "name"), do: p.name
  defp sort_value(p, "price"), do: p.price_cents
  defp sort_value(p, "id"), do: p.id

  defp compare_key(:asc, {v1, id1}, {v2, id2}) do
    cond do
      v1 < v2 -> :before
      v1 > v2 -> :after
      id1 < id2 -> :before
      id1 > id2 -> :after
      true -> :eq
    end
  end

  defp compare_key(:desc, {v1, id1}, {v2, id2}) do
    cond do
      v1 > v2 -> :before
      v1 < v2 -> :after
      id1 > id2 -> :before
      id1 < id2 -> :after
      true -> :eq
    end
  end

  # -- Cursor ---------------------------------------------------------------

  defp encode_cursor(p, params) do
    {value, id} = key_of(p, params)

    {sort_field(params), value, id}
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  defp decode_cursor(params, field) do
    case Map.get(params, "cursor") do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      c when is_binary(c) ->
        with {:ok, bin} <- Base.url_decode64(c, padding: false),
             {:ok, {^field, value, id}} <- safe_to_term(bin),
             true <- valid_key?(field, value, id) do
          {:ok, {value, id}}
        else
          _ -> {:error, :invalid_cursor}
        end

      _ ->
        {:error, :invalid_cursor}
    end
  end

  # The decoded payload is untrusted: its value must have the exact type the
  # sort field produces, otherwise Erlang's cross-type term ordering would
  # silently slice the page instead of failing loudly.
  defp valid_key?("name", value, id), do: is_binary(value) and is_integer(id)
  defp valid_key?("price", value, id), do: is_integer(value) and is_integer(id)
  defp valid_key?("id", value, id), do: is_integer(value) and is_integer(id) and value == id
  defp valid_key?(_, _, _), do: false

  defp safe_to_term(bin) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    _ -> :error
  end

  # -- Rendering ------------------------------------------------------------

  defp render(p) do
    %{id: p.id, name: p.name, category: p.category, price: format_price(p.price_cents)}
  end

  defp format_price(cents) do
    "#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"
  end
end
```