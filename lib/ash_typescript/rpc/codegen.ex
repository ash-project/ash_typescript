# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen do
  @moduledoc """
  Generates TypeScript code for interacting with Ash resources via Rpc.
  """
  import AshTypescript.Codegen
  import AshTypescript.Codegen.FilterTypes

  alias AshTypescript.Codegen.TypeDiscovery
  alias AshTypescript.Rpc.Codegen.FunctionGenerators.ChannelRenderer
  alias AshTypescript.Rpc.Codegen.FunctionGenerators.HttpRenderer
  alias AshTypescript.Rpc.Codegen.FunctionGenerators.TypedQueries
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector
  alias AshTypescript.Rpc.Codegen.TypeGenerators.InputTypes
  alias AshTypescript.Rpc.Codegen.TypeGenerators.ResultTypes
  alias AshTypescript.Rpc.Codegen.TypescriptStatic
  alias AshTypescript.Rpc.ZodSchemaGenerator

  @doc """
  Formats an endpoint configuration for TypeScript code generation.

  Accepts either:
  - A string: Returns the string as a quoted literal for direct embedding
  - A tuple {:runtime_expr, "expression"}: Returns the expression as-is for runtime evaluation

  ## Examples

      iex> format_endpoint_for_typescript("/rpc/run")
      "\"/rpc/run\""

      iex> format_endpoint_for_typescript({:runtime_expr, "CustomTypes.getRunEndpoint()"})
      "CustomTypes.getRunEndpoint()"
  """
  def format_endpoint_for_typescript(endpoint) when is_binary(endpoint) do
    "\"#{endpoint}\""
  end

  def format_endpoint_for_typescript({:runtime_expr, expression})
      when is_binary(expression) do
    expression
  end

  def generate_typescript_types(otp_app, opts \\ []) do
    endpoint_process =
      Keyword.get(opts, :run_endpoint, "/rpc/run")
      |> format_endpoint_for_typescript()

    endpoint_validate =
      Keyword.get(opts, :validate_endpoint, "/rpc/validate")
      |> format_endpoint_for_typescript()

    rpc_action_before_request_hook =
      Keyword.get(opts, :rpc_action_before_request_hook) ||
        AshTypescript.rpc_action_before_request_hook()

    rpc_action_after_request_hook =
      Keyword.get(opts, :rpc_action_after_request_hook) ||
        AshTypescript.rpc_action_after_request_hook()

    rpc_validation_before_request_hook =
      Keyword.get(opts, :rpc_validation_before_request_hook) ||
        AshTypescript.rpc_validation_before_request_hook()

    rpc_validation_after_request_hook =
      Keyword.get(opts, :rpc_validation_after_request_hook) ||
        AshTypescript.rpc_validation_after_request_hook()

    rpc_action_hook_context_type =
      Keyword.get(opts, :rpc_action_hook_context_type) ||
        AshTypescript.rpc_action_hook_context_type()

    rpc_validation_hook_context_type =
      Keyword.get(opts, :rpc_validation_hook_context_type) ||
        AshTypescript.rpc_validation_hook_context_type()

    rpc_action_before_channel_push_hook =
      Keyword.get(opts, :rpc_action_before_channel_push_hook) ||
        AshTypescript.rpc_action_before_channel_push_hook()

    rpc_action_after_channel_response_hook =
      Keyword.get(opts, :rpc_action_after_channel_response_hook) ||
        AshTypescript.rpc_action_after_channel_response_hook()

    rpc_validation_before_channel_push_hook =
      Keyword.get(opts, :rpc_validation_before_channel_push_hook) ||
        AshTypescript.rpc_validation_before_channel_push_hook()

    rpc_validation_after_channel_response_hook =
      Keyword.get(opts, :rpc_validation_after_channel_response_hook) ||
        AshTypescript.rpc_validation_after_channel_response_hook()

    rpc_action_channel_hook_context_type =
      Keyword.get(opts, :rpc_action_channel_hook_context_type) ||
        AshTypescript.rpc_action_channel_hook_context_type()

    rpc_validation_channel_hook_context_type =
      Keyword.get(opts, :rpc_validation_channel_hook_context_type) ||
        AshTypescript.rpc_validation_channel_hook_context_type()

    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(otp_app)

    rpc_resources = TypeDiscovery.get_rpc_resources(otp_app)
    domains = Ash.Info.domains(otp_app)

    case AshTypescript.VerifierChecker.check_all_verifiers(rpc_resources ++ domains) do
      :ok ->
        case TypeDiscovery.build_rpc_warnings(otp_app) do
          nil -> :ok
          message -> IO.warn(message)
        end

        {:ok,
         generate_full_typescript(
           resources_and_actions,
           endpoint_process,
           endpoint_validate,
           %{
             rpc_action_before_request_hook: rpc_action_before_request_hook,
             rpc_action_after_request_hook: rpc_action_after_request_hook,
             rpc_validation_before_request_hook: rpc_validation_before_request_hook,
             rpc_validation_after_request_hook: rpc_validation_after_request_hook,
             rpc_action_hook_context_type: rpc_action_hook_context_type,
             rpc_validation_hook_context_type: rpc_validation_hook_context_type,
             rpc_action_before_channel_push_hook: rpc_action_before_channel_push_hook,
             rpc_action_after_channel_response_hook: rpc_action_after_channel_response_hook,
             rpc_validation_before_channel_push_hook: rpc_validation_before_channel_push_hook,
             rpc_validation_after_channel_response_hook:
               rpc_validation_after_channel_response_hook,
             rpc_action_channel_hook_context_type: rpc_action_channel_hook_context_type,
             rpc_validation_channel_hook_context_type: rpc_validation_channel_hook_context_type
           },
           otp_app
         )}

      {:error, error_message} ->
        {:error, error_message}
    end
  end

  defp generate_full_typescript(
         rpc_resources_and_actions,
         endpoint_process,
         endpoint_validate,
         hook_config,
         otp_app
       ) do
    rpc_resources =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.Rpc.Info.typescript_rpc(domain)
        |> Enum.map(fn %{resource: r} -> r end)
      end)
      |> Enum.uniq()

    actions =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.Rpc.Info.typescript_rpc(domain)
        |> Enum.flat_map(fn %{resource: resource, rpc_actions: rpc_actions} ->
          Enum.map(rpc_actions, fn %{action: action} ->
            Ash.Resource.Info.action(resource, action)
          end)
        end)
      end)

    typed_queries = RpcConfigCollector.get_typed_queries(otp_app)

    embedded_resources = find_embedded_resources(otp_app)
    all_resources_for_schemas = rpc_resources ++ embedded_resources

    """
    // Generated by AshTypescript
    // Do not edit this file manually

    #{TypescriptStatic.generate_imports()}

    #{TypescriptStatic.generate_hook_context_types(hook_config)}

    #{generate_ash_type_aliases(rpc_resources, actions, otp_app)}

    #{generate_all_schemas_for_resources(all_resources_for_schemas, all_resources_for_schemas)}

    #{ZodSchemaGenerator.generate_zod_schemas_for_embedded_resources(embedded_resources)}

    #{generate_filter_types(all_resources_for_schemas, all_resources_for_schemas)}

    #{TypescriptStatic.generate_utility_types()}

    #{TypescriptStatic.generate_helper_functions(hook_config, endpoint_process, endpoint_validate)}

    #{TypedQueries.generate_typed_queries_section(typed_queries, all_resources_for_schemas)}

    #{generate_rpc_functions(rpc_resources_and_actions, otp_app, all_resources_for_schemas)}
    """
  end

  defp generate_rpc_functions(
         resources_and_actions,
         otp_app,
         _resources
       ) do
    rpc_functions =
      resources_and_actions
      |> Enum.map_join("\n\n", fn resource_and_action ->
        generate_rpc_function(
          resource_and_action,
          resources_and_actions,
          otp_app
        )
      end)

    """
    #{rpc_functions}
    """
  end

  defp generate_rpc_function(
         {resource, action, rpc_action},
         _resources_and_actions,
         _otp_app
       ) do
    rpc_action_name = to_string(rpc_action.name)

    # Augment action with RPC settings (get?, get_by) so generators see the full picture
    action = augment_action_with_rpc_settings(action, rpc_action, resource)

    input_type = InputTypes.generate_input_type(resource, action, rpc_action_name)

    zod_schema =
      if AshTypescript.Rpc.generate_zod_schemas?() do
        ZodSchemaGenerator.generate_zod_schema(resource, action, rpc_action_name)
      else
        ""
      end

    result_type = ResultTypes.generate_result_type(resource, action, rpc_action, rpc_action_name)

    rpc_function =
      HttpRenderer.render_execution_function(
        resource,
        action,
        rpc_action,
        rpc_action_name
      )

    validation_function =
      if AshTypescript.Rpc.generate_validation_functions?() do
        HttpRenderer.render_validation_function(
          resource,
          action,
          rpc_action_name
        )
      else
        ""
      end

    channel_function =
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        ChannelRenderer.render_execution_function(
          resource,
          action,
          rpc_action,
          rpc_action_name
        )
      else
        ""
      end

    channel_validation_function =
      if AshTypescript.Rpc.generate_validation_functions?() and
           AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        ChannelRenderer.render_validation_function(resource, action, rpc_action_name)
      else
        ""
      end

    function_parts = [rpc_function]

    function_parts =
      if validation_function != "" do
        function_parts ++ [validation_function]
      else
        function_parts
      end

    function_parts =
      if channel_validation_function != "" do
        function_parts ++ [channel_validation_function]
      else
        function_parts
      end

    function_parts =
      if channel_function != "" do
        function_parts ++ [channel_function]
      else
        function_parts
      end

    functions_section = Enum.join(function_parts, "\n\n")

    base_types = [input_type] |> Enum.reject(&(&1 == ""))

    output_parts =
      if zod_schema != "" do
        base_types ++ [zod_schema, result_type, functions_section]
      else
        base_types ++ [result_type, functions_section]
      end

    Enum.join(output_parts, "\n")
    |> String.trim_trailing("\n")
    |> then(&(&1 <> "\n"))
  end

  # Augments the action with RPC-level settings (get?, get_by)
  # This allows TypeScript generators to see the full picture of what the action does
  #
  # Note: get? and get_by no longer add arguments - they are handled separately:
  # - get? just sets action.get? = true to indicate single-record return
  # - get_by stores the fields for generating a separate getBy config field
  defp augment_action_with_rpc_settings(action, rpc_action, _resource) do
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = Map.get(rpc_action, :get_by) || []

    cond do
      # RPC get? - just mark as a get action
      rpc_get? ->
        Map.put(action, :get?, true)

      # RPC get_by - mark as get action and store fields for getBy generation
      rpc_get_by != [] ->
        action
        |> Map.put(:get?, true)
        |> Map.put(:rpc_get_by_fields, rpc_get_by)

      # No RPC modifications
      true ->
        action
    end
  end
end
