Implement the private `build_result/3` function. It takes the fully sorted list of
items (`sorted`), the selected page `window` (already the correct slice, in ascending
`:id` order), and the effective `limit`, and returns the final
`%{data: [...], meta: %{...}}` result map.

Provide two clauses:

  * When `window` is empty, return `data: []` with `meta` containing `page_size: limit`,
    `next_cursor: nil`, `prev_cursor: nil`, `has_next: false` and `has_prev: false`.

  * Otherwise, take the id of the first item in the window (`first_id`) and the id of
    the last item (`last_id`). Compute `has_prev` as whether any item in `sorted` has an
    id `< first_id`, and `has_next` as whether any item in `sorted` has an id `> last_id`.
    Return `data: window` with `meta` containing `page_size: limit`; `next_cursor` set to
    `encode_cursor(last_id)` when `has_next` is true (otherwise `nil`); `prev_cursor` set
    to `encode_cursor(first_id)` when `has_prev` is true (otherwise `nil`); and the
    `has_next` / `has_prev` booleans themselves.

```elixir
defmodule CursorPaginator do
  @moduledoc """
  Cursor-based (keyset) pagination over an in-memory list of `%{id: integer()}`
  maps. Ordering is by `:id` ascending. No total counts are exposed — navigation
  is entirely driven by opaque, URL-safe cursors.
  """

  @default_limit 20
  @max_limit 100

  @doc """
  Paginates `items` (a list of `%{id: integer()}` maps) using keyset pagination.

  `params` accepts optional string keys as they arrive from query params:

    * `"limit"` — page size, default `#{@default_limit}`, clamped to `#{@max_limit}`;
      values `< 1` or non-numeric fall back to the default.
    * `"cursor"` — an opaque cursor; missing or malformed means start from the start.
    * `"direction"` — `"next"` (default) or `"prev"`.

  Returns `%{data: [...], meta: %{...}}` with `meta` exposing `:page_size`,
  `:next_cursor`, `:prev_cursor`, `:has_next` and `:has_prev`.
  """
  @spec paginate([map()], map()) :: %{data: [map()], meta: map()}
  def paginate(items, params \\ %{}) when is_list(items) do
    limit = parse_limit(params)
    direction = parse_direction(params)
    cursor_id = parse_cursor(params)

    sorted = Enum.sort_by(items, & &1.id)

    window =
      case {direction, cursor_id} do
        {:next, nil} -> Enum.take(sorted, limit)
        {:next, c} -> sorted |> Enum.filter(&(&1.id > c)) |> Enum.take(limit)
        {:prev, nil} -> Enum.take(sorted, limit)
        {:prev, c} -> sorted |> Enum.filter(&(&1.id < c)) |> Enum.take(-limit)
      end

    build_result(sorted, window, limit)
  end

  defp build_result(_sorted, [], limit) do
    # TODO
  end

  defp build_result(sorted, window, limit) do
    # TODO
  end

  @doc """
  Encodes an integer `id` into an opaque, URL-safe cursor string.
  """
  @spec encode_cursor(integer()) :: binary()
  def encode_cursor(id), do: Base.url_encode64("id:#{id}", padding: false)

  @doc """
  Decodes an opaque cursor back into its id.

  Returns `{:ok, id}` for a valid cursor, or `:error` for anything malformed.
  """
  @spec decode_cursor(term()) :: {:ok, integer()} | :error
  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, bin} <- Base.url_decode64(cursor, padding: false),
         "id:" <> rest <- bin,
         {n, ""} <- Integer.parse(rest) do
      {:ok, n}
    else
      _ -> :error
    end
  end

  def decode_cursor(_), do: :error

  defp parse_cursor(%{"cursor" => raw}) when is_binary(raw) do
    case decode_cursor(raw) do
      {:ok, n} -> n
      :error -> nil
    end
  end

  defp parse_cursor(_), do: nil

  defp parse_direction(%{"direction" => "prev"}), do: :prev
  defp parse_direction(_), do: :next

  defp parse_limit(%{"limit" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> min(n, @max_limit)
      _ -> @default_limit
    end
  end

  defp parse_limit(_), do: @default_limit
end
```