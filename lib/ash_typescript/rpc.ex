defmodule AshTypescript.Rpc do
  import AshTypescript.Rpc.Helpers
  require Ash.Query

  defmodule RpcAction do
    defstruct [:name, :action]
  end

  def codegen(argv) do
    Mix.Task.reenable("ash_typescript.codegen")
    Mix.Task.run("ash_typescript.codegen", argv)
  end

  @rpc_action %Spark.Dsl.Entity{
    name: :rpc_action,
    target: RpcAction,
    schema: [
      name: [
        type: :atom,
        doc: "The name of the Rpc-action"
      ],
      action: [
        type: :atom,
        doc: "The resource action to expose"
      ]
    ],
    args: [:name, :action]
  }

  defmodule Resource do
    defstruct [:resource, rpc_actions: []]
  end

  @resource %Spark.Dsl.Entity{
    name: :resource,
    target: Resource,
    describe: "Define available Rpc-actions for a resource",
    schema: [
      resource: [
        type: {:spark, Ash.Resource},
        doc: "The resource being configured"
      ]
    ],
    args: [:resource],
    entities: [
      rpc_actions: [@rpc_action]
    ]
  }

  @rpc %Spark.Dsl.Section{
    name: :rpc,
    describe: "Define available Rpc-actions for resources in this domain.",
    entities: [
      @resource
    ]
  }

  use Spark.Dsl.Extension, sections: [@rpc]

  @doc """
  Determines if tenant parameters are required in RPC requests.

  This checks the application configuration for :require_tenant_parameters.
  If true (default), tenant parameters are required for multitenant resources.
  If false, tenant will be extracted from the connection using Ash.PlugHelpers.get_tenant/1.
  """
  def require_tenant_parameters? do
    Application.get_env(:ash_typescript, :require_tenant_parameters, true)
  end

  @doc """
  Gets the input field formatter configuration for parsing input parameters from the client.

  This determines how client field names are converted to internal Elixir field names.
  Defaults to :camel_case. Can be:
  - Built-in: :camel_case, :pascal_case, :snake_case
  - Custom: {Module, :function} or {Module, :function, [extra_args]}
  """
  def input_field_formatter do
    Application.get_env(:ash_typescript, :input_field_formatter, :camel_case)
  end

  @doc """
  Gets the output field formatter configuration for TypeScript generation and responses to the client.

  This determines how internal Elixir field names are converted for client consumption in both
  generated TypeScript types and API responses.
  Defaults to :camel_case. Can be:
  - Built-in: :camel_case, :pascal_case, :snake_case
  - Custom: {Module, :function} or {Module, :function, [extra_args]}
  """
  def output_field_formatter do
    Application.get_env(:ash_typescript, :output_field_formatter, :camel_case)
  end

  @doc """
  Determines if a resource requires a tenant parameter.

  A resource requires a tenant if it has multitenancy configured and global? is false (default).
  """
  def requires_tenant?(resource) do
    strategy = Ash.Resource.Info.multitenancy_strategy(resource)

    case strategy do
      strategy when strategy in [:attribute, :context] ->
        not Ash.Resource.Info.multitenancy_global?(resource)

      _ ->
        false
    end
  end

  @doc """
  Determines if a resource should have tenant parameters in the generated TypeScript interface.

  This combines resource multitenancy requirements with the configuration setting.
  """
  def requires_tenant_parameter?(resource) do
    requires_tenant?(resource) && require_tenant_parameters?()
  end

  @spec run_action(otp_app :: atom, conn :: Plug.Conn.t(), params :: map) ::
          %{success: boolean, data: map() | nil, error: map() | nil}
  def run_action(otp_app, conn, params) do
    rpc_action =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.Rpc.Info.rpc(domain)
      end)
      |> Enum.find_value(fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.find_value(rpc_actions, fn action ->
          if to_string(action.name) == params["action"] do
            {resource, action}
          end
        end)
      end)

    case rpc_action do
      nil ->
        raise "not found"

      {resource, %{action: action}} ->
        action = Ash.Resource.Info.action(resource, action)

        tenant =
          if requires_tenant_parameter?(resource) do
            case Map.get(params, "tenant") do
              nil ->
                raise "Tenant parameter is required for resource #{inspect(resource)} but was not provided"

              tenant_value ->
                tenant_value
            end
          else
            Ash.PlugHelpers.get_tenant(conn)
          end

        opts = [
          actor: Ash.PlugHelpers.get_actor(conn),
          tenant: tenant,
          context: Ash.PlugHelpers.get_context(conn) || %{}
        ]

        # Parse client field names using new tree traversal approach
        client_fields = Map.get(params, "fields", [])

        # Use the new field parser for comprehensive field processing
        {select, load} = AshTypescript.Rpc.FieldParser.parse_requested_fields(
          client_fields, 
          resource, 
          input_field_formatter()
        )
        
        # Debug output to verify the new parser is working
        IO.inspect({select, load}, label: "New field parser output (select, load)")

        # Parse calculations parameter and enhanced calculations with field selection
        {calculations_load, calculation_field_specs} =
          parse_calculations_with_fields(
            Map.get(params, "calculations", %{}),
            resource
          )

        # Combine regular load and calculations load
        combined_load = load ++ calculations_load

        fields_to_take = select ++ combined_load

        # Parse input fields using the configured input formatter
        raw_input = Map.get(params, "input", %{})

        input =
          AshTypescript.FieldFormatter.parse_input_fields(raw_input, input_field_formatter())

        case action.type do
          :read ->
            query =
              resource
              |> Ash.Query.for_read(action.name, input, opts)
              |> Ash.Query.select(select)
              |> Ash.Query.load(combined_load)
              |> then(fn query ->
                if params["filter"] do
                  Ash.Query.filter_input(query, params["filter"])
                else
                  query
                end
              end)
              |> then(fn query ->
                if params["sort"] do
                  Ash.Query.sort_input(query, params["sort"])
                else
                  query
                end
              end)

            result = Ash.read(query)

            # Handle get actions that should return a single item
            case result do
              {:ok, [single_item]} when action.get? -> {:ok, single_item}
              other -> other
            end

          :create ->
            resource
            |> Ash.Changeset.for_create(action.name, input, opts)
            |> Ash.Changeset.select(select)
            |> Ash.Changeset.load(combined_load)
            |> Ash.create()

          :update ->
            # For update actions, we need to get the record first
            with {:ok, record} <- Ash.get(resource, params["primary_key"], opts) do
              record
              |> Ash.Changeset.for_update(action.name, input, opts)
              |> Ash.Changeset.select(select)
              |> Ash.Changeset.load(combined_load)
              |> Ash.update()
            end

          :destroy ->
            # For destroy actions, we need to get the record first
            with {:ok, record} <- Ash.get(resource, params["primary_key"], opts) do
              record
              |> Ash.Changeset.for_destroy(action.name, input, opts)
              |> Ash.Changeset.select(select)
              |> Ash.Changeset.load(combined_load)
              |> Ash.destroy()
            end

          :action ->
            resource
            |> Ash.ActionInput.for_action(action.name, input, opts)
            |> Ash.run_action()
        end
        |> case do
          :ok ->
            %{success: true, data: %{}}

          {:ok, result} ->
            return_value = extract_return_value(result, fields_to_take, calculation_field_specs)

            formatted_return_value =
              format_response_fields(return_value, output_field_formatter())

            %{success: true, data: formatted_return_value}

          {:error, error} ->
            %{success: false, errors: serialize_error(error)}
        end
    end
  end

  def extract_return_value(result, fields_to_take, calculation_field_specs)
       when is_struct(result) do
    extract_fields_from_map(result, fields_to_take, calculation_field_specs)
  end

  def extract_return_value(result, fields_to_take, calculation_field_specs)
       when is_map(result) do
    extract_fields_from_map(result, fields_to_take, calculation_field_specs)
  end

  def extract_return_value(result, fields_to_take, calculation_field_specs)
       when is_list(result) do
    Enum.map(result, fn res ->
      extract_return_value(res, fields_to_take, calculation_field_specs)
    end)
  end

  def extract_return_value(return_value, [], _calculation_field_specs), do: return_value

  def extract_return_value(_return_value, _list, _calculation_field_specs),
    do:
      {:error,
       "select and load lists must be empty when returning other values than a struct or map."}

  # Build embedded resource load entries using the same pattern as build_ash_load_entry
  defp build_embedded_resource_load_entries(load_list, resource) do
    # For now, let's just return the original format and see if embedded resources
    # can be loaded with the same syntax as relationships
    load_list
  end

  # Check if an attribute is an embedded resource
  defp is_embedded_resource_attribute?(resource, attribute_name) do
    case Ash.Resource.Info.attribute(resource, attribute_name) do
      nil -> 
        IO.inspect({resource, attribute_name, :not_found}, label: "Attribute not found")
        false
      attribute -> 
        result = is_embedded_resource_type?(attribute.type)
        IO.inspect({resource, attribute_name, attribute.type, result}, label: "Checking embedded resource type")
        result
    end
  end

  # Check if a type is an embedded resource type
  defp is_embedded_resource_type?(module) when is_atom(module) do
    try do
      Ash.Resource.Info.embedded?(module)
    rescue
      _ -> false
    end
  end

  defp is_embedded_resource_type?({:array, module}) when is_atom(module) do
    is_embedded_resource_type?(module)
  end

  defp is_embedded_resource_type?(_), do: false

  defp extract_fields_from_map(map, fields_to_take, calculation_field_specs) do
    Enum.reduce(fields_to_take, %{}, fn field_spec, acc ->
      case field_spec do
        # Simple field (atom)
        field when is_atom(field) ->
          if Map.has_key?(map, field) do
            value = Map.get(map, field)

            # Check if this field is a calculation with specific field selection
            case Map.get(calculation_field_specs, field) do
              nil ->
                # No special field selection for this calculation
                Map.put(acc, field, value)

              {calc_fields, nested_specs} ->
                # Apply field selection to the calculation result with nested specs
                # Include both simple fields and nested calculation fields
                nested_calc_fields = Map.keys(nested_specs)
                all_fields = calc_fields ++ nested_calc_fields
                filtered_value = extract_return_value(value, all_fields, nested_specs)
                # Format the filtered calculation result for client consumption
                formatted_value = format_response_fields(filtered_value, output_field_formatter())
                Map.put(acc, field, formatted_value)

              calc_fields when is_list(calc_fields) ->
                # Legacy format - simple field selection (backward compatibility)
                filtered_value = extract_return_value(value, calc_fields, %{})
                formatted_value = format_response_fields(filtered_value, output_field_formatter())
                Map.put(acc, field, formatted_value)
            end
          else
            acc
          end

        # Nested field as tuple {relation, nested_fields}
        {relation, nested_fields} when is_atom(relation) and is_list(nested_fields) ->
          if Map.has_key?(map, relation) do
            nested_value = Map.get(map, relation)

            extracted_nested =
              extract_return_value(nested_value, nested_fields, calculation_field_specs)

            Map.put(acc, relation, extracted_nested)
          else
            acc
          end

        # Nested field as keyword list entry
        [{key, nested_fields}] when is_atom(key) and is_list(nested_fields) ->
          if Map.has_key?(map, key) do
            nested_value = Map.get(map, key)

            extracted_nested =
              extract_return_value(nested_value, nested_fields, calculation_field_specs)

            Map.put(acc, key, extracted_nested)
          else
            acc
          end

        # Handle calculation with arguments: {calculation_name, arguments}
        {calc_name, _args} when is_atom(calc_name) ->
          if Map.has_key?(map, calc_name) do
            value = Map.get(map, calc_name)

            # Check if this calculation has specific field selection
            case Map.get(calculation_field_specs, calc_name) do
              nil ->
                # No special field selection for this calculation
                Map.put(acc, calc_name, value)

              {calc_fields, nested_specs} ->
                # Apply field selection to the calculation result with nested specs
                # Include both simple fields and nested calculation fields
                nested_calc_fields = Map.keys(nested_specs)
                all_fields = calc_fields ++ nested_calc_fields
                filtered_value = extract_return_value(value, all_fields, nested_specs)
                # Format the filtered calculation result for client consumption
                formatted_value = format_response_fields(filtered_value, output_field_formatter())
                Map.put(acc, calc_name, formatted_value)

              calc_fields when is_list(calc_fields) ->
                # Legacy format - simple field selection (backward compatibility)
                filtered_value = extract_return_value(value, calc_fields, %{})
                formatted_value = format_response_fields(filtered_value, output_field_formatter())
                Map.put(acc, calc_name, formatted_value)
            end
          else
            acc
          end

        # Handle any other format by trying to extract as simple field
        field ->
          if Map.has_key?(map, field) do
            Map.put(acc, field, Map.get(map, field))
          else
            acc
          end
      end
    end)
  end

  def validate_action(otp_app, conn, params) do
    rpc_action =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.Rpc.Info.rpc(domain)
      end)
      |> Enum.find_value(fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.find_value(rpc_actions, fn action ->
          if to_string(action.name) == params["action"] do
            {resource, action}
          end
        end)
      end)

    case rpc_action do
      nil ->
        raise "not found"

      {resource, %{action: action}} ->
        action = Ash.Resource.Info.action(resource, action)

        tenant =
          if requires_tenant_parameter?(resource) do
            case Map.get(params, "tenant") do
              nil ->
                raise "Tenant parameter is required for resource #{inspect(resource)} but was not provided"

              tenant_value ->
                tenant_value
            end
          else
            Ash.PlugHelpers.get_tenant(conn)
          end

        opts = [
          actor: Ash.PlugHelpers.get_actor(conn),
          tenant: tenant,
          context: Ash.PlugHelpers.get_context(conn) || %{}
        ]

        case action.type do
          action_type when action_type in [:update, :destroy] ->
            case Ash.get(resource, params["primary_key"], opts) do
              {:ok, record} ->
                result =
                  record
                  |> AshPhoenix.Form.for_action(action.name, opts)
                  |> AshPhoenix.Form.validate(params["input"])
                  |> AshPhoenix.Form.errors()
                  |> Enum.into(%{})

                if Enum.empty?(result) do
                  %{success: true}
                else
                  %{success: false, errors: result}
                end

              {:error, error} ->
                %{success: false, error: serialize_error(error)}
            end

          _ ->
            result =
              resource
              |> AshPhoenix.Form.for_action(action.name, opts)
              |> AshPhoenix.Form.validate(params["input"])
              |> AshPhoenix.Form.errors()
              |> Enum.into(%{})

            if Enum.empty?(result) do
              %{success: true}
            else
              %{success: false, errors: result}
            end
        end
    end
  end

  defp serialize_error(error) when is_exception(error) do
    %{
      class: error.class,
      message: Exception.message(error),
      errors: serialize_nested_errors(error.errors || []),
      path: error.path || []
    }
    |> add_error_fields(error)
  end

  defp serialize_error(error) when is_binary(error) do
    %{class: "unknown", message: error, errors: [], path: []}
  end

  defp serialize_error(error) do
    %{class: "unknown", message: inspect(error), errors: [], path: []}
  end

  defp serialize_nested_errors(errors) when is_list(errors) do
    Enum.map(errors, &serialize_single_error/1)
  end

  defp serialize_single_error(error) when is_exception(error) do
    %{
      message: Exception.message(error),
      field: Map.get(error, :field),
      fields: Map.get(error, :fields, []),
      path: Map.get(error, :path, [])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp serialize_single_error(error) do
    %{message: inspect(error)}
  end

  defp add_error_fields(base_map, error) do
    error
    |> Map.take([:field, :fields])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(base_map)
  end

  # Helper functions for nested calculation processing

  # Check if calculation returns an Ash resource
  defp is_resource_calculation?(calc_definition) do
    result =
      case calc_definition.type do
        Ash.Type.Struct ->
          # Check if constraints specify instance_of an Ash resource
          case Keyword.get(calc_definition.constraints || [], :instance_of) do
            module when is_atom(module) -> Ash.Resource.Info.resource?(module)
            _ -> false
          end

        _ ->
          false
      end

    result
  end

  # Get the resource that a calculation returns
  defp get_calculation_return_resource(calc_definition) do
    case calc_definition.type do
      Ash.Type.Struct ->
        # Check if constraints specify instance_of an Ash resource
        case Keyword.get(calc_definition.constraints || [], :instance_of) do
          module when is_atom(module) ->
            if Ash.Resource.Info.resource?(module) do
              {:ok, module}
            else
              :not_resource
            end

          _ ->
            :not_resource
        end

      _ ->
        :not_resource
    end
  end

  # Build Ash load entry in correct format
  defp build_ash_load_entry(calc_atom, args, fields, nested_load) do
    combined_load = fields ++ nested_load

    case {map_size(args), length(combined_load)} do
      {0, 0} -> calc_atom
      {0, _} -> {calc_atom, [fields: combined_load]}
      {_, 0} -> {calc_atom, args}
      # Ash tuple format
      {_, _} -> {calc_atom, {args, combined_load}}
    end
  end

  # Check if post-processing is needed
  defp needs_post_processing?(args, fields, nested_specs) do
    # Only need post-processing if we have args AND (fields or nested calculations)
    map_size(args) > 0 and (length(fields) > 0 or map_size(nested_specs) > 0)
  end

  # Parse field names and convert to load format
  defp parse_field_names_and_load(fields) do
    fields
    |> Enum.map(fn field ->
      case field do
        field when is_binary(field) ->
          AshTypescript.FieldFormatter.parse_input_field(field, input_field_formatter())

        field ->
          field
      end
    end)
    |> parse_json_load(input_field_formatter())
  end

  # Atomize calculation arguments
  defp atomize_calc_args(args) do
    Enum.reduce(args, %{}, fn {k, v}, acc ->
      Map.put(acc, String.to_existing_atom(k), v)
    end)
  end

  # Enhanced calculation parsing with recursive nested calculation support
  defp parse_calculations_with_fields(calculations, resource) when is_map(calculations) do
    resource_calculations = Ash.Resource.Info.calculations(resource)

    Enum.reduce(calculations, {[], %{}}, fn {calc_name, calc_spec}, {load_acc, specs_acc} ->
      calc_atom =
        AshTypescript.FieldFormatter.parse_input_field(calc_name, input_field_formatter())

      calc_definition = Enum.find(resource_calculations, &(&1.name == calc_atom))

      # Extract all components uniformly (regardless of what's present)
      # Use input field formatter to parse the calc args field name from client format
      calc_args_field = AshTypescript.FieldFormatter.format_field(:calc_args, output_field_formatter())
      args = Map.get(calc_spec, calc_args_field, %{}) |> atomize_calc_args()
      fields = Map.get(calc_spec, "fields", []) |> parse_field_names_and_load()
      nested_calcs = Map.get(calc_spec, "calculations", %{})

      # Handle nested calculations with direct recursion
      {nested_load, nested_specs} =
        if map_size(nested_calcs) > 0 and is_resource_calculation?(calc_definition) do
          {:ok, target_resource} = get_calculation_return_resource(calc_definition)
          # DIRECT RECURSIVE CALL - same function handles nesting naturally!
          parse_calculations_with_fields(nested_calcs, target_resource)
        else
          {[], %{}}
        end

      # Build load entry in correct Ash format
      load_entry = build_ash_load_entry(calc_atom, args, fields, nested_load)

      # Simple field specs - just track if we need post-processing
      field_spec =
        if needs_post_processing?(args, fields, nested_specs) do
          # Simple tuple instead of complex map
          {fields, nested_specs}
        else
          nil
        end

      updated_specs =
        if field_spec, do: Map.put(specs_acc, calc_atom, field_spec), else: specs_acc

      {[load_entry | load_acc], updated_specs}
    end)
    |> then(fn {load, specs} -> {Enum.reverse(load), specs} end)
  end

  defp parse_calculations_with_fields(_, _), do: {[], %{}}

  # Format response fields using the configured output formatter
  defp format_response_fields(data, formatter) when is_map(data) and not is_struct(data) do
    AshTypescript.FieldFormatter.format_fields(data, formatter)
  end

  defp format_response_fields(data, formatter) when is_struct(data) do
    data
    |> Map.from_struct()
    |> AshTypescript.FieldFormatter.format_fields(formatter)
  end

  defp format_response_fields(data, formatter) when is_list(data) do
    Enum.map(data, &format_response_fields(&1, formatter))
  end

  defp format_response_fields(data, _formatter), do: data
end
