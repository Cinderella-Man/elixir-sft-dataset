# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule CursorPaginator do
  @default_limit 20
  @max_limit 100

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

  def encode_cursor(id), do: Base.url_encode64("id:#{id}", padding: false)

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
