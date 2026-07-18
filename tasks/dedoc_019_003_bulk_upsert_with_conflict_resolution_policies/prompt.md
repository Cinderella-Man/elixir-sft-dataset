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
defmodule Inventory do
  @policies [:replace, :merge, :skip]

  def start_link(_ \\ []) do
    Agent.start_link(fn -> %{records: %{}} end, name: __MODULE__)
  end

  def all, do: Agent.get(__MODULE__, fn %{records: r} -> Map.values(r) end)

  def count, do: Agent.get(__MODULE__, fn %{records: r} -> map_size(r) end)

  def get(sku), do: Agent.get(__MODULE__, fn %{records: r} -> Map.get(r, sku) end)

  def bulk_upsert(list, opts \\ []) do
    policy = Keyword.get(opts, :on_conflict, :replace)

    unless policy in @policies do
      raise ArgumentError,
            "invalid :on_conflict #{inspect(policy)}, expected one of #{inspect(@policies)}"
    end

    partial? = Keyword.get(opts, :partial, false)

    validations =
      list
      |> Enum.with_index()
      |> Enum.map(fn {attrs, i} -> {i, validate(attrs)} end)

    any_error? = Enum.any?(validations, fn {_, v} -> match?({:error, _}, v) end)

    if not partial? and any_error? do
      results =
        Enum.map(validations, fn
          {i, {:error, errs}} -> {i, :error, errs}
          {i, {:ok, _norm}} -> {i, :ok, :valid}
        end)

      {:error, results}
    else
      results =
        Enum.map(validations, fn
          {i, {:error, errs}} -> {i, :error, errs}
          {i, {:ok, norm}} -> apply_one(i, norm, policy)
        end)

      {:ok, results}
    end
  end

  # -- upsert application ---------------------------------------------------

  defp apply_one(i, norm, policy) do
    Agent.get_and_update(__MODULE__, fn %{records: recs} = st ->
      case Map.get(recs, norm.sku) do
        nil ->
          rec = %{sku: norm.sku, name: norm.name, price: norm.price, qty: norm.qty}
          {{i, :inserted, rec}, %{st | records: Map.put(recs, norm.sku, rec)}}

        existing ->
          case policy do
            :skip ->
              {{i, :skipped, existing}, st}

            :replace ->
              rec = %{sku: norm.sku, name: norm.name, price: norm.price, qty: norm.qty}
              {{i, :updated, rec}, %{st | records: Map.put(recs, norm.sku, rec)}}

            :merge ->
              rec = %{existing | name: norm.name, price: norm.price, qty: existing.qty + norm.qty}
              {{i, :updated, rec}, %{st | records: Map.put(recs, norm.sku, rec)}}
          end
      end
    end)
  end

  # -- validation -----------------------------------------------------------

  defp validate(attrs) do
    errors =
      %{}
      |> put_sku_error(attrs)
      |> put_name_error(attrs)
      |> put_price_error(attrs)
      |> put_qty_error(attrs)

    if map_size(errors) == 0 do
      {:ok,
       %{
         sku: attrs["sku"],
         name: attrs["name"],
         price: attrs["price"],
         qty: normalize_qty(Map.get(attrs, "qty"))
       }}
    else
      {:error, errors}
    end
  end

  defp put_sku_error(errors, attrs) do
    case attrs["sku"] do
      s when is_binary(s) and byte_size(s) > 0 -> errors
      _ -> Map.put(errors, "sku", ["can't be blank"])
    end
  end

  defp put_name_error(errors, attrs) do
    case attrs["name"] do
      n when is_binary(n) and byte_size(n) > 0 ->
        if String.length(n) <= 100,
          do: errors,
          else: Map.put(errors, "name", ["should be at most 100 character(s)"])

      _ ->
        Map.put(errors, "name", ["can't be blank"])
    end
  end

  defp put_price_error(errors, attrs) do
    case attrs["price"] do
      p when is_integer(p) and p > 0 -> errors
      _ -> Map.put(errors, "price", ["must be a positive integer"])
    end
  end

  defp put_qty_error(errors, attrs) do
    case Map.get(attrs, "qty") do
      nil -> errors
      q when is_integer(q) and q >= 0 -> errors
      _ -> Map.put(errors, "qty", ["must be a non-negative integer"])
    end
  end

  defp normalize_qty(nil), do: 0
  defp normalize_qty(q), do: q
end
```
