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
end
