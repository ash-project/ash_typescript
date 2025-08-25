defmodule AshTypescript.Rpc do
  @moduledoc false

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

  use Spark.Dsl.Extension,
    sections: [@rpc],
    verifiers: [AshTypescript.Rpc.VerifyRpc]

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
  Determines if Zod schema generation is enabled.

  When true, generates Zod schemas alongside TypeScript types for runtime validation.
  Defaults to false (opt-in feature).
  """
  def generate_zod_schemas? do
    Application.get_env(:ash_typescript, :generate_zod_schemas, false)
  end

  @doc """
  Gets the Zod import path for generated TypeScript.

  This determines the import statement used in generated TypeScript files.
  Defaults to "zod" for standard npm package.
  Can be customized for different package managers or custom Zod builds.
  """
  def zod_import_path do
    Application.get_env(:ash_typescript, :zod_import_path, "zod")
  end

  @doc """
  Gets the suffix used for generated Zod schema constants.

  This determines the naming pattern for Zod schemas.
  Defaults to "Schema" (e.g., createTodoSchema).
  """
  def zod_schema_suffix do
    Application.get_env(:ash_typescript, :zod_schema_suffix, "ZodSchema")
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
    requires_tenant?(resource) and require_tenant_parameters?()
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
    case Pipeline.parse_request(otp_app, conn, params, validation_mode?: true) do
      {:ok, parsed_request} ->
        validate_form_input(parsed_request)

      {:error, reason} ->
        %{success: false, errors: [ErrorBuilder.build_error_response(reason)]}
    end
    |> Pipeline.format_output()
  end

  defp validate_form_input(%{action: action, resource: resource, input: input} = request) do
    opts = [
      actor: request.actor,
      tenant: request.tenant,
      context: request.context
    ]

    case action.type do
      :read ->
        # For read actions, validate by building a query
        validate_read_action(resource, action, input, opts)

      action_type when action_type in [:update, :destroy] ->
        case Ash.get(resource, request.primary_key, opts) do
          {:ok, record} ->
            perform_form_validation(record, action.name, input, opts)

          {:error, error} ->
            %{success: false, errors: [ErrorBuilder.build_error_response(error)]}
        end

      _ ->
        perform_form_validation(resource, action.name, input, opts)
    end
  end

  defp validate_read_action(resource, action, input, opts) do
    # For read actions, validate by building a query
    try do
      query =
        resource
        |> Ash.Query.for_read(action.name, input, opts)

      # If we can build the query without errors, validation passes
      case query do
        %Ash.Query{errors: []} ->
          %{success: true}

        %Ash.Query{errors: errors} when errors != [] ->
          formatted_errors =
            errors
            |> Enum.map(fn error ->
              %{
                type: "validation_error",
                message: Exception.message(error)
              }
            end)

          %{success: false, errors: formatted_errors}

        _ ->
          %{success: true}
      end
    rescue
      e ->
        %{
          success: false,
          errors: [
            %{
              type: "validation_error",
              message: Exception.message(e)
            }
          ]
        }
    end
  end

  defp perform_form_validation(record_or_resource, action_name, input, opts) do
    form_errors =
      record_or_resource
      |> AshPhoenix.Form.for_action(action_name, opts)
      |> AshPhoenix.Form.validate(input)
      |> AshPhoenix.Form.errors()

    if Enum.empty?(form_errors) do
      %{success: true}
    else
      formatted_errors =
        form_errors
        |> Enum.map(fn {field, messages} ->
          formatted_messages =
            messages
            |> List.wrap()
            |> Enum.map(&to_string/1)

          %{
            type: "validation_error",
            field: to_string(field),
            errors: formatted_messages
          }
        end)

      %{success: false, errors: formatted_errors}
    end
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
    with {:ok, typed_query} <- find_typed_query(otp_app, typed_query_name) do
      rpc_params = %{
        "typed_query_action" => Atom.to_string(typed_query_name),
        "fields" => typed_query.fields
      }

      rpc_params =
        rpc_params
        |> maybe_add_param("input", params[:input])
        |> maybe_add_param("page", params[:page])
        |> maybe_add_param("filter", params[:filter])
        |> maybe_add_param("sort", params[:sort])

      run_action(otp_app, conn, rpc_params)
    else
      error -> error
    end
  end

  defp find_typed_query(otp_app, typed_query_name) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.reduce_while({:error, {:typed_query_not_found, typed_query_name}}, fn domain, _acc ->
      rpc_config = AshTypescript.Rpc.Info.rpc(domain)

      Enum.find_value(rpc_config, fn %{typed_queries: typed_queries} ->
        Enum.find(typed_queries, &(&1.name == typed_query_name))
      end)
      |> case do
        nil -> {:cont, {:error, {:typed_query_not_found, typed_query_name}}}
        found -> {:halt, {:ok, found}}
      end
    end)
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)
end
