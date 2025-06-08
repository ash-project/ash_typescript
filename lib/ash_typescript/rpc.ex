defmodule AshTypescript.RPC do
  import AshTypescript.RPC.Helpers
  require Ash.Query

  defmodule RPCAction do
    defstruct [:name, :action]
  end

  @rpc_action %Spark.Dsl.Entity{
    name: :rpc_action,
    target: RPCAction,
    schema: [
      name: [
        type: :atom,
        doc: "The name of the RPC-action"
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
    describe: "Define available RPC-actions for a resource",
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
    describe: "Define available RPC-actions for resources in this domain.",
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
        AshTypescript.RPC.Info.rpc(domain)
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
          params["fields"]
          |> Enum.filter(fn field -> field in attributes end)
          |> Enum.map(&String.to_existing_atom/1)

        load =
          params["fields"]
          |> Enum.reject(fn field -> field in attributes end)
          |> parse_json_load()

        fields_to_take = select ++ load

        input = params["input"] || %{}

        case action.type do
          :read ->
            query =
              resource
              |> Ash.Query.for_read(action.name, input, opts)
              |> Ash.Query.select(select)
              |> Ash.Query.load(load)
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
            |> Ash.Changeset.load(load)
            |> Ash.create()

          :update ->
            # For update actions, we need to get the record first
            with {:ok, record} <- Ash.get(resource, params["primary_key"], opts) do
              record
              |> Ash.Changeset.for_update(action.name, input, opts)
              |> Ash.Changeset.select(select)
              |> Ash.Changeset.load(load)
              |> Ash.update()
            end

          :destroy ->
            # For destroy actions, we need to get the record first
            with {:ok, record} <- Ash.get(resource, params["primary_key"], opts) do
              record
              |> Ash.Changeset.for_destroy(action.name, input, opts)
              |> Ash.Changeset.select(select)
              |> Ash.Changeset.load(load)
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
            return_value = extract_return_value(result, fields_to_take)
            %{success: true, data: return_value}

          {:error, error} ->
            %{success: false, errors: error}
        end
    end
  end

  defp extract_return_value(result, fields_to_take) when is_struct(result) do
    extract_fields_from_map(result, fields_to_take)
  end

  defp extract_return_value(result, fields_to_take) when is_map(result) do
    extract_fields_from_map(result, fields_to_take)
  end

  defp extract_return_value(result, fields_to_take) when is_list(result) do
    Enum.map(result, fn res -> extract_return_value(res, fields_to_take) end)
  end

  defp extract_return_value(return_value, []), do: return_value

  defp extract_return_value(_return_value, _list),
    do:
      {:error,
       "select and load lists must be empty when returning other values than a struct or map."}

  defp extract_fields_from_map(map, fields_to_take) do
    Enum.reduce(fields_to_take, %{}, fn field_spec, acc ->
      case field_spec do
        # Simple field (atom)
        field when is_atom(field) ->
          if Map.has_key?(map, field) do
            Map.put(acc, field, Map.get(map, field))
          else
            acc
          end

        # Nested field as tuple {relation, nested_fields}
        {relation, nested_fields} when is_atom(relation) and is_list(nested_fields) ->
          if Map.has_key?(map, relation) do
            nested_value = Map.get(map, relation)
            extracted_nested = extract_return_value(nested_value, nested_fields)
            Map.put(acc, relation, extracted_nested)
          else
            acc
          end

        # Nested field as keyword list entry
        [{key, nested_fields}] when is_atom(key) and is_list(nested_fields) ->
          if Map.has_key?(map, key) do
            nested_value = Map.get(map, key)
            extracted_nested = extract_return_value(nested_value, nested_fields)
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
        AshTypescript.RPC.Info.rpc(domain)
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
          :read ->
            {:error, "Cannot validate a read action"}

          :action ->
            {:error, "Cannot validate a generic action"}

          :create ->
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

          _ ->
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

              {:error, _} ->
                {:error, "Record not found"}
            end
        end
    end
  end
end
