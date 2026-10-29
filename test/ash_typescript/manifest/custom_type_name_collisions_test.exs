# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.CustomTypeNameCollisionsTest do
  # Collisions of declared custom types' alias and schema names: the manifest
  # verifier `VerifyCustomTypeNames` (alias vs alias, vs another's `Input`
  # name, vs resource-derived and fixed generated names) and the codegen
  # backstop (duplicate `export type`, imported-and-declared names,
  # `import_name`s). Manifests are compiled with `Module.create/3` under fixed
  # names.
  use ExUnit.Case, async: false

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.{CustomTypeAliases, ScalarAliases}
  alias AshTypescript.Manifest.{Custom, TypeUses}
  alias AshTypescript.Manifest.CustomTypeNameCollisionsTest, as: T
  alias AshTypescript.Manifest.Verifiers.VerifyCustomTypeNames
  alias AshTypescript.Test.CodegenTestHelper

  defmodule MapStorage do
    @moduledoc false
    defmacro __using__(_) do
      quote do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end
    end
  end

  defmodule Billing.Money do
    @moduledoc false
    use MapStorage
  end

  defmodule Shop.Money do
    @moduledoc false
    use MapStorage
  end

  defmodule Decimal do
    @moduledoc false
    use MapStorage
  end

  defmodule InferResult do
    @moduledoc false
    use MapStorage
  end

  defmodule CollisionHolderResourceSchema do
    @moduledoc false
    use MapStorage
  end

  defmodule Shade do
    @moduledoc false
    use MapStorage
  end

  defmodule ShadeInput do
    @moduledoc false
    use MapStorage
  end

  defmodule SwatchInputSchema do
    @moduledoc false
    use MapStorage
  end

  # An embedded resource: in `manifest.types`, not `manifest.resources`.
  defmodule Swatch do
    @moduledoc false
    use Ash.Resource, data_layer: :embedded, extensions: [AshTypescript.Resource]

    typescript do
      type_name "Swatch"
    end

    attributes do
      attribute :hex, :string, public?: true
    end
  end

  # Read through an RPC action, so every attribute's type is on the wire and
  # needs its `map` entry.
  defmodule Holder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "CollisionHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :billing_money, T.Billing.Money, public?: true
      attribute :shop_money, T.Shop.Money, public?: true
      attribute :decimal, T.Decimal, public?: true
      attribute :infer_result, T.InferResult, public?: true
      attribute :resource_schema, T.CollisionHolderResourceSchema, public?: true
      attribute :shade, T.Shade, public?: true
      attribute :shade_input, T.ShadeInput, public?: true
      attribute :swatch_input_schema, T.SwatchInputSchema, public?: true
      attribute :swatch, T.Swatch, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule HolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :list_collision_holders, :read
      end
    end

    resources do
      resource T.Holder
    end
  end

  defmodule StringStorage do
    @moduledoc false
    defmacro __using__(_) do
      quote do
        use Ash.Type

        @impl true
        def storage_type(_), do: :string
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end
    end
  end

  # Scalars named by their `scalar` entries.
  defmodule ScalarA do
    @moduledoc false
    use StringStorage
  end

  defmodule ScalarB do
    @moduledoc false
    use StringStorage
  end

  defmodule MfaScalar do
    @moduledoc false
    use StringStorage
  end

  defmodule MfaNames do
    @moduledoc false
    def ts_type(_constraints), do: "string"
    def ts_alias(_constraints), do: "Decimal"
  end

  # A declared custom type named by its callback, with an `Input` name.
  defmodule Tint do
    @moduledoc false
    use MapStorage

    def typescript_fields, do: [hex: [type: :string, allow_nil?: false]]
    def typescript_type_alias, do: "Tint"
  end

  # NewTypes over a primitive named by their callback.
  defmodule NamedA do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string

    def typescript_type_alias, do: "SameName"
  end

  defmodule NamedB do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string

    def typescript_type_alias, do: "SameName"
  end

  defmodule ScalarHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "CollisionScalarHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :scalar_a, T.ScalarA, public?: true
      attribute :scalar_b, T.ScalarB, public?: true
      attribute :mfa, T.MfaScalar, public?: true
      attribute :money, AshMoney.Types.Money, public?: true
      attribute :tint, T.Tint, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule ScalarHolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.ScalarHolder do
        rpc_action :list_collision_scalar_holders, :read
      end
    end

    resources do
      resource T.ScalarHolder
    end
  end

  defmodule CallbackHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "CollisionCallbackHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :named_a, T.NamedA, public?: true
      attribute :named_b, T.NamedB, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule CallbackHolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.CallbackHolder do
        rpc_action :list_collision_callback_holders, :read
      end
    end

    resources do
      resource T.CallbackHolder
    end
  end

  # Each type's `ts_alias` unless a test overrides it: distinct, so only the
  # pair under test collides. `:derive` leaves `ts_alias` out (the joined
  # module name).
  @distinct %{
    T.Billing.Money => "BillingMoneyAlias",
    T.Shop.Money => "ShopMoneyAlias",
    T.Decimal => "DecimalAlias",
    T.InferResult => "InferResultAlias",
    T.CollisionHolderResourceSchema => "ResourceSchemaAlias",
    T.Shade => "ShadeAlias",
    T.ShadeInput => "ShadeInputAlias",
    T.SwatchInputSchema => "SwatchInputSchemaAlias"
  }

  @fix "Rename one of them as each line says."

  @rename "with `ts_alias \"…\"` on its `map` entry (or `typescript_type_alias/0` on the type, " <>
            "when no entry sets `ts_alias`)"

  # The scoped manifest prints the RPC resource warnings and the verifier's
  # diagnostics; they're captured.
  defp manifest!(name, type_names) do
    module = Module.concat(T, name)

    entries =
      @distinct
      |> Map.merge(type_names)
      |> Enum.sort_by(fn {module, _} -> inspect(module) end)
      |> Enum.map(fn {type, ts_alias} -> map_entry(type, ts_alias) end)

    unless Code.ensure_loaded?(module) do
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Module.create(
          module,
          quote do
            use AshTypescript.Manifest,
              otp_app: :ash_typescript,
              domains: [AshTypescript.Manifest.CustomTypeNameCollisionsTest.HolderDomain]

            custom_types do
              (unquote_splicing(entries))
            end
          end,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    module
  end

  defp map_entry(type, :derive) do
    quote do
      map unquote(type) do
        field :value, :string
      end
    end
  end

  defp map_entry(type, ts_alias) do
    quote do
      map unquote(type) do
        ts_alias unquote(ts_alias)
        field :value, :string
      end
    end
  end

  @scalar_rename "with `ts_alias \"…\"` on its `scalar` entry (or `typescript_type_alias/0` on " <>
                   "the type, when no entry sets `ts_alias`)"

  # A manifest over `domain` with the `custom_types` `body`, compiled once.
  defp scalar_manifest!(name, domain, body) do
    module = Module.concat(T, name)

    unless Code.ensure_loaded?(module) do
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Module.create(
          module,
          quote do
            use AshTypescript.Manifest, otp_app: :ash_typescript, domains: [unquote(domain)]

            unquote(body)
          end,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    module
  end

  # The `ScalarHolder` entries: `ScalarA` and `ScalarB` named by `names`
  # (unnamed when absent), `MfaScalar` named by an MFA returning `Decimal`.
  defp scalar_holder_manifest!(name, names) do
    scalar = fn module ->
      case Map.fetch(names, module) do
        {:ok, ts_alias} ->
          quote(do: scalar(unquote(module), :string, ts_alias: unquote(ts_alias)))

        :error ->
          quote(do: scalar(unquote(module), :string))
      end
    end

    scalar_manifest!(
      name,
      T.ScalarHolderDomain,
      quote do
        custom_types do
          unquote(scalar.(T.ScalarA))
          unquote(scalar.(T.ScalarB))

          scalar AshTypescript.Manifest.CustomTypeNameCollisionsTest.MfaScalar, :string do
            ts_type {AshTypescript.Manifest.CustomTypeNameCollisionsTest.MfaNames, :ts_type, []}
            ts_alias {AshTypescript.Manifest.CustomTypeNameCollisionsTest.MfaNames, :ts_alias, []}
          end
        end
      end
    )
  end

  defp collision_error!(name, type_names) do
    assert {:error, message} = AshTypescript.Manifest.run_verifiers(manifest!(name, type_names))
    message
  end

  describe "manifest verifier" do
    test "two declared types with the same alias" do
      message =
        collision_error!(SameAlias, %{T.Billing.Money => "Money", T.Shop.Money => "Money"})

      assert message =~ "Types with colliding TypeScript names found:"

      assert message =~
               "`Money` is the TypeScript alias of both #{inspect(T.Billing.Money)} and " <>
                 "#{inspect(T.Shop.Money)}: rename one of them #{@rename}."

      assert message =~ @fix
    end

    test "an alias equal to another's Input name" do
      message = collision_error!(InputName, %{T.Shade => "Shade", T.ShadeInput => "ShadeInput"})

      assert message =~
               "`ShadeInput` is the TypeScript alias of #{inspect(T.ShadeInput)} and the " <>
                 "input alias name of #{inspect(T.Shade)}: rename one of them #{@rename}."

      assert message =~ @fix
    end

    test "an alias equal to a resource-derived name" do
      message =
        collision_error!(ResourceName, %{
          T.CollisionHolderResourceSchema => "CollisionHolderResourceSchema"
        })

      assert message =~
               "`CollisionHolderResourceSchema` is the TypeScript alias of " <>
                 "#{inspect(T.CollisionHolderResourceSchema)} and a type generated for the " <>
                 "resource #{inspect(T.Holder)}: rename it #{@rename}."

      assert message =~ @fix
    end

    test "an alias equal to an embedded resource's derived name" do
      message = collision_error!(EmbeddedName, %{T.SwatchInputSchema => "SwatchInputSchema"})

      assert message =~
               "`SwatchInputSchema` is the TypeScript alias of #{inspect(T.SwatchInputSchema)} " <>
                 "and a type generated for the resource #{inspect(T.Swatch)}: rename it " <>
                 "#{@rename}."
    end

    test "an alias equal to a primitive alias" do
      message = collision_error!(PrimitiveName, %{T.Decimal => "Decimal"})

      assert message =~
               "`Decimal` is the TypeScript alias of #{inspect(T.Decimal)} and a type " <>
                 "ash_typescript generates: rename it #{@rename}."

      assert message =~ @fix
    end

    test "an alias equal to a utility type" do
      message = collision_error!(UtilityName, %{T.InferResult => "InferResult"})

      assert message =~
               "`InferResult` is the TypeScript alias of #{inspect(T.InferResult)} and a " <>
                 "type ash_typescript generates: rename it #{@rename}."
    end

    test "every collision is listed in one error" do
      message =
        collision_error!(AllCollisions, %{
          T.Billing.Money => "Money",
          T.Shop.Money => "Money",
          T.Decimal => "Decimal"
        })

      assert message =~ "`Money` is the TypeScript alias of both"
      assert message =~ "`Decimal` is the TypeScript alias of"
    end

    # Guards for the planted defect in the verifier (aliases taken from the
    # definition name instead of the decorated alias name).
    test "a ts_alias resolves the collision" do
      module =
        manifest!(RenamedAlias, %{T.Billing.Money => "Money", T.Shop.Money => "ShopMoney"})

      assert AshTypescript.Manifest.run_verifiers(module) == :ok
    end

    test "the joined module names of same-named modules don't collide" do
      module = manifest!(DefaultAliases, %{T.Billing.Money => :derive, T.Shop.Money => :derive})

      assert AshTypescript.Manifest.run_verifiers(module) == :ok

      aliases =
        module
        |> AshTypescript.manifest()
        |> then(&AshTypescript.with_manifest(&1, fn -> CustomTypeAliases.definitions() end))
        |> Enum.map(&CustomTypeAliases.plain_name/1)

      assert "AshTypescriptManifestCustomTypeNameCollisionsTestBillingMoney" in aliases
      assert "AshTypescriptManifestCustomTypeNameCollisionsTestShopMoney" in aliases
    end

    test "the test manifest has no collision" do
      assert AshTypescript.Manifest.run_verifiers(AshTypescript.Test.Manifest) == :ok
    end

    test "the reserved set covers the fixed generated names" do
      {:ok, files} = CodegenTestHelper.generate_files()

      custom_types = Custom.custom_types(nil)

      scalar_aliases =
        AshTypescript.manifest()
        |> TypeUses.nodes()
        |> Enum.map(&ScalarAliases.name(&1, custom_types))

      aliases =
        Enum.flat_map(CustomTypeAliases.definitions(), fn definition ->
          [CustomTypeAliases.plain_name(definition), CustomTypeAliases.input_name(definition)]
        end) ++ scalar_aliases

      resource_derived =
        ~r/(ResourceSchema|AttributesOnlySchema|InputSchema|FilterInput|FilterField|SortField)$/

      channel = ~r/(Payload|Channel|ChannelEvents|ChannelHandlers|ChannelRefs)$/

      fixed =
        ~r/^export type (\w+)/m
        |> Regex.scan(CodegenTestHelper.types_content(files))
        |> Enum.map(fn [_, name] -> name end)
        |> Enum.reject(&(&1 in aliases or &1 =~ resource_derived or &1 =~ channel))

      assert "Decimal" in fixed
      assert "InferResult" in fixed
      assert fixed -- VerifyCustomTypeNames.reserved_names() == []
    end

    test "the reserved set has the primitive aliases and the utility types" do
      reserved = VerifyCustomTypeNames.reserved_names()

      for name <- ~w(UUID UUIDv7 Decimal AshDate Time TimeUsec UtcDateTime UtcDateTimeUsec
                     DateTime NaiveDateTime Duration DurationName Binary AshVector
                     UrlEncodedBinary File Function ModuleName InferResult SortString
                     AshRpcError ValidationResult) do
        assert name in reserved, "#{name} is not reserved"
      end
    end
  end

  describe "scalar names" do
    defp verify(module), do: AshTypescript.Manifest.run_verifiers(module)

    test "two scalar modules with one name" do
      assert {:error, message} =
               verify(
                 scalar_holder_manifest!(ScalarSame, %{T.ScalarA => "Code", T.ScalarB => "Code"})
               )

      assert message =~ "Types with colliding TypeScript names found:"

      assert message =~
               "`Code` is the TypeScript alias of both #{inspect(T.ScalarA)} and " <>
                 "#{inspect(T.ScalarB)}: rename one of them #{@scalar_rename}."

      assert message =~ @fix
    end

    test "a scalar name equal to a map-like alias" do
      assert {:error, message} =
               verify(scalar_holder_manifest!(ScalarMoney, %{T.ScalarA => "Money"}))

      assert message =~
               "`Money` is the TypeScript alias of both AshMoney.Types.Money and " <>
                 "#{inspect(T.ScalarA)}: rename one of them: AshMoney.Types.Money #{@rename}, " <>
                 "or #{inspect(T.ScalarA)} #{@scalar_rename}."
    end

    test "a scalar name equal to a reserved name" do
      assert {:error, message} =
               verify(scalar_holder_manifest!(ScalarDecimal, %{T.ScalarA => "Decimal"}))

      assert message =~
               "`Decimal` is the TypeScript alias of #{inspect(T.ScalarA)} and a type " <>
                 "ash_typescript generates: rename it #{@scalar_rename}."
    end

    test "a scalar name equal to a map alias's Input name" do
      assert {:error, message} =
               verify(scalar_holder_manifest!(ScalarTintInput, %{T.ScalarA => "TintInput"}))

      assert message =~
               "`TintInput` is the TypeScript alias of #{inspect(T.ScalarA)} and the input " <>
                 "alias name of #{inspect(T.Tint)}: rename one of them: " <>
                 "#{inspect(T.ScalarA)} #{@scalar_rename}, or #{inspect(T.Tint)} #{@rename}."
    end

    test "callback names are checked" do
      assert {:error, message} =
               verify(scalar_manifest!(ScalarCallbacks, T.CallbackHolderDomain, nil))

      assert message =~
               "`SameName` is the TypeScript alias of both #{inspect(T.NamedA)} and " <>
                 "#{inspect(T.NamedB)}: rename one of them #{@scalar_rename}."
    end

    test "MFA names aren't checked at compile time" do
      assert verify(scalar_holder_manifest!(ScalarMfaOnly, %{})) == :ok
    end

    test "distinct scalar names don't collide" do
      assert verify(
               scalar_holder_manifest!(ScalarDistinct, %{T.ScalarA => "A", T.ScalarB => "B"})
             ) ==
               :ok
    end
  end

  describe "codegen backstop" do
    # The test manifest with Money's alias (or a schema name) replaced. Codegen
    # re-runs the verifiers against the configured manifest module, so these
    # reach the backstop.
    defp with_money_names(names) do
      manifest = AshTypescript.manifest()

      types =
        Enum.map(manifest.types, fn
          %Type{module: AshMoney.Types.Money} = money ->
            update_in(money.custom.ash_typescript.type_alias_names, &Map.merge(&1, names))

          type ->
            type
        end)

      AshRpc.Manifest.put_lookups(%{manifest | types: types})
    end

    defp generate_with_money_names(names) do
      CodegenTestHelper.generate_files(:ash_typescript, manifest: with_money_names(names))
    end

    # Codegen with the `*_schema_suffix` config `key` set to `suffix`: a named
    # schema is its alias plus the suffix.
    defp generate_with_suffix(key, suffix, names) do
      previous = Application.fetch_env(:ash_typescript, key)
      Application.put_env(:ash_typescript, key, suffix)

      try do
        generate_with_money_names(names)
      after
        case previous do
          {:ok, value} -> Application.put_env(:ash_typescript, key, value)
          :error -> Application.delete_env(:ash_typescript, key)
        end
      end
    end

    test "a duplicate export type in the types file" do
      assert {:error, message} =
               generate_with_money_names(%{typescript: "TrackerSummaryPayload"})

      assert message =~ "Duplicate exported type names in #{AshTypescript.types_output_file()}"
      assert message =~ "  - TrackerSummaryPayload"

      assert message =~
               "`TrackerSummaryPayload` is the TypeScript alias of the type " <>
                 "AshMoney.Types.Money: rename it #{@rename}."
    end

    test "an alias imported and declared locally in the RPC file" do
      assert {:error, message} = generate_with_money_names(%{typescript: "ListTodosInput"})

      rpc_file = Application.get_env(:ash_typescript, :output_file)

      assert message =~
               "#{rpc_file} imports types from #{AshTypescript.types_output_file()} " <>
                 "that it also declares:\n  - ListTodosInput"

      assert message =~
               "`ListTodosInput` is the TypeScript alias of the type " <>
                 "AshMoney.Types.Money: rename it #{@rename}."
    end

    test "an alias imported and declared locally in the routes file" do
      assert {:error, message} = generate_with_money_names(%{typescript: "TypedControllerConfig"})

      assert message =~
               "#{AshTypescript.routes_output_file()} imports types from " <>
                 "#{AshTypescript.types_output_file()} that it also declares:\n" <>
                 "  - TypedControllerConfig"
    end

    test "an alias imported and declared locally in the typed channels file" do
      assert {:error, message} = generate_with_money_names(%{typescript: "createOrgChannel"})

      assert message =~
               "#{AshTypescript.typed_channels_output_file()} imports types from " <>
                 "#{AshTypescript.types_output_file()} that it also declares:\n" <>
                 "  - createOrgChannel"
    end

    test "an alias equal to an import_name" do
      assert {:error, message} = generate_with_money_names(%{typescript: "CustomTypes"})

      assert message =~
               "The TypeScript alias `CustomTypes` of the type AshMoney.Types.Money " <>
                 "is an `import_name` in the `:import_into_generated` config"

      assert message =~ "config: rename it #{@rename}, or change the `import_name`."
    end

    test "an alias equal to a typed controller import_name" do
      assert {:error, message} = generate_with_money_names(%{typescript: "RouteHooks"})

      assert message =~
               "The TypeScript alias `RouteHooks` of the type AshMoney.Types.Money " <>
                 "is an `import_name` in the `:typed_controller_import_into_generated` config"
    end

    @doc false
    # A `ts_alias` MFA target: names every use `name`.
    def fixed_alias(_constraints, name), do: name

    # Codegen with the test manifest's ExternalCode scalar entry naming every
    # use `name` through an MFA, which the verifier leaves to codegen.
    defp generate_with_external_code_alias(name) do
      manifest =
        update_in(
          AshTypescript.manifest().custom.ash_typescript.custom_types.declared[
            AshTypescript.Test.ExternalCode
          ],
          &%{&1 | ts_alias: {__MODULE__, :fixed_alias, [name]}}
        )

      CodegenTestHelper.generate_files(:ash_typescript, manifest: manifest)
    end

    test "a scalar alias exported twice names its scalar entry" do
      assert {:error, message} = generate_with_external_code_alias("TrackerSummaryPayload")

      assert message =~ "Duplicate exported type names in #{AshTypescript.types_output_file()}"

      assert message =~
               "`TrackerSummaryPayload` is the TypeScript alias of the type " <>
                 "AshTypescript.Test.ExternalCode: rename it " <>
                 "#{AshTypescript.CustomTypes.rename_hint(:scalar)}."
    end

    test "a scalar alias equal to an import_name names its scalar entry" do
      assert {:error, message} = generate_with_external_code_alias("CustomTypes")

      assert message =~
               "The TypeScript alias `CustomTypes` of the type AshTypescript.Test.ExternalCode " <>
                 "is an `import_name` in the `:import_into_generated` config: rename it " <>
                 "#{AshTypescript.CustomTypes.rename_hint(:scalar)}, or change the `import_name`."
    end

    test "a schema name equal to a schema import_name" do
      assert {:error, message} =
               generate_with_suffix(:zod_schema_suffix, "Schemas", %{typescript: "NestedZod"})

      assert message =~
               "The Zod schema `NestedZodSchemas` of the type AshMoney.Types.Money " <>
                 "is an `import_name` in the `:zod_import_into_generated` config: rename its " <>
                 "alias #{@rename}, or change the `import_name`."
    end

    test "an alias equal to a name the RPC file imports itself" do
      # The test config enables channel RPC actions, so the RPC file imports
      # `Channel` from phoenix.
      assert {:error, message} = generate_with_money_names(%{typescript: "Channel"})

      rpc_file = Application.get_env(:ash_typescript, :output_file)

      assert message =~
               "#{rpc_file} imports names that it also imports from " <>
                 "#{AshTypescript.types_output_file()} or declares:\n" <>
                 ~s(  - Channel \(imported from "phoenix"\))

      assert message =~
               "`Channel` is the TypeScript alias of the type " <>
                 "AshMoney.Types.Money: rename it #{@rename}."

      assert message =~ "A file can bind each name once: rename what generates the clashing name."
    end

    test "a zod schema named like the zod import" do
      assert {:error, message} = generate_with_suffix(:zod_schema_suffix, "", %{typescript: "z"})

      assert message =~
               "#{AshTypescript.zod_output_file()} imports names that it also imports from " <>
                 "#{AshTypescript.types_output_file()} or declares:\n" <>
                 ~s(  - z \(imported from "zod"\))

      assert message =~
               "`z` is the Zod schema of the type AshMoney.Types.Money, named after " <>
                 "its alias: rename the alias #{@rename}."
    end

    test "a valibot schema named like the valibot import" do
      assert {:error, message} =
               generate_with_suffix(:valibot_schema_suffix, "", %{typescript: "v"})

      assert message =~
               "#{AshTypescript.valibot_output_file()} imports names that it also imports from " <>
                 "#{AshTypescript.types_output_file()} or declares:\n" <>
                 ~s(  - v \(imported from "valibot"\))

      assert message =~
               "`v` is the Valibot schema of the type AshMoney.Types.Money, named " <>
                 "after its alias: rename the alias #{@rename}."
    end

    test "the test app generates without backstop errors" do
      assert {:ok, _files} = CodegenTestHelper.generate_files()
    end
  end
end
