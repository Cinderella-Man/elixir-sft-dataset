# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule AssertHelpers do
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  # ---------------------------------------------------------------------------
  # assert_next_message/2
  # ---------------------------------------------------------------------------

  defmacro assert_next_message(expected, timeout_ms \\ 1_000) do
    quote do
      AssertHelpers.next_message(unquote(expected), unquote(timeout_ms))
    end
  end

  def next_message(expected, timeout_ms \\ 1_000) do
    receive do
      msg ->
        if msg == expected do
          :ok
        else
          ExUnit.Assertions.flunk("""
          assert_next_message failed

            expected message: #{inspect(expected)}
            received message: #{inspect(msg)}
          """)
        end
    after
      timeout_ms ->
        ExUnit.Assertions.flunk("""
        assert_next_message timed out

          expected message: #{inspect(expected)}
          waited          : #{timeout_ms}ms
          no message arrived in the mailbox within the timeout
        """)
    end
  end

  # ---------------------------------------------------------------------------
  # assert_no_message/1
  # ---------------------------------------------------------------------------

  defmacro assert_no_message(within_ms \\ 100) do
    quote do
      AssertHelpers.no_message(unquote(within_ms))
    end
  end

  def no_message(within_ms \\ 100) do
    receive do
      msg ->
        ExUnit.Assertions.flunk("""
        assert_no_message failed

          expected no message within #{within_ms}ms
          but received: #{inspect(msg)}
        """)
    after
      within_ms -> :ok
    end
  end

  # ---------------------------------------------------------------------------
  # assert_process_exits/2
  # ---------------------------------------------------------------------------

  defmacro assert_process_exits(pid, timeout_ms \\ 1_000) do
    quote do
      AssertHelpers.process_exits(unquote(pid), unquote(timeout_ms))
    end
  end

  def process_exits(pid, timeout_ms \\ 1_000) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _object, _reason} ->
        :ok
    after
      timeout_ms ->
        Process.demonitor(ref, [:flush])

        ExUnit.Assertions.flunk("""
        assert_process_exits timed out

          process : #{inspect(pid)}
          alive?  : #{Process.alive?(pid)}
          waited  : #{timeout_ms}ms
          the process did not terminate within the timeout
        """)
    end
  end
end
```
