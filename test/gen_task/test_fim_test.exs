defmodule GenTask.TestFimTest do
  use ExUnit.Case, async: true

  alias GenTask.TestFim

  @harness """
  defmodule FooTest do
    use ExUnit.Case, async: false

    defp start, do: :ok

    test "first behaviour" do
      assert start() == :ok
    end

    test "second behaviour" do
      refute start() == :error
    end
  end
  """

  describe "test_blocks/1" do
    test "finds each top-level test block with its name and line span" do
      blocks = TestFim.test_blocks(@harness)
      assert length(blocks) == 2
      assert Enum.map(blocks, & &1.name) == ["first behaviour", "second behaviour"]

      # spans are start<=end and cover a `test "…" do … end` region
      for b <- blocks, do: assert(b.s < b.e)
    end

    test "ignores helper defps and the module header" do
      names = TestFim.test_blocks(@harness) |> Enum.map(& &1.name)
      refute Enum.any?(names, &(&1 =~ "start"))
    end

    test "ignores describe-nested tests (only top-level 2-space blocks are targets)" do
      h = """
      defmodule T do
        use ExUnit.Case

        describe "group" do
          test "nested one" do
            assert true
          end

          test "nested two" do
            assert true
          end
        end

        test "top level" do
          assert true
        end
      end
      """

      assert TestFim.test_blocks(h) |> Enum.map(& &1.name) == ["top level"]
    end
  end

  describe "asserting_block?/1 (bundle-parent gold gate)" do
    test "assert true is vacuous (the old regex passed it)" do
      refute TestFim.asserting_block?(~s(test "x" do\n  assert true\nend))
    end

    test "the word assert in a comment or string is not an assertion" do
      refute TestFim.asserting_block?("""
             test "x" do
               # assert later
               send(self(), "assert")
             end
             """)
    end

    test "assert on a real expression passes (no module ref needed — conn helpers)" do
      assert TestFim.asserting_block?("""
             test "x", %{conn: conn} do
               conn = get(conn, "/items")
               assert json_response(conn, 200)["data"] == []
             end
             """)
    end

    test "behavioral macros pass even with literal args" do
      assert TestFim.asserting_block?(~s(test "x" do\n  assert_receive :done, 100\nend))

      assert TestFim.asserting_block?(
               ~s[test "x" do\n  assert_raise ArgumentError, fn -> boom() end\nend]
             )
    end

    test "a later vacuous assert does not erase an earlier real one" do
      assert TestFim.asserting_block?(
               ~s[test "x" do\n  assert do_it() == :ok\n  assert true\nend]
             )
    end

    test "unparsable block is conservatively rejected" do
      refute TestFim.asserting_block?("test \"x\" do\n  assert (\nend")
    end
  end

  describe "prompt_md/2" do
    test "embeds the module and the harness skeleton in two elixir fences" do
      md =
        TestFim.prompt_md(
          "defmodule Mod do\n  def go, do: :ok\nend",
          "defmodule T do\n  # TODO\nend",
          "test",
          "tfim_x_01"
        )

      assert length(Regex.scan(~r/```elixir/, md)) == 2
      assert md =~ "def go, do: :ok"
      assert md =~ "# TODO"
    end
  end
end
