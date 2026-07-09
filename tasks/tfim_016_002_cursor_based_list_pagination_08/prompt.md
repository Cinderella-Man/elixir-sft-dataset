# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule CursorPaginatorTest do
  use ExUnit.Case, async: false

  defp items(range) do
    for i <- range, do: %{id: i, name: "Item #{i}"}
  end

  test "default returns first window with default limit of 20" do
    %{data: data, meta: meta} = CursorPaginator.paginate(items(1..25))

    assert length(data) == 20
    assert Enum.map(data, & &1.id) == Enum.to_list(1..20)
    assert meta.page_size == 20
    assert meta.has_prev == false
    assert meta.has_next == true
    assert meta.prev_cursor == nil
    assert is_binary(meta.next_cursor)
  end

  test "orders by id ascending regardless of input order" do
    shuffled = Enum.shuffle(items(1..10))
    %{data: data} = CursorPaginator.paginate(shuffled, %{"limit" => "10"})
    assert Enum.map(data, & &1.id) == Enum.to_list(1..10)
  end

  test "forward navigation with next_cursor does not repeat items and covers all" do
    all = items(1..12)

    page1 = CursorPaginator.paginate(all, %{"limit" => "5"})
    assert Enum.map(page1.data, & &1.id) == [1, 2, 3, 4, 5]
    assert page1.meta.has_next
    assert page1.meta.has_prev == false

    page2 =
      CursorPaginator.paginate(all, %{"limit" => "5", "cursor" => page1.meta.next_cursor})

    assert Enum.map(page2.data, & &1.id) == [6, 7, 8, 9, 10]
    assert page2.meta.has_next
    assert page2.meta.has_prev

    page3 =
      CursorPaginator.paginate(all, %{"limit" => "5", "cursor" => page2.meta.next_cursor})

    assert Enum.map(page3.data, & &1.id) == [11, 12]
    assert page3.meta.has_next == false
    assert page3.meta.next_cursor == nil
    assert page3.meta.has_prev == true
  end

  test "backward navigation returns the preceding window in ascending order" do
    all = items(1..12)

    page3 =
      CursorPaginator.paginate(all, %{
        "limit" => "5",
        "cursor" => CursorPaginator.encode_cursor(10)
      })

    assert Enum.map(page3.data, & &1.id) == [11, 12]

    prev =
      CursorPaginator.paginate(all, %{
        "limit" => "5",
        "direction" => "prev",
        "cursor" => page3.meta.prev_cursor
      })

    assert Enum.map(prev.data, & &1.id) == [6, 7, 8, 9, 10]
    assert prev.meta.has_prev == true
    assert prev.meta.has_next == true
  end

  test "clamps limit to 100" do
    %{data: data, meta: meta} = CursorPaginator.paginate(items(1..150), %{"limit" => "500"})
    assert length(data) == 100
    assert meta.page_size == 100
  end

  test "non-numeric and sub-1 limits fall back to default" do
    %{meta: m1} = CursorPaginator.paginate(items(1..3), %{"limit" => "abc"})
    assert m1.page_size == 20

    %{meta: m2} = CursorPaginator.paginate(items(1..3), %{"limit" => "0"})
    assert m2.page_size == 20

    %{meta: m3} = CursorPaginator.paginate(items(1..3), %{"limit" => "-4"})
    assert m3.page_size == 20
  end

  test "malformed cursor is ignored and starts from the beginning" do
    # TODO
  end

  test "empty item list yields empty data and nil cursors" do
    %{data: data, meta: meta} = CursorPaginator.paginate([])
    assert data == []
    assert meta.has_next == false
    assert meta.has_prev == false
    assert meta.next_cursor == nil
    assert meta.prev_cursor == nil
  end

  test "cursor encode/decode round trips and rejects garbage" do
    encoded = CursorPaginator.encode_cursor(42)
    assert is_binary(encoded)
    assert CursorPaginator.decode_cursor(encoded) == {:ok, 42}
    assert CursorPaginator.decode_cursor("garbage***") == :error
    assert CursorPaginator.decode_cursor(123) == :error
  end
end
```
