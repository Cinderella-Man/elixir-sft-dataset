# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule EtsCatalog do
  @default_page 1
  @default_page_size 20
  @max_page_size 100

  def new do
    :ets.new(:ets_catalog, [:ordered_set, :public])
  end

  def insert(table, %{id: id} = item) do
    :ets.insert(table, {id, item})
    :ok
  end

  def count(table), do: :ets.info(table, :size)

  def list(table, params \\ %{}) do
    page_size = parse_page_size(params)
    requested = parse_page(params)

    all =
      table
      |> :ets.tab2list()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    total_count = length(all)
    total_pages = if total_count == 0, do: 0, else: ceil(total_count / page_size)

    current =
      cond do
        total_count == 0 -> 1
        requested > total_pages -> total_pages
        true -> requested
      end

    data =
      all
      |> Enum.drop((current - 1) * page_size)
      |> Enum.take(page_size)

    %{
      data: data,
      meta: %{
        requested_page: requested,
        current_page: current,
        page_size: page_size,
        total_count: total_count,
        total_pages: total_pages
      }
    }
  end

  defp parse_page(%{"page" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> n
      _ -> @default_page
    end
  end

  defp parse_page(_), do: @default_page

  defp parse_page_size(%{"page_size" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_), do: @default_page_size
end
```
