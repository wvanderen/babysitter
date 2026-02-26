defmodule Babysitter.Workflow.Parser do
  @moduledoc """
  Parses YAML workflow files into workflow definitions.

  Workflow files are located in .babysitter/workflows/*.yaml
  """

  alias Babysitter.{Stage, Validation}

  @type workflow :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          intelligence: :dumb | :smart | :hybrid,
          stages: %{atom() => Stage.t()},
          stage_order: [atom()],
          entry_point: atom() | nil,
          metadata: map()
        }

  @spec parse_file(Path.t()) :: {:ok, workflow()} | {:error, term()}
  def parse_file(path) do
    with true <- File.exists?(path),
         {:ok, raw} <- decode_yaml(path),
         {:ok, parsed} <- validate_required_fields(raw),
         {:ok, workflow} <- build_workflow(parsed) do
      {:ok, workflow}
    else
      false ->
        {:error,
         {:invalid_yaml, path, %{reason: :file_not_found, message: "File not found: #{path}"}}}

      error ->
        error
    end
  end

  @spec parse_string(String.t()) :: {:ok, workflow()} | {:error, term()}
  def parse_string(yaml_content) do
    with {:ok, raw} <- decode_yaml_string(yaml_content),
         {:ok, parsed} <- validate_required_fields(raw),
         {:ok, workflow} <- build_workflow(parsed) do
      {:ok, workflow}
    end
  end

  defp decode_yaml(path) do
    case :yamerl.decode_file(String.to_charlist(path)) do
      [config | _] when is_list(config) ->
        {:ok, atomize_keys(config)}

      {:error, _, _} = error ->
        {:error, format_yamerl_error(path, error)}

      [] ->
        {:error, {:invalid_yaml, path, %{reason: :empty_file, message: "YAML file is empty"}}}
    end
  catch
    :throw, {:yamerl_exception, errors} ->
      {:error, format_yamerl_exception(path, errors)}

    kind, reason ->
      {:error,
       {:invalid_yaml, path, %{reason: :decode_error, message: format_error_reason(kind, reason)}}}
  end

  defp decode_yaml_string(content) do
    case :yamerl.decode(String.to_charlist(content)) do
      [config | _] when is_list(config) ->
        {:ok, atomize_keys(config)}

      {:error, _, _} = error ->
        {:error, format_yamerl_error(nil, error)}

      [] ->
        {:error,
         {:invalid_yaml, nil, %{reason: :empty_content, message: "YAML content is empty"}}}
    end
  catch
    :throw, {:yamerl_exception, errors} ->
      {:error, format_yamerl_exception(nil, errors)}

    kind, reason ->
      {:error,
       {:invalid_yaml, nil, %{reason: :decode_error, message: format_error_reason(kind, reason)}}}
  end

  defp validate_required_fields(parsed) do
    with :ok <- require_field(parsed, :id),
         :ok <- require_field(parsed, :name),
         :ok <- require_field(parsed, :stages) do
      {:ok, parsed}
    end
  end

  defp require_field(parsed, field) do
    if Map.has_key?(parsed, field) do
      :ok
    else
      {:error,
       {:invalid_yaml, nil,
        %{
          reason: :missing_required_field,
          field: field,
          message: "Missing required field: #{field}"
        }}}
    end
  end

  defp build_workflow(parsed) do
    id = to_string(parsed[:id])
    stages_data = parsed[:stages] || []

    with {:ok, stages_map, stage_order} <- build_stages(stages_data, id) do
      entry_point = parse_entry_point(parsed[:entry_point], stage_order)

      workflow = %{
        id: id,
        name: to_string(parsed[:name]),
        description: parsed[:description] && to_string(parsed[:description]),
        intelligence: parse_intelligence(parsed[:intelligence]),
        stages: stages_map,
        stage_order: stage_order,
        entry_point: entry_point,
        metadata: build_metadata(parsed)
      }

      {:ok, workflow}
    end
  end

  defp build_stages(stages_data, workflow_id) do
    stages_data
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}, []}, fn {stage_data, index}, {:ok, acc_map, acc_order} ->
      case build_stage(stage_data, workflow_id, index) do
        {:ok, stage} ->
          stage_id = if is_atom(stage.id), do: stage.id, else: String.to_atom(stage.id)
          {:cont, {:ok, Map.put(acc_map, stage_id, stage), acc_order ++ [stage_id]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp build_stage(stage_data, _workflow_id, _index) do
    with {:ok, id} <- get_stage_id(stage_data),
         {:ok, type} <- parse_stage_type(stage_data[:type]) do
      timeout = parse_timeout(stage_data[:timeout])
      validations = parse_validations(stage_data[:validation] || stage_data[:validations] || [])

      stage = %Stage{
        id: id,
        type: type,
        agent: parse_agent(stage_data[:agent]),
        name: stage_data[:name] && to_string(stage_data[:name]),
        prompt: stage_data[:prompt] || stage_data[:prompt_template],
        command: stage_data[:command] && to_string(stage_data[:command]),
        timeout: timeout,
        validations: validations,
        transitions: [],
        on_success: parse_stage_ref(stage_data[:on_success]),
        on_failure: parse_stage_ref(stage_data[:on_failure]),
        on_timeout: parse_stage_ref(stage_data[:on_timeout]),
        metadata: extract_stage_metadata(stage_data)
      }

      {:ok, stage}
    end
  end

  defp get_stage_id(stage_data) do
    case stage_data[:id] do
      nil ->
        {:error,
         {:invalid_yaml, nil,
          %{reason: :missing_stage_id, message: "Stage is missing required 'id' field"}}}

      id ->
        {:ok, to_string(id)}
    end
  end

  defp parse_stage_type(nil), do: {:ok, :agent}
  defp parse_stage_type(type) when is_atom(type), do: {:ok, type}

  defp parse_stage_type(type) when is_binary(type) do
    case String.downcase(type) do
      "agent" ->
        {:ok, :agent}

      "action" ->
        {:ok, :action}

      "validation" ->
        {:ok, :validation}

      "decision" ->
        {:ok, :decision}

      other ->
        {:error,
         {:invalid_yaml, nil,
          %{
            reason: :invalid_stage_type,
            type: other,
            message:
              "Invalid stage type: #{other}. Must be one of: agent, action, validation, decision"
          }}}
    end
  end

  defp parse_agent(nil), do: nil
  defp parse_agent(agent) when is_atom(agent), do: agent
  defp parse_agent(agent) when is_binary(agent), do: String.to_atom(agent)

  defp parse_timeout(nil), do: :infinity
  defp parse_timeout(:infinity), do: :infinity

  defp parse_timeout(timeout) when is_integer(timeout), do: timeout

  defp parse_timeout(timeout) when is_binary(timeout) do
    cond do
      String.ends_with?(timeout, "s") ->
        timeout |> String.trim_trailing("s") |> String.to_integer() |> Kernel.*(1000)

      String.ends_with?(timeout, "m") ->
        timeout |> String.trim_trailing("m") |> String.to_integer() |> Kernel.*(60_000)

      String.ends_with?(timeout, "h") ->
        timeout |> String.trim_trailing("h") |> String.to_integer() |> Kernel.*(3_600_000)

      true ->
        String.to_integer(timeout)
    end
  end

  defp parse_validations(validations) when is_list(validations) do
    Enum.map(validations, &parse_validation/1)
  end

  defp parse_validations(_), do: []

  defp parse_validation(%{type: :compile} = v) do
    %Validation{
      type: :exit_code,
      pattern: 0,
      error_message: v[:error_message] || "Compilation failed"
    }
  end

  defp parse_validation(%{type: :tests} = v) do
    %Validation{
      type: :exit_code,
      pattern: 0,
      error_message: v[:error_message] || "Tests failed"
    }
  end

  defp parse_validation(%{type: :lint} = v) do
    %Validation{
      type: :exit_code,
      pattern: 0,
      error_message: v[:error_message] || "Linting failed"
    }
  end

  defp parse_validation(%{type: :command} = v) do
    %Validation{
      type: :exit_code,
      pattern: 0,
      error_message: v[:error_message] || "Command failed: #{v[:command]}"
    }
  end

  defp parse_validation(%{type: :output_contains} = v) do
    %Validation{
      type: :output_contains,
      pattern: to_string(v[:pattern]),
      negate: v[:negate] || false,
      error_message: v[:error_message]
    }
  end

  defp parse_validation(%{type: :output_matches} = v) do
    pattern = to_string(v[:pattern])

    %Validation{
      type: :output_matches,
      pattern: Regex.compile!(pattern),
      negate: v[:negate] || false,
      error_message: v[:error_message]
    }
  end

  defp parse_validation(%{type: :exit_code} = v) do
    %Validation{
      type: :exit_code,
      pattern: v[:pattern] || 0,
      negate: v[:negate] || false,
      error_message: v[:error_message]
    }
  end

  defp parse_validation(%{type: :file_exists} = v) do
    %Validation{
      type: :file_exists,
      path: v[:path],
      negate: v[:negate] || false,
      error_message: v[:error_message]
    }
  end

  defp parse_validation(%{type: :file_contains} = v) do
    %Validation{
      type: :file_contains,
      path: v[:path],
      pattern: to_string(v[:pattern]),
      negate: v[:negate] || false,
      error_message: v[:error_message]
    }
  end

  defp parse_validation(%{type: type} = v) when is_binary(type) do
    parse_validation(%{v | type: String.to_atom(type)})
  end

  defp parse_validation(validation) when is_map(validation) do
    type = Map.get(validation, :type, :exit_code)

    %Validation{
      type: type,
      pattern: Map.get(validation, :pattern, 0),
      negate: Map.get(validation, :negate, false),
      error_message: Map.get(validation, :error_message)
    }
  end

  defp parse_stage_ref(nil), do: nil

  defp parse_stage_ref(ref) when is_atom(ref), do: ref

  defp parse_stage_ref(ref) when is_binary(ref), do: String.to_atom(ref)

  defp parse_entry_point(nil, [first | _]), do: first
  defp parse_entry_point(nil, []), do: nil
  defp parse_entry_point(point, _) when is_atom(point), do: point
  defp parse_entry_point(point, _) when is_binary(point), do: String.to_atom(point)

  defp parse_intelligence(nil), do: :hybrid
  defp parse_intelligence(int) when is_atom(int), do: int

  defp parse_intelligence(int) when is_binary(int) do
    case String.downcase(int) do
      "dumb" -> :dumb
      "smart" -> :smart
      "hybrid" -> :hybrid
      _ -> :hybrid
    end
  end

  defp extract_stage_metadata(stage_data) do
    reserved =
      ~w[id type agent name prompt prompt_template command timeout validation validations on_success on_failure on_timeout]a

    stage_data
    |> Map.drop(reserved)
  end

  defp build_metadata(parsed) do
    reserved = ~w[id name description intelligence stages entry_point]a

    parsed
    |> Map.drop(reserved)
  end

  defp atomize_keys(config) when is_list(config) do
    cond do
      config == [] ->
        []

      printable_charlist?(config) ->
        List.to_string(config)

      is_proplist?(config) ->
        config
        |> Enum.map(fn {k, v} ->
          key = if is_list(k), do: List.to_atom(k), else: k
          {key, atomize_keys(v)}
        end)
        |> Map.new()

      true ->
        Enum.map(config, &atomize_keys/1)
    end
  end

  defp atomize_keys(config) when is_map(config) do
    Map.new(config, fn {k, v} -> {k, atomize_keys(v)} end)
  end

  defp atomize_keys(other), do: other

  defp is_proplist?([{_, _} | rest]), do: is_proplist?(rest)
  defp is_proplist?([]), do: true
  defp is_proplist?(_), do: false

  defp printable_charlist?(list) when is_list(list),
    do: list != [] and List.ascii_printable?(list)

  defp printable_charlist?(_), do: false

  defp format_yamerl_exception(path, errors) when is_list(errors) do
    error = List.first(errors)
    details = extract_yamerl_error_details(error)
    {:invalid_yaml, path, details}
  end

  defp format_yamerl_exception(path, error) do
    {:invalid_yaml, path, %{reason: :unknown, message: "Unknown YAML error: #{inspect(error)}"}}
  end

  defp extract_yamerl_error_details(
         {:yamerl_parsing_error, level, message, line, col, type, _token, _}
       ) do
    %{
      level: level,
      line: line,
      column: col,
      type: type,
      reason: type,
      message: to_string(message)
    }
  end

  defp extract_yamerl_error_details({:yamerl_invalid_option, details}) do
    %{
      reason: :invalid_option,
      message: "Invalid YAML option: #{inspect(details)}"
    }
  end

  defp extract_yamerl_error_details(error) do
    %{
      reason: :unknown,
      message: "YAML parsing error: #{inspect(error)}"
    }
  end

  defp format_yamerl_error(path, {:error, line, message}) do
    {:invalid_yaml, path,
     %{
       reason: :parse_error,
       line: line,
       message: to_string(message)
     }}
  end

  defp format_yamerl_error(path, error) do
    {:invalid_yaml, path,
     %{
       reason: :parse_error,
       message: "YAML parse error: #{inspect(error)}"
     }}
  end

  defp format_error_reason(:error, %_{message: message}), do: message
  defp format_error_reason(:error, message) when is_binary(message), do: message
  defp format_error_reason(:error, reason), do: inspect(reason)
  defp format_error_reason(kind, reason), do: "#{kind}: #{inspect(reason)}"
end
