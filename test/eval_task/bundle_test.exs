defmodule EvalTask.BundleTest do
  use ExUnit.Case, async: true
  alias EvalTask.Bundle

  @good ~s(<file path="lib/a.ex">\ndefmodule A do\n  def x, do: 1\nend\n</file>\n<file path="priv/repo/migrations/1_c.exs">\ndefmodule M do\n  use Ecto.Migration\nend\n</file>)

  test "bundle? detects <file> blocks" do
    assert Bundle.bundle?(@good)
    refute Bundle.bundle?("defmodule A do\nend")
  end

  test "parse returns {path, contents} in order" do
    assert [{"lib/a.ex", a}, {"priv/repo/migrations/1_c.exs", _}] = Bundle.parse(@good)
    assert a =~ "defmodule A"
  end

  test "validate accepts a well-formed bundle" do
    assert :ok = Bundle.validate(Bundle.parse(@good))
  end

  test "validate rejects a fragment (.ex with no module)" do
    frag =
      ~s(<file path="lib/router.ex">\n# Add inside your :api scope\nscope "/x" do\nend\n</file>)

    assert {:error, msg} = Bundle.validate(Bundle.parse(frag))
    assert msg =~ "fragment"
  end

  test "validate rejects unsafe / out-of-tree paths" do
    bad = ~s(<file path="../etc/passwd">\ndefmodule A do\nend\n</file>)
    assert {:error, msg} = Bundle.validate(Bundle.parse(bad))
    assert msg =~ "unsafe"

    outside = ~s(<file path="secrets/a.ex">\ndefmodule A do\nend\n</file>)
    assert {:error, _} = Bundle.validate(Bundle.parse(outside))
  end

  test "validate rejects duplicate paths and empty bundles" do
    dup =
      ~s(<file path="lib/a.ex">\ndefmodule A do\nend\n</file>\n<file path="lib/a.ex">\ndefmodule B do\nend\n</file>)

    assert {:error, msg} = Bundle.validate(Bundle.parse(dup))
    assert msg =~ "duplicate"
    assert {:error, _} = Bundle.validate([])
  end

  test "materialize splits sources from migrations; module_names + lib_sources" do
    files = Bundle.parse(@good)
    assert Bundle.module_names(files) == ["A"]
    assert [src] = Bundle.lib_sources(files)
    assert src =~ "def x"

    dir = Path.join(System.tmp_dir!(), "bt_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    {sources, migrations} = Bundle.materialize(files, dir)
    assert length(sources) == 1 and length(migrations) == 1
    File.rm_rf!(dir)
  end
end
