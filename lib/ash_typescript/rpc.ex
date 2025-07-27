defmodule AshTypescript.Rpc do
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
        {select, load, extraction_template} =
          AshTypescript.Rpc.FieldParser.parse_requested_fields(
            client_fields,
            resource,
            input_field_formatter()
          )

        # For our enhanced field parser, the load statements already contain only loadable items
        # (calculations and relationships), so we can use them directly for Ash
        ash_load = load

        # Parse input fields using the configured input formatter
        raw_input = Map.get(params, "input", %{})

        # For get actions, add primary_key to input if provided
        raw_input_with_pk =
          if params["primary_key"] && Map.get(action, :get?) do
            Map.put(raw_input, "id", params["primary_key"])
          else
            raw_input
          end

        input =
          AshTypescript.FieldFormatter.parse_input_fields(
            raw_input_with_pk,
            input_field_formatter()
          )

        # Track whether pagination was explicitly requested (for all action types)
        pagination_requested = is_map(params["page"])

        case action.type do
          :read ->
            query =
              resource
              |> Ash.Query.for_read(action.name, input, opts)
              |> Ash.Query.select(select)
              |> Ash.Query.load(ash_load)
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
              |> then(fn query ->
                if pagination_requested do
                  # Parse page fields using the configured input formatter
                  parsed_page =
                    AshTypescript.FieldFormatter.parse_input_fields(
                      params["page"],
                      input_field_formatter()
                    )

                  Ash.Query.page(query, parsed_page)
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
            |> Ash.Changeset.load(ash_load)
            |> Ash.create()

          :update ->
            # For update actions, we need to get the record first
            with {:ok, record} <- Ash.get(resource, params["primary_key"], opts) do
              record
              |> Ash.Changeset.for_update(action.name, input, opts)
              |> Ash.Changeset.select(select)
              |> Ash.Changeset.load(ash_load)
              |> Ash.update()
            end

          :destroy ->
            # For destroy actions, we need to get the record first
            with {:ok, record} <- Ash.get(resource, params["primary_key"], opts) do
              record
              |> Ash.Changeset.for_destroy(action.name, input, opts)
              |> Ash.Changeset.select(select)
              |> Ash.Changeset.load(ash_load)
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
            processed_result =
              AshTypescript.Rpc.ResultProcessorNew.extract_fields(
                result,
                extraction_template,
                output_field_formatter()
              )


            %{success: true, data: processed_result}

          {:error, error} ->
            %{success: false, errors: serialize_error(error)}
        end
    end
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
end
