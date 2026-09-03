# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.EmbeddedGenericActionReturnTest do
  @moduledoc """
  Regression coverage for embedded resources that are only reachable through a
  generic action's `:returns` type (or through a generic action argument).

  These used to be referenced by the generated RPC file but never defined in the
  types file, so the output did not compile — the only workaround was adding a
  dummy calculation to make the embedded resource reachable some other way.

  Reachability now walks generic action return types, but only for the actions
  that are actually exposed as entrypoints. That distinction matters because
  reachability folds over its roots carrying a shared `visited` set: a root that
  was already reached as an *earlier* root's relationship destination does not
  get its structure walked a second time, and only gets its action surface
  walked if the entry names actions explicitly. So the shape that regresses is
  **two RPC resources where the earlier one relates to the later one** — the
  resource holding the generic action is already visited by the time its own
  root entry comes up. `Related` below exists purely to create that ordering;
  with `Holder` as the only RPC resource every assertion here passes even when
  the underlying discovery is broken.

  The domain, resources and manifest are declared inline rather than added to
  `test/support` so the committed `test/ts` fixtures stay untouched — the point
  is to prove reachability, not to grow the shared fixture set.
  """

  # Mutates the global :manifest config, so must not run async.
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  defmodule NestedEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "NestedEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false
    end
  end

  defmodule StructReturnEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "StructReturnEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false

      # Reachable only through the embedded resource above, which is itself
      # reachable only through a generic action return type.
      attribute :nested,
                AshTypescript.EmbeddedGenericActionReturnTest.NestedEmbedded,
                public?: true
    end
  end

  defmodule ArrayReturnEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "ArrayReturnEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false
    end
  end

  defmodule ArgumentEmbedded do
    use Ash.Resource, data_layer: :embedded, domain: nil, extensions: [AshTypescript.Resource]

    typescript do
      type_name "ArgumentEmbedded"
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, public?: true, allow_nil?: false
    end
  end

  defmodule Holder do
    use Ash.Resource,
      domain: AshTypescript.EmbeddedGenericActionReturnTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "Holder"
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read]

      # Embedded resource reachable *only* through this action's return type,
      # named as a module.
      action :build_embedded,
             AshTypescript.EmbeddedGenericActionReturnTest.StructReturnEmbedded do
        public? true

        run fn _input, _ctx ->
          {:ok, %AshTypescript.EmbeddedGenericActionReturnTest.StructReturnEmbedded{}}
        end
      end

      # Same, but declared as `:struct` with an `instance_of` constraint.
      action :build_struct, :struct do
        public? true

        constraints instance_of:
                      AshTypescript.EmbeddedGenericActionReturnTest.StructReturnEmbedded

        run fn _input, _ctx ->
          {:ok, %AshTypescript.EmbeddedGenericActionReturnTest.StructReturnEmbedded{}}
        end
      end

      action :build_struct_list, {:array, :struct} do
        public? true

        constraints items: [
                      instance_of:
                        AshTypescript.EmbeddedGenericActionReturnTest.ArrayReturnEmbedded
                    ]

        run fn _input, _ctx -> {:ok, []} end
      end

      action :accept_struct, :string do
        public? true

        argument :payload, :struct,
          allow_nil?: false,
          constraints: [
            instance_of: AshTypescript.EmbeddedGenericActionReturnTest.ArgumentEmbedded
          ]

        run fn _input, _ctx -> {:ok, "ok"} end
      end
    end
  end

  defmodule Related do
    @moduledoc """
    A second RPC resource that relates to `Holder`. Declared before `Holder` in
    the domain so reachability reaches `Holder` as a relationship destination
    first, marking it visited before its own root entry is folded over.
    """
    use Ash.Resource,
      domain: AshTypescript.EmbeddedGenericActionReturnTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "Related"
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
    end

    relationships do
      belongs_to :holder, AshTypescript.EmbeddedGenericActionReturnTest.Holder do
        public? true
        attribute_writable? true
      end
    end

    actions do
      defaults [:read]
    end
  end

  defmodule Domain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      # Order is load-bearing: see the moduledoc.
      resource AshTypescript.EmbeddedGenericActionReturnTest.Related do
        rpc_action :list_related, :read
      end

      resource AshTypescript.EmbeddedGenericActionReturnTest.Holder do
        rpc_action :list_holders, :read
        rpc_action :build_embedded, :build_embedded
        rpc_action :build_struct, :build_struct
        rpc_action :build_struct_list, :build_struct_list
        rpc_action :accept_struct, :accept_struct
      end
    end

    resources do
      resource AshTypescript.EmbeddedGenericActionReturnTest.Related
      resource AshTypescript.EmbeddedGenericActionReturnTest.Holder
    end
  end

  defmodule Manifest do
    use AshTypescript.Manifest,
      otp_app: :ash_typescript,
      domains: [AshTypescript.EmbeddedGenericActionReturnTest.Domain]
  end

  # Codegen resolves resources through `Ash.Info.domains/1`, so generation runs
  # against a dedicated otp_app to keep the shared test domains out of the way.
  @otp_app :embedded_generic_action_return_test_app

  setup do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :manifest,
      :typed_controllers,
      :typed_channels
    ])

    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:ash_domains], @otp_app)

    Application.put_env(:ash_typescript, :manifest, Manifest)
    Application.put_env(:ash_typescript, :typed_controllers, [])
    Application.put_env(:ash_typescript, :typed_channels, [])
    Application.put_env(@otp_app, :ash_domains, [Domain])

    {:ok, files} = AshTypescript.Codegen.Orchestrator.generate(@otp_app, [])

    types_content =
      files
      |> Enum.filter(fn {path, _} -> String.ends_with?(path, "ash_types.ts") end)
      |> Enum.map_join("\n", fn {_, content} -> content end)

    rpc_content =
      files
      |> Enum.filter(fn {path, _} -> String.ends_with?(path, "generated.ts") end)
      |> Enum.map_join("\n", fn {_, content} -> content end)

    refute types_content == "", "no types file was generated"
    refute rpc_content == "", "no RPC file was generated"

    %{types: types_content, rpc: rpc_content}
  end

  test "the domain really does reach the generic action's resource by relationship first" do
    # Guards the premise of every other test in this module: if `Related` stops
    # reaching `Holder` before `Holder`'s own root entry, these tests silently
    # stop covering the bug they exist for.
    rpc_resources = AshTypescript.Codegen.TypeDiscovery.get_rpc_resources(@otp_app)

    assert rpc_resources == [Related, Holder],
           "expected Related to be folded over before Holder, got #{inspect(rpc_resources)}"

    assert Enum.any?(
             Ash.Resource.Info.public_relationships(Related),
             &(&1.destination == Holder)
           ),
           "expected Related to reach Holder through a public relationship"
  end

  test "embedded resource named as a generic action's return type is defined, not just referenced",
       %{types: types, rpc: rpc} do
    assert types =~ "export type StructReturnEmbeddedResourceSchema = {"
    assert rpc =~ "StructReturnEmbeddedResourceSchema"
  end

  test "embedded resource returned via :struct + instance_of is defined", %{rpc: rpc} do
    # Both generic actions return the same embedded resource, so this asserts on
    # the RPC side; the schema definition is covered by the test above.
    assert rpc =~ "BuildStructFields = UnifiedFieldSelection<StructReturnEmbeddedResourceSchema>"
  end

  test "embedded resource in a generic action's array return type is defined", %{
    types: types,
    rpc: rpc
  } do
    assert types =~ "export type ArrayReturnEmbeddedResourceSchema = {"
    assert rpc =~ "ArrayReturnEmbeddedResourceSchema"
  end

  test "embedded resource used as a generic action argument is defined", %{types: types} do
    assert types =~ "export type ArgumentEmbeddedInputSchema = {"
  end

  test "embedded resource nested inside a returned embedded resource is defined", %{types: types} do
    # The subtree below a return type has to be walked too, not just the return
    # type itself.
    assert types =~ "export type NestedEmbeddedResourceSchema = {"
  end

  test "every embedded schema the RPC file imports from the types file exists there", %{
    types: types,
    rpc: rpc
  } do
    imported =
      Regex.scan(~r/import type \{([^}]*)\} from "\.\/ash_types"/, rpc)
      |> Enum.flat_map(fn [_, names] -> String.split(names, ",") end)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    refute imported == [], "expected the RPC file to import types from the types file"

    missing = Enum.reject(imported, &String.contains?(types, "export type #{&1}"))

    assert missing == [],
           "RPC file imports names that the types file never defines: #{inspect(missing)}"
  end

  test "every schema name the RPC file mentions is defined in the types file", %{
    types: types,
    rpc: rpc
  } do
    # Stronger than the import check above: a dropped schema can also show up as
    # a bare reference the import list never mentions, which is still the
    # `TS2304: Cannot find name` the reporter hit.
    referenced =
      Regex.scan(~r/\b([A-Z][A-Za-z0-9_]*(?:ResourceSchema|InputSchema))\b/, rpc)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.uniq()

    refute referenced == [], "expected the RPC file to reference resource schemas"

    missing = Enum.reject(referenced, &String.contains?(types, "export type #{&1} ="))

    assert missing == [],
           "RPC file references names that the types file never defines: #{inspect(missing)}"
  end
end
