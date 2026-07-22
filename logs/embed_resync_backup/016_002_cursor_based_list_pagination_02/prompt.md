Implement the public `paginate/2` function. It takes `items` (a list of `%{id: integer()}` maps) and an optional `params` map of string-keyed query params, and returns a `%{data: [...], meta: %{...}}` result using keyset pagination.

Start by deriving the three effective inputs from `params` using the provided helpers: `parse_limit/1` for the page size, `parse_direction/1` for the `:next`/`:prev` direction, and `parse_cursor/1` for the decoded cursor id (which is `nil` when the cursor is missing or malformed).

Sort `items` by `:id` ascending — the input order must not matter. Then select the window of items based on `{direction, cursor_id}`:

  * `{:next, nil}` — take the first `limit` items from the start.
  * `{:next, c}` — keep only items with `id > c`, then take the first `limit` of them.
  * `{:prev, nil}` — take the first `limit` items from the start.
  * `{:prev, c}` — keep only items with `id < c`, then take the LAST `limit` of them (so the result is still in ascending `:id` order).

Finally, delegate to `build_result/3` with the sorted list, the selected window, and the effective limit to assemble the `%{data: ..., meta: ...}` map. Keep the `when is_list(items)` guard.

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
    # TODO
  end

  defp build_result(_sorted, [], limit) do
    %{
      data: [],
      meta: %{
        page_size: limit,
        next_cursor: nil,
        prev_cursor: nil,
        has_next: false,
        has_prev: false
      }
    }
  end

  defp build_result(sorted, window, limit) do
    first_id = hd(window).id
    last_id = List.last(window).id
    has_prev = Enum.any?(sorted, &(&1.id < first_id))
    has_next = Enum.any?(sorted, &(&1.id > last_id))

    %{
      data: window,
      meta: %{
        page_size: limit,
        next_cursor: if(has_next, do: encode_cursor(last_id), else: nil),
        prev_cursor: if(has_prev, do: encode_cursor(first_id), else: nil),
        has_next: has_next,
        has_prev: has_prev
      }
    }
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