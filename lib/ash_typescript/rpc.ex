defmodule AshTypescript.Rpc do
  @moduledoc """
  Next-generation RPC processing pipeline with clean architecture and strict validation.

  This is a complete rewrite focused on:
  - Performance: 50%+ improvement over current implementation
  - Strict validation: Fail-fast on all invalid inputs
  - Clean architecture: Pure functional pipeline
  - Single responsibility: Clear separation of concerns

  Pipeline: parse_input -> execute_action -> filter_result -> format_output
  """

  # DSL structures for Spark extension
  defmodule RpcAction do
    defstruct [:name, :action]
  end

  defmodule Resource do
    defstruct [:resource, rpc_actions: [], typed_queries: []]
  end

  defmodule TypedQuery do
    defstruct [:name, :ts_result_type_name, :ts_fields_const_name, :resource, :action, :fields]
  end

  @typed_query %Spark.Dsl.Entity{
    name: :typed_query,
    target: TypedQuery,
    schema: [
      action: [
        type: :atom,
        doc: "The read action on the resource to query"
      ],
      name: [
        type: :atom,
        doc: "The name of the RPC-action"
      ],
      ts_result_type_name: [
        type: :string,
        doc: "The name of the TypeScript type for the query result"
      ],
      ts_fields_const_name: [
        type: :string,
        doc:
          "The name of the constant for the fields, that can be reused by the client to re-run the query"
      ],
      fields: [
        type: {:list, :any},
        doc: "The fields to query"
      ]
    ],
    args: [:name, :action]
  }

  @rpc_action %Spark.Dsl.Entity{
    name: :rpc_action,
    target: RpcAction,
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
      rpc_actions: [@rpc_action],
      typed_queries: [@typed_query]
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

  alias AshTypescript.Rpc.{Pipeline, ErrorBuilder}

  @doc """
  Determines if tenant parameters are required in RPC requests.

  This checks the application configuration for :require_tenant_parameters.
  If true (default), tenant parameters are required for multitenant resources.
  If false, tenant will be extracted from the connection using Ash.PlugHelpers.get_tenant/1.
  """
  def require_tenant_parameters? do
    Application.get_env(:ash_typescript, :require_tenant_parameters, false)
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

  @doc """
  Main entry point for the new RPC processing pipeline.

  ## Parameters
  - `otp_app` - The OTP application atom
  - `conn` - The Plug connection
  - `params` - Request parameters map

  ## Returns
  - `{:ok, result}` - Successfully processed result
  - `{:error, reason}` - Processing error with detailed message

  ## Error Handling
  This implementation uses strict validation and fails fast on any invalid input.
  No permissive modes - all errors are reported immediately.
  """
  @spec run_action(atom(), Plug.Conn.t(), map()) :: map()
  def run_action(otp_app, conn, params) do
    with {:ok, parsed_request} <- Pipeline.parse_request(otp_app, conn, params),
         {:ok, ash_result} <- Pipeline.execute_ash_action(parsed_request),
         {:ok, processed_result} <- Pipeline.process_result(ash_result, parsed_request) do
      %{success: true, data: processed_result}
    else
      {:error, reason} ->
        %{success: false, errors: [ErrorBuilder.build_error_response(reason)]}
    end
    |> Pipeline.format_output()
  end

  @doc """
  Validates action parameters without execution.
  Used for form validation in the client.
  """
  @spec validate_action(atom(), Plug.Conn.t(), map()) ::
          {:ok, map()} | {:error, map()}
  def validate_action(otp_app, conn, params) do
    case Pipeline.parse_request(otp_app, conn, params) do
      {:ok, _parsed_request} ->
        %{success: true}

      {:error, reason} ->
        %{success: false, errors: [ErrorBuilder.build_error_response(reason)]}
    end
    |> Pipeline.format_output()
  end

  @doc """
  Runs a typed query for server-side rendering and data fetching.

  This function looks up a typed query by name and executes it with the configured fields,
  returning the data in the exact shape defined by the typed query. This is ideal for
  SSR controllers that need to pre-fetch data with type safety.

  ## Parameters
  - `otp_app` - The OTP application name
  - `typed_query_name` - The atom name of the typed query to execute  
  - `params` - Map with optional `:input` and `:page` keys
  - `conn` - The Plug connection (for tenant context, etc.)

  ## Returns
  - `{:ok, data}` - Successfully executed typed query with processed results
  - `{:error, reason}` - Error during lookup or execution

  ## Example
      # In a Phoenix controller
      def index(conn, _params) do
        case AshTypescript.Rpc.run_typed_query(:my_app, :list_todos_user_page, %{}, conn) do
          {:ok, todos} ->
            render(conn, "index.html", initial_todos: todos)
          {:error, reason} ->
            # Handle error appropriately
            send_resp(conn, 500, "Error loading data")
        end
      end
  """
  @spec run_typed_query(atom(), atom(), map(), Plug.Conn.t()) :: {:ok, any()} | {:error, any()}
  def run_typed_query(otp_app, typed_query_name, params \\ %{}, conn) do
    with {:ok, {resource, action, typed_query}} <- find_typed_query(otp_app, typed_query_name),
         {:ok, rpc_action} <- find_rpc_action_for_typed_query(otp_app, resource, action.name) do
      
      # Build RPC parameters with the typed query's fields and RPC action name
      rpc_params = %{
        "action" => Atom.to_string(rpc_action.name),
        "fields" => typed_query.fields
      }
      
      # Add input and page if provided
      rpc_params = 
        rpc_params
        |> maybe_add_param("input", params[:input])
        |> maybe_add_param("page", params[:page])
      
      # Execute using the existing run_action pipeline
      case run_action(otp_app, conn, rpc_params) do
        %{"success" => true, "data" => data} -> {:ok, data}
        %{"success" => false, "errors" => errors} -> {:error, {:rpc_errors, errors}}
        other -> {:error, {:unexpected_response, other}}
      end
    end
  end

  # Helper function to find a typed query by name across all domains
  defp find_typed_query(otp_app, typed_query_name) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.reduce_while({:error, :not_found}, fn domain, _acc ->
      rpc_config = AshTypescript.Rpc.Info.rpc(domain)
      
      result = 
        Enum.find_value(rpc_config, fn %{resource: resource, typed_queries: typed_queries} ->
          case Enum.find(typed_queries, &(&1.name == typed_query_name)) do
            nil -> nil
            typed_query -> 
              action = Ash.Resource.Info.action(resource, typed_query.action)
              {resource, action, typed_query}
          end
        end)

      case result do
        nil -> {:cont, {:error, :not_found}}
        found -> {:halt, {:ok, found}}
      end
    end)
    |> case do
      {:error, :not_found} -> 
        {:error, {:typed_query_not_found, typed_query_name}}
      result -> 
        result
    end
  end

  # Helper function to find the corresponding RPC action for a typed query
  defp find_rpc_action_for_typed_query(otp_app, resource, action_name) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.reduce_while({:error, :not_found}, fn domain, _acc ->
      rpc_config = AshTypescript.Rpc.Info.rpc(domain)
      
      result = 
        Enum.find_value(rpc_config, fn %{resource: ^resource, rpc_actions: rpc_actions} ->
          Enum.find(rpc_actions, &(&1.action == action_name))
        end)

      case result do
        nil -> {:cont, {:error, :not_found}}
        found -> {:halt, {:ok, found}}
      end
    end)
    |> case do
      {:error, :not_found} -> 
        {:error, {:rpc_action_not_found, {resource, action_name}}}
      result -> 
        result
    end
  end

  # Helper to add optional parameters
  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)
end
