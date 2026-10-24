# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.NestedTypeAliasesTest do
  @moduledoc """
  Regression coverage for #106: a type that only appears nested inside another
  type — a typed map/keyword/tuple field, a union member, a calculation
  argument's fields, a generic action's typed-map return, or a NewType used as
  a field — is rendered by the type mapper as its alias (e.g. `UtcDateTime`),
  so the alias must also be declared in `ash_types.ts`.

  Each alias below is used *only* in one nested position in this scoped
  domain, so a missing declaration can't be masked by a plain attribute of the
  same type elsewhere. The domain is declared inline to keep the shared
  `test/ts` fixtures untouched.
  """

  # Mutates the global :manifest config, so must not run async.
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  defmodule StampBinary do
    use Ash.Type.NewType, subtype_of: :binary
  end

  defmodule Invoice do
    use Ash.Resource,
      domain: AshTypescript.Codegen.NestedTypeAliasesTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "Invoice"
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id

      attribute :payment, :map,
        public?: true,
        constraints: [
          fields: [
            method: [type: :string],
            paid_at: [type: :utc_datetime],
            stamp: [type: AshTypescript.Codegen.NestedTypeAliasesTest.StampBinary],
            raw_payload: [type: :term]
          ]
        ]

      attribute :settlement, :union,
        public?: true,
        constraints: [
          types: [
            at_time: [type: :time],
            detail: [type: :map, constraints: [fields: [on: [type: :date]]]],
            opaque: [type: :term]
          ]
        ]

      attribute :span, :tuple,
        public?: true,
        constraints: [fields: [amount: [type: :decimal], label: [type: :string]]]

      attribute :blob, :term, public?: true

      attribute :opts, :keyword,
        public?: true,
        constraints: [fields: [timeout: [type: :duration]]]
    end

    calculations do
      calculate :window_label, :string, expr("window") do
        public? true

        argument :window, :map,
          allow_nil?: true,
          constraints: [fields: [since: [type: :utc_datetime_usec]]]
      end
    end

    actions do
      defaults [:read]

      read :list_stamped do
        metadata :stamped_at, :time_usec
      end

      action :recent_invoices, {:array, :map} do
        public? true

        constraints items: [
                      fields: [number: [type: :string], created: [type: :naive_datetime]]
                    ]

        run fn _, _ -> {:ok, []} end
      end
    end
  end

  defmodule Domain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Codegen.NestedTypeAliasesTest.Invoice do
        rpc_action :list_invoices, :read
        rpc_action :list_stamped_invoices, :list_stamped
        rpc_action :recent_invoices, :recent_invoices
      end
    end

    resources do
      resource AshTypescript.Codegen.NestedTypeAliasesTest.Invoice
    end
  end

  defmodule Manifest do
    use AshTypescript.Manifest,
      otp_app: :ash_typescript,
      domains: [AshTypescript.Codegen.NestedTypeAliasesTest.Domain]
  end

  @otp_app :nested_type_aliases_test_app

  setup_all do
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

    types =
      files
      |> Enum.filter(fn {path, _} -> String.ends_with?(path, "ash_types.ts") end)
      |> Enum.map_join("\n", fn {_, content} -> content end)

    all = Enum.map_join(files, "\n", fn {_, content} -> content end)

    refute types == "", "no types file was generated"

    %{types: types, all: all}
  end

  for {alias_name, ts, position} <- [
        {"UtcDateTime", "string", "typed map attribute field"},
        {"Binary", "string", "NewType used as a typed map field"},
        {"Time", "string", "union member"},
        {"AshDate", "string", "typed map field inside a union member"},
        {"Decimal", "string", "tuple element"},
        {"Duration", "string", "typed keyword field"},
        {"UtcDateTimeUsec", "string", "calculation argument's typed map field"},
        {"NaiveDateTime", "string", "generic action's {:array, :map} return item field"},
        {"TimeUsec", "string", "read action metadata field"}
      ] do
    test "declares #{alias_name} when used only as a #{position}", %{types: types, all: all} do
      alias_name = unquote(alias_name)

      # Guards the fixture: the alias must actually be referenced somewhere.
      assert Regex.match?(~r/:\s*#{alias_name}\b/, all),
             "expected generated code to reference #{alias_name}"

      assert types =~ "export type #{alias_name} = #{unquote(ts)};"
    end
  end

  test ":term as an attribute, typed map field and union member renders as any", %{types: types} do
    assert types =~ ~r/blob\??: any\b/
    assert types =~ ~r/rawPayload\??: any\b/
    assert types =~ ~r/opaque\??: any\b/
  end
end
