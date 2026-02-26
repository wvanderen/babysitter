defmodule Babysitter.Workflow.LoaderTest do
  use ExUnit.Case, async: false

  alias Babysitter.Workflow.Loader

  @temp_dir "test/tmp/workflow_loader"

  setup do
    File.rm_rf!(@temp_dir)
    File.mkdir_p!(@temp_dir)

    on_exit(fn ->
      File.rm_rf!(@temp_dir)
    end)

    :ok
  end

  describe "load_all/1" do
    test "returns empty list for non-existent directory" do
      non_existent = "test/tmp/non_existent_dir_#{:rand.uniform(1_000_000)}"
      assert {:ok, []} = Loader.load_all(non_existent)
    end

    test "returns empty list for empty directory" do
      assert {:ok, []} = Loader.load_all(@temp_dir)
    end

    test "loads single workflow file" do
      yaml = """
      id: test-workflow
      name: Test Workflow
      stages:
        - id: step1
          type: action
          command: echo hello
      """

      File.write!(Path.join(@temp_dir, "test.yaml"), yaml)

      assert {:ok, [workflow]} = Loader.load_all(@temp_dir)
      assert workflow.id == "test-workflow"
      assert workflow.name == "Test Workflow"
    end

    test "loads multiple workflow files" do
      yaml1 = """
      id: workflow-1
      name: First Workflow
      stages:
        - id: step1
          type: action
          command: echo one
      """

      yaml2 = """
      id: workflow-2
      name: Second Workflow
      stages:
        - id: step1
          type: action
          command: echo two
      """

      File.write!(Path.join(@temp_dir, "workflow1.yaml"), yaml1)
      File.write!(Path.join(@temp_dir, "workflow2.yml"), yaml2)

      assert {:ok, workflows} = Loader.load_all(@temp_dir)
      assert length(workflows) == 2

      ids = Enum.map(workflows, & &1.id) |> Enum.sort()
      assert ids == ["workflow-1", "workflow-2"]
    end

    test "ignores non-yaml files" do
      yaml = """
      id: valid-workflow
      name: Valid Workflow
      stages:
        - id: step1
          type: action
          command: echo valid
      """

      File.write!(Path.join(@temp_dir, "valid.yaml"), yaml)
      File.write!(Path.join(@temp_dir, "readme.txt"), "This is not a workflow")
      File.write!(Path.join(@temp_dir, "script.ex"), "defmodule Script do end")

      assert {:ok, [workflow]} = Loader.load_all(@temp_dir)
      assert workflow.id == "valid-workflow"
    end

    test "returns error with failed files for invalid yaml" do
      valid_yaml = """
      id: valid-workflow
      name: Valid Workflow
      stages:
        - id: step1
          type: action
          command: echo valid
      """

      invalid_yaml = """
      id: invalid-workflow
      name: Invalid Workflow
      # Missing stages field
      """

      File.write!(Path.join(@temp_dir, "valid.yaml"), valid_yaml)
      File.write!(Path.join(@temp_dir, "invalid.yaml"), invalid_yaml)

      assert {:error, failed_files} = Loader.load_all(@temp_dir)
      assert length(failed_files) == 1

      [{failed_path, reason}] = failed_files
      assert failed_path =~ "invalid.yaml"
      assert reason == {:missing_required_field, :stages}
    end

    test "collects multiple failures" do
      invalid1 = """
      id: invalid-1
      name: Invalid One
      """

      invalid2 = """
      id: invalid-2
      name: Invalid Two
      """

      File.write!(Path.join(@temp_dir, "invalid1.yaml"), invalid1)
      File.write!(Path.join(@temp_dir, "invalid2.yml"), invalid2)

      assert {:error, failed_files} = Loader.load_all(@temp_dir)
      assert length(failed_files) == 2
    end

    test "handles yaml syntax errors" do
      bad_yaml = """
      id: test
      name: Test
      stages:
        - id: step1
          type: action
      - invalid list item
      """

      File.write!(Path.join(@temp_dir, "bad.yaml"), bad_yaml)

      assert {:error, failed_files} = Loader.load_all(@temp_dir)
      assert length(failed_files) == 1
      [{_path, reason}] = failed_files
      assert match?({:yaml_parse_error, _}, reason) or match?({:yaml_decode_error, _}, reason)
    end
  end

  describe "load_all/0" do
    test "uses default directory path" do
      assert {:ok, workflows} = Loader.load_all()
      assert is_list(workflows)
      assert Enum.all?(workflows, &Map.has_key?(&1, :id))
    end
  end

  describe "load_file/1" do
    test "loads single workflow file by path" do
      yaml = """
      id: single-workflow
      name: Single Workflow
      stages:
        - id: step1
          type: action
          command: echo single
      """

      file_path = Path.join(@temp_dir, "single.yaml")
      File.write!(file_path, yaml)

      assert {:ok, workflow} = Loader.load_file(file_path)
      assert workflow.id == "single-workflow"
    end

    test "returns error for non-existent file" do
      non_existent = Path.join(@temp_dir, "non_existent.yaml")
      assert {:error, :file_not_found} = Loader.load_file(non_existent)
    end

    test "returns error for invalid yaml" do
      invalid_yaml = """
      id: invalid
      name: Invalid
      """

      file_path = Path.join(@temp_dir, "invalid.yaml")
      File.write!(file_path, invalid_yaml)

      assert {:error, reason} = Loader.load_file(file_path)
      assert reason == {:missing_required_field, :stages}
    end
  end

  describe "workflows_by_id/1" do
    test "returns map of workflows indexed by id" do
      yaml1 = """
      id: workflow-alpha
      name: Alpha Workflow
      stages:
        - id: step1
          type: action
          command: echo alpha
      """

      yaml2 = """
      id: workflow-beta
      name: Beta Workflow
      stages:
        - id: step1
          type: action
          command: echo beta
      """

      File.write!(Path.join(@temp_dir, "alpha.yaml"), yaml1)
      File.write!(Path.join(@temp_dir, "beta.yaml"), yaml2)

      assert {:ok, workflows} = Loader.load_all(@temp_dir)
      by_id = Loader.workflows_by_id(workflows)

      assert map_size(by_id) == 2
      assert by_id["workflow-alpha"].name == "Alpha Workflow"
      assert by_id["workflow-beta"].name == "Beta Workflow"
    end
  end
end
