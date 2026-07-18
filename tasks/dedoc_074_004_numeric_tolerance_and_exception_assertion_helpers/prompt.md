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
defmodule AssertHelpers do
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  # ---------------------------------------------------------------------------
  # assert_within_pct/3
  # ---------------------------------------------------------------------------

  defmacro assert_within_pct(actual, expected, pct) do
    quote bind_quoted: [actual: actual, expected: expected, pct: pct] do
      allowed = abs(expected) * (pct / 100)
      diff = abs(actual - expected)

      actual_pct =
        if expected == 0 do
          if actual == 0, do: +0.0, else: :infinity
        else
          diff / abs(expected) * 100
        end

      unless diff <= allowed do
        ExUnit.Assertions.flunk("""
        assert_within_pct failed

          actual          : #{inspect(actual)}
          expected        : #{inspect(expected)}
          difference      : #{inspect(diff)}
          allowed (±#{pct}%) : #{inspect(allowed)}
          actual delta    : #{inspect(actual_pct)}%
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # assert_monotonic/2
  # ---------------------------------------------------------------------------

  defmacro assert_monotonic(list, direction \\ :increasing) do
    quote bind_quoted: [list: list, direction: direction] do
      items = Enum.to_list(list)

      case AssertHelpers.__first_non_monotonic__(items, direction) do
        :ok ->
          :ok

        {:violation, index, a, b} ->
          ExUnit.Assertions.flunk("""
          assert_monotonic (#{direction}) failed

            sequence is not strictly #{direction}
            violation at index #{index}:
              element #{index}     : #{inspect(a)}
              element #{index + 1} : #{inspect(b)}
            full sequence: #{inspect(items)}
          """)
      end
    end
  end

  # Public so the macro-generated `quote` block can call it from any module.
  def __first_non_monotonic__(items, direction) do
    items
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {[a, b], i} ->
      ok? =
        case direction do
          :increasing -> a < b
          :decreasing -> a > b
        end

      if ok?, do: false, else: {:violation, i, a, b}
    end)
  end

  # ---------------------------------------------------------------------------
  # assert_raises_message/3
  # ---------------------------------------------------------------------------

  defmacro assert_raises_message(exception, needle, fun) do
    quote bind_quoted: [exception: exception, needle: needle, fun: fun] do
      result =
        try do
          fun.()
          {:no_raise, nil}
        rescue
          e -> {:raised, e}
        end

      case result do
        {:no_raise, _} ->
          ExUnit.Assertions.flunk("""
          assert_raises_message failed

            expected #{inspect(exception)} to be raised
            but no exception was raised
          """)

        {:raised, e} ->
          cond do
            not is_struct(e, exception) ->
              ExUnit.Assertions.flunk("""
              assert_raises_message failed

                expected exception: #{inspect(exception)}
                actual exception  : #{inspect(e.__struct__)}
                message           : #{inspect(Exception.message(e))}
              """)

            not (Exception.message(e) =~ needle) ->
              ExUnit.Assertions.flunk("""
              assert_raises_message failed

                exception #{inspect(exception)} was raised as expected
                but its message did not contain the expected text
                expected substring: #{inspect(needle)}
                actual message    : #{inspect(Exception.message(e))}
              """)

            true ->
              :ok
          end
      end
    end
  end
end
```
