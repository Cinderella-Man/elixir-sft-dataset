# Implement `decode_cursor/2`

Implement the private `decode_cursor/2` function. It takes `params` (a string-keyed
map) and `field` (the sort field the current request is ordered by) and returns
`{:ok, decoded}` or `{:error, :invalid_cursor}`.

Behavior:

- Look up the `"cursor"` value in `params`. When it is missing (`nil`) or an empty
  string, there is no cursor to apply, so return `{:ok, nil}`.
- When it is a non-empty binary, treat it as an opaque token: Base64-url-decode it
  (with `padding: false`) and safely convert the resulting binary back to an Erlang
  term (use the `safe_to_term/1` helper, which decodes with the `:safe` option and
  never raises). A valid cursor decodes to a three-element tuple `{sort_field, value,
  id}`. The decoded `sort_field` must match the request's current `field`; on a
  successful match return `{:ok, {value, id}}` so the caller can slice strictly after
  that key.
- Any failure — a token that is not valid Base64-url, a binary that does not decode
  to the expected tuple shape, or a tuple whose encoded sort field differs from the
  current `field` — must produce `{:error, :invalid_cursor}`. A `"cursor"` value that
  is not a binary at all is likewise `{:error, :invalid_cursor}`.

This keeps cursors self-describing and prevents callers from paginating incoherently
across a different ordering than the one the cursor was produced under.

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
    with :ok <- validate_sort(params),
         {:ok, cursor} <- decode_cursor(params, sort_field(params)) do
      sorted =
        products
        |> Enum.filter(&matches?(&1, params))
        |> Enum.sort(sorter(params))

      after_cursor =
        case cursor do
          nil ->
            sorted

          key ->
            Enum.drop_while(sorted, fn p ->
              compare_key(order(params), key_of(p, params), key) != :after
            end)
        end

      limit = limit(params)
      page = Enum.take(after_cursor, limit)
      remaining = length(after_cursor) - length(page)

      next =
        if remaining > 0 and page != [] do
          encode_cursor(List.last(page), params)
        else
          nil
        end

      {:ok, %{data: Enum.map(page, &render/1), next_cursor: next, has_more: remaining > 0}}
    end
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
    # TODO
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