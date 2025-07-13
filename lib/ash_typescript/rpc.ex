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

        opts = [
          actor: Ash.PlugHelpers.get_actor(conn),
          tenant: Ash.PlugHelpers.get_tenant(conn),
          context: Ash.PlugHelpers.get_context(conn) || %{}
        ]

        attributes =
          Ash.Resource.Info.public_attributes(resource) |> Enum.map(fn a -> to_string(a.name) end)

        select =
          Map.get(params, "fields", [])
          |> Enum.filter(fn field -> field in attributes end)
          |> Enum.map(&String.to_existing_atom/1)

        load =
          Map.get(params, "fields", [])
          |> Enum.reject(fn field -> field in attributes end)
          |> parse_json_load()

        # Parse calculations parameter and enhanced calculations with field selection
        {calculations_load, calculation_field_specs} =
          parse_calculations_with_fields(
            Map.get(params, "calculations", %{}),
            resource
          )

        # Combine regular load and calculations load
        combined_load = load ++ calculations_load

        fields_to_take = select ++ combined_load

        input = Map.get(params, "input", %{})

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
            %{success: true, data: return_value}

          {:error, error} ->
            %{success: false, errors: serialize_error(error)}
        end
    end
  end

  defp extract_return_value(result, fields_to_take, calculation_field_specs)
       when is_struct(result) do
    extract_fields_from_map(result, fields_to_take, calculation_field_specs)
  end

  defp extract_return_value(result, fields_to_take, calculation_field_specs)
       when is_map(result) do
    extract_fields_from_map(result, fields_to_take, calculation_field_specs)
  end

  defp extract_return_value(result, fields_to_take, calculation_field_specs)
       when is_list(result) do
    Enum.map(result, fn res ->
      extract_return_value(res, fields_to_take, calculation_field_specs)
    end)
  end

  defp extract_return_value(return_value, [], _calculation_field_specs), do: return_value

  defp extract_return_value(_return_value, _list, _calculation_field_specs),
    do:
      {:error,
       "select and load lists must be empty when returning other values than a struct or map."}

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

              calc_fields ->
                # Apply field selection to the calculation result
                filtered_value = extract_return_value(value, calc_fields, calculation_field_specs)
                Map.put(acc, field, filtered_value)
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

        opts = [
          actor: Ash.PlugHelpers.get_actor(conn),
          tenant: Ash.PlugHelpers.get_tenant(conn),
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

  # Enhanced calculation parsing that separates regular loading from field selection specs
  defp parse_calculations_with_fields(calculations, resource) when is_map(calculations) do
    resource_calculations = Ash.Resource.Info.calculations(resource)

    {calculations_load, calculation_field_specs} =
      Enum.reduce(calculations, {[], %{}}, fn {calc_name, calc_spec}, {load_acc, specs_acc} ->
        calc_atom = String.to_existing_atom(calc_name)
        _calc_definition = Enum.find(resource_calculations, &(&1.name == calc_atom))

        case calc_spec do
          %{"calcArgs" => args, "fields" => fields} ->
            # For calculations with arguments and field selection, we load without field selection
            # and store the field spec for later application in extract_return_value
            args_atomized =
              Enum.reduce(args, %{}, fn {k, v}, acc ->
                Map.put(acc, String.to_existing_atom(k), v)
              end)

            # Store field specification for this calculation
            parsed_fields = parse_json_load(fields)
            updated_specs = Map.put(specs_acc, calc_atom, parsed_fields)

            # Return only the args for loading (no fields to avoid Ash validation issues)
            load_entry = {calc_atom, [args: args_atomized]}
            {[load_entry | load_acc], updated_specs}

          %{"fields" => fields} ->
            # Calculation without arguments, field selection can work normally
            parsed_fields = parse_json_load(fields)
            load_entry = {calc_atom, [fields: parsed_fields]}
            {[load_entry | load_acc], specs_acc}

          %{"calcArgs" => args} ->
            # Calculation with arguments but no field selection
            args_atomized =
              Enum.reduce(args, %{}, fn {k, v}, acc ->
                Map.put(acc, String.to_existing_atom(k), v)
              end)

            load_entry = {calc_atom, [args: args_atomized]}
            {[load_entry | load_acc], specs_acc}

          _ ->
            # Simple calculation without args or field selection
            {[calc_atom | load_acc], specs_acc}
        end
      end)

    {Enum.reverse(calculations_load), calculation_field_specs}
  end

  defp parse_calculations_with_fields(_, _), do: {[], %{}}
end
