defmodule GenTask.FimSkeletonTest do
  use ExUnit.Case, async: true

  alias GenTask.Fim

  @parent """
  defmodule Calc do
    @moduledoc "demo"

    def add(a, b), do: a + b

    def scale(x, f) do
      mul(x, f)
    end

    defp mul(a, b), do: a * b
  end
  """

  defp prompt_with(skeleton) do
    """
    Implement `scale/2`.

    ```elixir
    #{skeleton}
    ```
    """
  end

  @faithful_skeleton """
  defmodule Calc do
    @moduledoc "demo"

    def add(a, b), do: a + b

    def scale(x, f) do
      # TODO
    end

    defp mul(a, b), do: a * b
  end
  """

  # add/2 quietly rewritten outside the hole — the promoted prompt would falsely
  # claim every other function is intact.
  @tampered_skeleton """
  defmodule Calc do
    @moduledoc "demo"

    def add(a, b), do: a + b + 1

    def scale(x, f) do
      # TODO
    end

    defp mul(a, b), do: a * b
  end
  """

  # mul/1 dropped entirely.
  @dropped_fn_skeleton """
  defmodule Calc do
    @moduledoc "demo"

    def add(a, b), do: a + b

    def scale(x, f) do
      # TODO
    end
  end
  """

  describe "skeleton_matches_parent?/3" do
    test "a faithful hand-written skeleton passes" do
      assert Fim.skeleton_matches_parent?(prompt_with(@faithful_skeleton), @parent, "scale/2")
    end

    test "a skeleton that rewrites a function outside the hole is rejected" do
      refute Fim.skeleton_matches_parent?(prompt_with(@tampered_skeleton), @parent, "scale/2")
    end

    test "a skeleton that drops a function is rejected" do
      refute Fim.skeleton_matches_parent?(prompt_with(@dropped_fn_skeleton), @parent, "scale/2")
    end

    test "a prompt without a TODO fence is rejected" do
      refute Fim.skeleton_matches_parent?("no fence here", @parent, "scale/2")
    end

    test "an unparsable skeleton is rejected" do
      refute Fim.skeleton_matches_parent?(
               prompt_with("defmodule Calc do\n  def broken(\n  # TODO\nend"),
               @parent,
               "scale/2"
             )
    end
  end
end
