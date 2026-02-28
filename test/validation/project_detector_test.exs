defmodule Babysitter.Validation.ProjectDetectorTest do
  use ExUnit.Case, async: true

  alias Babysitter.Validation.ProjectDetector

  describe "detect/1" do
    test "detects Elixir project with mix.exs" do
      assert {:ok, :elixir} = ProjectDetector.detect(File.cwd!())
    end

    test "detects Go project with go.mod" do
      with_unique_tmp_dir(fn tmp_dir ->
        File.write!(Path.join(tmp_dir, "go.mod"), "module example.com/test\n")
        assert {:ok, :go} = ProjectDetector.detect(tmp_dir)
      end)
    end

    test "detects Node.js project with package.json" do
      with_unique_tmp_dir(fn tmp_dir ->
        File.write!(Path.join(tmp_dir, "package.json"), ~s({"name": "test"}))
        assert {:ok, :nodejs} = ProjectDetector.detect(tmp_dir)
      end)
    end

    test "detects Rust project with Cargo.toml" do
      with_unique_tmp_dir(fn tmp_dir ->
        File.write!(Path.join(tmp_dir, "Cargo.toml"), "[package]\nname = \"test\"\n")
        assert {:ok, :rust} = ProjectDetector.detect(tmp_dir)
      end)
    end

    test "detects Python project with pyproject.toml" do
      with_unique_tmp_dir(fn tmp_dir ->
        File.write!(Path.join(tmp_dir, "pyproject.toml"), "[project]\nname = \"test\"\n")
        assert {:ok, :python} = ProjectDetector.detect(tmp_dir)
      end)
    end

    test "returns error for non-project directory" do
      with_unique_tmp_dir(fn tmp_dir ->
        assert {:error, :not_detected} = ProjectDetector.detect(tmp_dir)
      end)
    end
  end

  describe "detect_all/1 - monorepo support" do
    test "detects root project" do
      {:ok, projects} = ProjectDetector.detect_all(File.cwd!())
      assert %{:root => :elixir} = projects
    end

    test "detects multiple projects in monorepo" do
      with_unique_tmp_dir(fn tmp_dir ->
        elixir_dir = Path.join(tmp_dir, "backend")
        go_dir = Path.join(tmp_dir, "cli")
        File.mkdir_p!(elixir_dir)
        File.mkdir_p!(go_dir)
        File.write!(Path.join(elixir_dir, "mix.exs"), "defmodule Test do end")
        File.write!(Path.join(go_dir, "go.mod"), "module example.com/cli\n")

        {:ok, projects} = ProjectDetector.detect_all(tmp_dir)
        assert projects["backend"] == :elixir
        assert projects["cli"] == :go
      end)
    end

    test "ignores common non-project directories" do
      with_unique_tmp_dir(fn tmp_dir ->
        File.mkdir_p!(Path.join(tmp_dir, "node_modules"))
        File.mkdir_p!(Path.join(tmp_dir, ".git"))

        {:ok, projects} = ProjectDetector.detect_all(tmp_dir)
        refute Map.has_key?(projects, "node_modules")
        refute Map.has_key?(projects, ".git")
      end)
    end
  end

  describe "get_compile_command/1" do
    test "returns mix compile for Elixir" do
      assert {:ok, cmd} = ProjectDetector.get_compile_command(:elixir)
      assert cmd =~ "mix compile"
    end

    test "returns go build for Go" do
      assert {:ok, cmd} = ProjectDetector.get_compile_command(:go)
      assert cmd =~ "go build"
    end

    test "returns error for unknown" do
      assert {:error, :unknown_language} = ProjectDetector.get_compile_command(:unknown)
    end
  end

  describe "get_test_command/1" do
    test "returns mix test for Elixir" do
      assert {:ok, cmd} = ProjectDetector.get_test_command(:elixir)
      assert cmd =~ "mix test"
    end

    test "returns go test for Go" do
      assert {:ok, cmd} = ProjectDetector.get_test_command(:go)
      assert cmd =~ "go test"
    end
  end

  describe "get_lint_command/1" do
    test "returns credo for Elixir" do
      assert {:ok, cmd} = ProjectDetector.get_lint_command(:elixir)
      assert cmd =~ "credo"
    end
  end

  describe "project_type_info/1" do
    test "returns info for Elixir" do
      assert {:ok, info} = ProjectDetector.project_type_info(:elixir)
      assert info.name == :elixir
      assert is_binary(info.compile_command)
    end
  end

  describe "detect_with_commands/1" do
    test "returns type with commands" do
      {:ok, result} = ProjectDetector.detect_with_commands(File.cwd!())
      assert result.type == :elixir
      assert is_binary(result.compile_command)
    end
  end

  describe "supported_types/0" do
    test "returns all types" do
      types = ProjectDetector.supported_types()
      assert :elixir in types
      assert :go in types
      assert :nodejs in types
    end
  end

  describe "ignored_directory?/1" do
    test "identifies ignored dirs" do
      assert ProjectDetector.ignored_directory?("node_modules")
      assert ProjectDetector.ignored_directory?(".git")
      refute ProjectDetector.ignored_directory?("src")
    end
  end

  defp with_unique_tmp_dir(callback) do
    tmp_dir = Path.join(System.tmp_dir!(), "pd_test_#{:rand.uniform(100_000_000)}")
    File.mkdir_p!(tmp_dir)

    try do
      callback.(tmp_dir)
    after
      File.rm_rf!(tmp_dir)
    end
  end
end
