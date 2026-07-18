# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `parse_cursor` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me a self-contained Elixir module `CursorPaginator` that implements **cursor-based (keyset) pagination** — the pagination model used by large feeds and APIs where offset pagination is too expensive and unstable. This is the pagination core of a `GET /api/items` list endpoint, but implemented as a pure function over an in-memory list so it can be tested without a database.

I need the following:

- A function `paginate(items, params)` where `items` is a list of maps, each having at least an `:id` (integer) key, and `params` is a map with optional string keys as they would arrive from query params:
  - `"limit"` — page size. Default `20`. Clamp to a maximum of `100`. Values `< 1`, non-numeric, or not *fully* numeric (a value like `"12abc"` with trailing junk is rejected, not read as `12`) fall back to the default.
  - `"cursor"` — an **opaque** cursor string (see below). A missing cursor means start from the beginning. A malformed/undecodable cursor is treated gracefully as no cursor (start from the beginning) — it must NOT raise or return an error.
  - `"direction"` — `"next"` (default) or `"prev"`.

- Items are always ordered by `:id` ascending, regardless of the order of the input list.

- The result is a map `%{data: [...], meta: %{...}}` where `meta` contains exactly these five keys and no others (in particular, no `:total_count` or `:total_pages`):
  - `:page_size` — the effective limit.
  - `:next_cursor` — an opaque cursor pointing after the last returned item, or `nil` when there is nothing after the window.
  - `:prev_cursor` — an opaque cursor pointing before the first returned item, or `nil` when there is nothing before the window.
  - `:has_next` — boolean, whether items exist after the returned window.
  - `:has_prev` — boolean, whether items exist before the returned window.

- Forward paging (`"next"`) with cursor `c` returns the items with `id > c` (the first `limit` of them). Backward paging (`"prev"`) with cursor `c` returns the items with `id < c` — the LAST `limit` of them — still returned in ascending `:id` order.

- Unlike offset pagination there is **no** `total_count` or `total_pages`; correctness comes from the cursor boundary, so inserting/deleting rows between requests never skips or duplicates rows within a stable id ordering.

- Expose `encode_cursor(id)` and `decode_cursor(cursor)` as public helpers. The cursor must be opaque and URL-safe: it must contain only characters matching `[A-Za-z0-9_-]` (e.g. **unpadded** base64url of an internal representation — no `=` padding), must round-trip for any integer id (including `0`, negatives, and very large values), and must not embed the raw id as a literal substring. `decode_cursor/1` returns `{:ok, id}` for a valid cursor or `:error` for anything malformed; non-binary input (e.g. an integer) also returns `:error` rather than raising.

When `data` is empty, both cursors are `nil` and both booleans are `false`.

Use only the standard library. Give me the module in a single file.

## Additional interface contract

- `paginate/2`'s params argument is optional: `paginate(items)` must behave exactly like `paginate(items, %{})` (declare the second parameter with a `\\ %{}` default).

## The module with `parse_cursor` missing

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
    # TODO
  end

  defp parse_direction(%{"direction" => "prev"}), do: :prev
  defp parse_direction(_), do: :next

  # Only a fully numeric value counts: "12abc" has trailing junk and is rejected,
  # falling back to the default limit rather than silently reading as 12.
  defp parse_limit(%{"limit" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, ""} when n >= 1 -> min(n, @max_limit)
      _ -> @default_limit
    end
  end

  defp parse_limit(_), do: @default_limit
end
```

Give me only the complete implementation of `parse_cursor` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
