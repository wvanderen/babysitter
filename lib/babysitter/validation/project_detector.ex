defmodule Babysitter.Validation.ProjectDetector do
  @moduledoc """
  Detects project types and maps them to validation commands.

  Supports detection of:
  - Elixir projects (mix.exs)
  - Go projects (go.mod)
  - Node.js projects (package.json)
  - Rust projects (Cargo.toml)
  - Python projects (pyproject.toml, setup.py, requirements.txt)

  Also handles monorepo scenarios where multiple project types exist
  in different subdirectories.
  """

  @type project_type :: :elixir | :go | :nodejs | :rust | :python

  @project_configs %{
    elixir: %{
      marker_files: ["mix.exs"],
      compile_command: "mix compile --warnings-as-errors",
      test_command: "mix test",
      lint_command: "mix credo --strict"
    },
    go: %{
      marker_files: ["go.mod"],
      compile_command: "go build ./...",
      test_command: "go test ./...",
      lint_command: "go vet ./..."
    },
    nodejs: %{
      marker_files: ["package.json"],
      compile_command: "npx tsc --noEmit",
      test_command: "npm test",
      lint_command: "npx eslint ."
    },
    rust: %{
      marker_files: ["Cargo.toml"],
      compile_command: "cargo build",
      test_command: "cargo test",
      lint_command: "cargo clippy"
    },
    python: %{
      marker_files: ["pyproject.toml", "setup.py", "requirements.txt"],
      compile_command: "python -m py_compile .",
      test_command: "pytest",
      lint_command: "ruff check ."
    }
  }

  @detection_order [:elixir, :go, :nodejs, :rust, :python]

  @ignored_dirs ~w(
    node_modules _build deps .git .hg .svn
    vendor target dist build .elixir_ls
    __pycache__ .tox .venv venv env .env
    .idea .vscode .vs
  )

  @doc """
  Detect the project type for a directory.
  """
  @spec detect(String.t() | nil) :: {:ok, project_type()} | {:error, :not_detected}
  def detect(cwd \\ nil) do
    cwd = cwd || File.cwd!()

    @detection_order
    |> Enum.find(fn type ->
      config = Map.get(@project_configs, type)
      Enum.any?(config.marker_files, &File.exists?(Path.join(cwd, &1)))
    end)
    |> case do
      nil -> {:error, :not_detected}
      type -> {:ok, type}
    end
  end

  @doc """
  Detect all project types in a directory tree (monorepo support).
  """
  @spec detect_all(String.t() | nil, keyword()) ::
          {:ok, %{optional(atom() | String.t()) => project_type()}} | {:error, term()}
  def detect_all(cwd \\ nil, opts \\ []) do
    cwd = cwd || File.cwd!()
    max_depth = Keyword.get(opts, :max_depth, 3)

    root_type = detect(cwd)

    subprojects =
      scan_subdirectories(cwd, max_depth)
      |> Enum.map(fn {rel_path, abs_path} ->
        case detect(abs_path) do
          {:ok, type} -> {rel_path, type}
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    result =
      case root_type do
        {:ok, type} -> Map.put(subprojects, :root, type)
        {:error, _} -> subprojects
      end

    {:ok, result}
  end

  @doc """
  Detect project type and return commands in one call.
  """
  @spec detect_with_commands(String.t() | nil) :: {:ok, map()} | {:error, :not_detected}
  def detect_with_commands(cwd \\ nil) do
    case detect(cwd) do
      {:ok, type} ->
        {:ok,
         %{
           type: type,
           compile_command: get_command!(type, :compile_command),
           test_command: get_command!(type, :test_command),
           lint_command: get_command!(type, :lint_command)
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get the compile command for a project type.
  """
  @spec get_compile_command(project_type()) :: {:ok, String.t()} | {:error, :unknown_language}
  def get_compile_command(type), do: get_command(type, :compile_command)

  @doc """
  Get the test command for a project type.
  """
  @spec get_test_command(project_type()) :: {:ok, String.t()} | {:error, :unknown_language}
  def get_test_command(type), do: get_command(type, :test_command)

  @doc """
  Get the lint command for a project type.
  """
  @spec get_lint_command(project_type()) :: {:ok, String.t()} | {:error, :unknown_language}
  def get_lint_command(type), do: get_command(type, :lint_command)

  @doc """
  Get comprehensive information about a project type.
  """
  @spec project_type_info(project_type()) :: {:ok, map()} | {:error, :unknown_language}
  def project_type_info(type) do
    case Map.get(@project_configs, type) do
      nil ->
        {:error, :unknown_language}

      config ->
        {:ok,
         %{
           name: type,
           compile_command: config.compile_command,
           test_command: config.test_command,
           lint_command: config.lint_command,
           marker_files: config.marker_files
         }}
    end
  end

  @doc """
  Check if a directory should be ignored during scanning.
  """
  @spec ignored_directory?(String.t()) :: boolean()
  def ignored_directory?(dirname) do
    dirname in @ignored_dirs or String.starts_with?(dirname, ".")
  end

  @doc """
  Get all supported project types.
  """
  @spec supported_types() :: [project_type()]
  def supported_types, do: @detection_order

  defp get_command(type, command_key) do
    case Map.get(@project_configs, type) do
      nil -> {:error, :unknown_language}
      config -> {:ok, Map.get(config, command_key)}
    end
  end

  defp get_command!(type, command_key) do
    case get_command(type, command_key) do
      {:ok, command} -> command
      {:error, _} -> raise "Unknown project type: #{type}"
    end
  end

  defp scan_subdirectories(cwd, max_depth), do: do_scan(cwd, cwd, 0, max_depth)

  defp do_scan(_root, _current_dir, current_depth, max_depth) when current_depth >= max_depth,
    do: []

  defp do_scan(root, current_dir, current_depth, max_depth) do
    case File.ls(current_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn entry ->
          path = Path.join(current_dir, entry)
          File.dir?(path) and not ignored_directory?(entry)
        end)
        |> Enum.flat_map(fn entry ->
          full_path = Path.join(current_dir, entry)
          rel_path = Path.relative_to(full_path, root)

          current_detection =
            case detect(full_path) do
              {:ok, _type} -> [{rel_path, full_path}]
              {:error, _} -> []
            end

          nested = do_scan(root, full_path, current_depth + 1, max_depth)
          current_detection ++ nested
        end)

      {:error, _} ->
        []
    end
  end
end
