# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.CompositeCustomTypeTest do
  # A composite custom type (`composite?/1` + `composite_types/1`, no other
  # field declaration) on a resource attribute: its entries are its fields,
  # through codegen and the RPC pipeline.
  use ExUnit.Case, async: false

  import AshTypescript.Test.CodegenTestHelper,
    only: [types_content: 1, zod_content: 1, valibot_content: 1]

  setup_all do
    {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
    %{types: types_content(files), zod: zod_content(files), valibot: valibot_content(files)}
  end

  defp lines(content), do: String.split(content, "\n")

  test "a composite type gets an alias and schemas", %{types: types, zod: zod, valibot: valibot} do
    assert "export type AshTypescriptTestCompositePoint = {x: number, y: number};" in lines(types)
    refute types =~ "AshTypescriptTestCompositePointInput"

    assert ("export const AshTypescriptTestCompositePointZodSchema = " <>
              "z.object({ x: z.number().int(), y: z.number().int() });") in lines(zod)

    assert ("export const AshTypescriptTestCompositePointValibotSchema = " <>
              "v.object({ x: v.pipe(v.number(), v.integer()), y: v.pipe(v.number(), v.integer()) });") in lines(
             valibot
           )
  end

  test "a composite value round-trips through RPC" do
    conn = %Plug.Conn{assigns: %{ash_actor: nil, ash_tenant: nil}}

    assert %{"success" => true, "data" => %{"id" => id, "position" => %{"x" => 1, "y" => 2}}} =
             AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
               "action" => "create_task",
               "input" => %{"title" => "Composite", "position" => %{"x" => 1, "y" => 2}},
               "fields" => ["id", %{"position" => ["x", "y"]}]
             })

    assert %{"success" => true, "data" => [%{"position" => %{"y" => 2}}]} =
             AshRpc.run_action(AshTypescript.RpcProfile, conn, %{
               "action" => "list_tasks",
               "filter" => %{"id" => %{"eq" => id}},
               "fields" => [%{"position" => ["y"]}]
             })
  end

  defmodule RaisingComposite do
    @moduledoc false
    use AshTypescript.Test.PassThroughType

    @impl true
    def composite?(_), do: true
    @impl true
    def composite_types(_), do: raise("no composite types today")
  end

  defmodule RaisingCompositeCheck do
    @moduledoc false
    use AshTypescript.Test.PassThroughType

    @impl true
    def composite?(_), do: raise("can't tell")
  end

  # One holder and domain per raising type, so each manifest meets one.
  for {holder, domain, type} <- [
        {__MODULE__.RaisingHolder, __MODULE__.RaisingDomain, RaisingComposite},
        {__MODULE__.RaisingCheckHolder, __MODULE__.RaisingCheckDomain, RaisingCompositeCheck}
      ] do
    defmodule holder do
      @moduledoc false
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name inspect(holder) |> String.split(".") |> List.last()
      end

      attributes do
        uuid_primary_key :id
        attribute :point, type, public?: true
      end

      actions do
        defaults [:read]
      end
    end

    defmodule domain do
      @moduledoc false
      use Ash.Domain,
        otp_app: :ash_typescript,
        extensions: [AshTypescript.Rpc],
        validate_config_inclusion?: false

      typescript_rpc do
        resource holder do
          rpc_action :list_holders, :read
        end
      end

      resources do
        resource holder
      end
    end
  end

  defp build_error(domain) do
    error =
      assert_raise RuntimeError, fn ->
        AshTypescript.Test.InlineManifest.build!(domains: [domain], body: nil)
      end

    Exception.message(error)
  end

  test "a raising composite_types/1 fails manifest compilation naming the type" do
    assert build_error(__MODULE__.RaisingDomain) =~
             "#{inspect(RaisingComposite)}.composite_types/1 raised: no composite types today"
  end

  test "a raising composite?/1 fails manifest compilation naming the type" do
    assert build_error(__MODULE__.RaisingCheckDomain) =~
             "#{inspect(RaisingCompositeCheck)}.composite?/1 raised: can't tell"
  end
end
