# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Verifiers.VerifyUniqueInputFieldNames do
  @moduledoc """
  Verifies that all input fields for each RPC action have unique client names.

  This prevents ambiguous input parsing where two different Elixir fields
  (arguments or accepted attributes) would map to the same client field name
  after formatting.

  ## Example

  If a resource has:
  ```elixir
  attribute :user_name, :string
  argument :userName, :string  # Would map to same client name as user_name
  ```

  This verifier would catch the conflict at compile time.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    output_formatter = AshTypescript.Rpc.output_field_formatter()

    dsl
    |> Verifier.get_entities([:typescript_rpc])
    |> Enum.reduce_while(:ok, fn %{resource: resource, rpc_actions: rpc_actions}, acc ->
      case verify_resource_actions(resource, rpc_actions, output_formatter) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_resource_actions(resource, rpc_actions, formatter) do
    errors =
      Enum.flat_map(rpc_actions, fn rpc_action ->
        verify_action_input_fields(resource, rpc_action, formatter)
      end)

    case errors do
      [] -> :ok
      _ -> format_errors(errors)
    end
  end

  defp verify_action_input_fields(resource, rpc_action, formatter) do
    action = Ash.Resource.Info.action(resource, rpc_action.action)

    if action do
      # Build list of {client_name, internal_name, source} tuples
      all_input_fields =
        build_argument_entries(resource, action, formatter) ++
          build_attribute_entries(resource, action, formatter)

      # Group by client name and find duplicates
      all_input_fields
      |> Enum.group_by(fn {client_name, _internal, _source} -> client_name end)
      |> Enum.filter(fn {_client_name, entries} -> length(entries) > 1 end)
      |> Enum.map(fn {client_name, entries} ->
        {resource, rpc_action.name, rpc_action.action, client_name, entries}
      end)
    else
      []
    end
  end

  defp build_argument_entries(resource, action, formatter) do
    action.arguments
    |> Enum.filter(& &1.public?)
    |> Enum.map(fn arg ->
      mapped =
        AshTypescript.Resource.Info.get_mapped_argument_name(resource, action.name, arg.name)

      client_name =
        cond do
          is_binary(mapped) ->
            mapped

          mapped == arg.name ->
            AshTypescript.FieldFormatter.format_field_name(arg.name, formatter)

          true ->
            AshTypescript.FieldFormatter.format_field_name(mapped, formatter)
        end

      {client_name, arg.name, :argument}
    end)
  end

  defp build_attribute_entries(resource, action, formatter) do
    accept_list = Map.get(action, :accept) || []

    accept_list
    |> Enum.map(&Ash.Resource.Info.attribute(resource, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn attr ->
      client_name =
        case AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name) do
          mapped when is_binary(mapped) -> mapped
          nil -> AshTypescript.FieldFormatter.format_field_name(attr.name, formatter)
        end

      {client_name, attr.name, :attribute}
    end)
  end

  defp format_errors(errors) do
    message =
      Enum.map_join(errors, "\n\n", fn {resource, rpc_action, action, client_name, entries} ->
        fields =
          Enum.map_join(entries, ", ", fn {_client, internal, source} ->
            "#{source} :#{internal}"
          end)

        """
        Duplicate input field name "#{client_name}" in #{inspect(resource)}
          RPC action: #{rpc_action} (action: #{action})
          The following fields all map to the same client name: #{fields}
          Use field_names or argument_names DSL to provide unique names.
        """
      end)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Duplicate input field names found in RPC configuration.

       #{message}

       Input field names must be unique within each action to avoid ambiguous parsing.
       """
     )}
  end
end
