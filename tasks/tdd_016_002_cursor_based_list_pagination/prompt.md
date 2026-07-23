# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

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
    %{data: data} =
      CursorPaginator.paginate(items(1..10), %{"limit" => "3", "cursor" => "!!!not-valid"})

    assert Enum.map(data, & &1.id) == [1, 2, 3]
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

  test "window emptied by a cursor past the last id yields nil cursors and false booleans" do
    all = items(1..5)

    %{data: data, meta: meta} =
      CursorPaginator.paginate(all, %{
        "limit" => "3",
        "cursor" => CursorPaginator.encode_cursor(5)
      })

    assert data == []
    assert meta.next_cursor == nil
    assert meta.prev_cursor == nil
    assert meta.has_next == false
    assert meta.has_prev == false
  end

  test "meta never exposes total_count or total_pages on any page" do
    all = items(1..12)

    page1 = CursorPaginator.paginate(all, %{"limit" => "5"})
    page2 = CursorPaginator.paginate(all, %{"limit" => "5", "cursor" => page1.meta.next_cursor})
    empty = CursorPaginator.paginate([])

    for %{meta: meta} <- [page1, page2, empty] do
      refute Map.has_key?(meta, :total_count)
      refute Map.has_key?(meta, :total_pages)

      assert Map.keys(meta) |> Enum.sort() ==
               [:has_next, :has_prev, :next_cursor, :page_size, :prev_cursor]
    end
  end

  test "rows inserted and deleted between requests neither skip nor duplicate the next window" do
    page1 = CursorPaginator.paginate(items(1..10), %{"limit" => "3"})
    assert Enum.map(page1.data, & &1.id) == [1, 2, 3]

    mutated =
      items(1..10)
      |> Enum.reject(&(&1.id == 2))
      |> then(&[%{id: 0, name: "Item 0"} | &1])
      |> Enum.shuffle()

    page2 =
      CursorPaginator.paginate(mutated, %{"limit" => "3", "cursor" => page1.meta.next_cursor})

    assert Enum.map(page2.data, & &1.id) == [4, 5, 6]
  end

  test "limit with trailing non-numeric characters falls back to the default" do
    %{data: data, meta: meta} = CursorPaginator.paginate(items(1..30), %{"limit" => "12abc"})

    assert meta.page_size == 20
    assert length(data) == 20
  end

  test "encoded cursors contain only url-safe characters for varied ids" do
    for id <- [0, 1, -7, 42, 1_000_000, 9_007_199_254_740_993] do
      cursor = CursorPaginator.encode_cursor(id)
      assert cursor =~ ~r/\A[A-Za-z0-9_-]+\z/
      assert CursorPaginator.decode_cursor(cursor) == {:ok, id}
    end

    cursor = CursorPaginator.encode_cursor(123)
    refute cursor =~ "123"
  end

  test "single-arity paginate matches the two-arity call with an empty params map" do
    all = Enum.shuffle(items(1..25))

    assert CursorPaginator.paginate(all) == CursorPaginator.paginate(all, %{})
    assert CursorPaginator.paginate([]) == CursorPaginator.paginate([], %{})
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
