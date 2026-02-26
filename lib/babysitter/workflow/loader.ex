defmodule Babysitter.Workflow.Loader do
  @moduledoc """
  Loads workflow files from a directory.

  Handles discovery of YAML files and batch parsing with error collection.
  """

  alias Babysitter.Workflow.Parser

  @default_path ".babysitter/workflows"

  @spec load_all() :: {:ok, [map()]} | {:error, [{String.t(), term()}]}
  def load_all do
    load_all(@default_path)
  end

  @spec load_all(Path.t()) :: {:ok, [map()]} | {:error, [{String.t(), term()}]}
  def load_all(dir) do
    case find_workflow_files(dir) do
      [] ->
        {:ok, []}

      files ->
        files
        |> Enum.reduce({[], []}, fn file, {successes, failures} ->
          case safe_parse(file) do
            {:ok, workflow} -> {[workflow | successes], failures}
            {:error, reason} -> {successes, [{file, reason} | failures]}
          end
        end)
        |> case do
          {workflows, []} -> {:ok, Enum.reverse(workflows)}
          {_, failures} -> {:error, Enum.reverse(failures)}
        end
    end
  end

  @spec load_file(Path.t()) :: {:ok, map()} | {:error, term()}
  def load_file(path) do
    safe_parse(path)
  end

  @spec workflows_by_id([map()]) :: %{String.t() => map()}
  def workflows_by_id(workflows) do
    Map.new(workflows, fn workflow -> {workflow.id, workflow} end)
  end

  defp safe_parse(file) do
    Parser.parse_file(file)
  catch
    :error, reason -> {:error, {:yaml_decode_error, reason}}
    :throw, reason -> {:error, {:yaml_parse_error, reason}}
  end

  defp find_workflow_files(dir) do
    dir
    |> Path.join("*.{yml,yaml}")
    |> Path.wildcard()
    |> Enum.sort()
  end
end
