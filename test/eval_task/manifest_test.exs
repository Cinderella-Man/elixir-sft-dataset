defmodule EvalTask.ManifestTest do
  use ExUnit.Case, async: true
  alias EvalTask.Manifest

  test "infers phoenix_conncase + prefix/web/otp from ConnCase" do
    m = Manifest.infer("defmodule X do\n  use PaginatedListWeb.ConnCase, async: true\nend")
    assert m.archetype == :phoenix_conncase
    assert m.prefix == "PaginatedList"
    assert m.web_prefix == "PaginatedListWeb"
    assert m.otp_app == :paginated_list
    assert m.db == :sqlite
  end

  test "infers plug_selfcontained from Plug.Test (use or import)" do
    assert Manifest.infer("use Plug.Test").archetype == :plug_selfcontained
    assert Manifest.infer("import Plug.Test").archetype == :plug_selfcontained
  end

  test "defaults to pure_otp" do
    m = Manifest.infer("use ExUnit.Case, async: false")
    assert m.archetype == :pure_otp
    assert m.db == :none
  end

  test "manifest.exs overrides inference" do
    dir = Path.join(System.tmp_dir!(), "mt_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "manifest.exs"), "%{db: :postgres}")
    m = Manifest.resolve(dir, "use MyAppWeb.ConnCase")
    assert m.db == :postgres
    assert m.archetype == :phoenix_conncase
    File.rm_rf!(dir)
  end
end
