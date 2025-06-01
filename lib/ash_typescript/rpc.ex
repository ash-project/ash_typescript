defmodule AshTypescript.RPC do
  alias AshTypescript.Helpers

  defmodule RPCAction do
    defstruct [:name, :action]
  end

  @rpc_action %Spark.Dsl.Entity{
    name: :rpc_action,
    target: RPCAction,
    schema: [
      name: [
        type: :atom,
        doc: "The name of the RPC-action`"
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

        select = Helpers.parse_json_select_and_load(params["select"])
        load = Helpers.parse_json_select_and_load(params["load"])

        root_loads = Enum.reject(load, &is_tuple/1)
        fields_to_take = select ++ root_loads

        case action.type do
          :read ->
            resource
            |> Ash.Query.for_read(action.name, params["input"], opts)
            |> Ash.Query.select(select)
            |> Ash.Query.load(load)
            |> Ash.read()

          :create ->
            resource
            |> Ash.Changeset.for_create(action.name, params["input"], opts)
            |> Ash.Changeset.select(select)
            |> Ash.Changeset.load(load)
            |> Ash.create()

          :update ->
            resource
            |> Ash.Changeset.for_update(action.name, params["input"], opts)
            |> Ash.Changeset.select(select)
            |> Ash.Changeset.load(load)
            |> Ash.update()

          :destroy ->
            resource
            |> Ash.Changeset.for_destroy(action.name, params["input"], opts)
            |> Ash.Changeset.select(select)
            |> Ash.Changeset.load(load)
            |> Ash.destroy()

          :action ->
            resource
            |> Ash.Changeset.for_action(action.name, params["input"], opts)
            |> Ash.run_action()
        end
        |> case do
          {:ok, result} ->
            result =
              if is_list(result) do
                Enum.map(result, fn res -> Map.take(res, fields_to_take) end)
              else
                Map.take(result, fields_to_take)
              end

            %{success: true, data: result, error: nil}

          {:error, error} ->
            %{success: false, data: nil, error: error}
        end
    end
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
            resource
            |> AshPhoenix.Form.for_action(action.name, opts)
            |> AshPhoenix.Form.validate(params["input"])
            |> AshPhoenix.Form.errors()
            |> Enum.into(%{})

          _ ->
            primary_key = Ash.Resource.Info.primary_key(resource)
            primary_key_as_strings = Enum.map(primary_key, &to_string/1)
            params_pkey_fields = Map.keys(params["primary_key"])

            with true <-
                   Enum.all?(primary_key_as_strings, fn pkey ->
                     pkey in params_pkey_fields
                   end),
                 pkey <- Map.take(params["primary_key"], primary_key_as_strings),
                 {:ok, record} <- Ash.get(resource, pkey, opts) do
              record
              |> AshPhoenix.Form.for_action(action.name, opts)
              |> AshPhoenix.Form.validate(params["input"])
              |> AshPhoenix.Form.errors()
              |> Enum.into(%{})
            else
              false -> {:error, "Invalid primary key"}
              {:error, _} -> {:error, "Record not found"}
            end
        end
    end
  end
end
