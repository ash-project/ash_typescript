# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ManifestGeneratorDomainGroupedTest do
  # Without namespaces the Markdown manifest groups RPC functions by domain
  # (the test app's manifest has namespaces, so `manifest_generator_test.exs`
  # covers the namespace grouping).
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.Codegen.ManifestGenerator

  for name <- [Widget, Gadget] do
    defmodule Module.concat(__MODULE__, name) do
      @moduledoc false
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "DomainGrouped#{inspect(name)}"
      end

      attributes do
        uuid_primary_key :id
        attribute :name, :string, public?: true
      end

      actions do
        defaults [:read, create: [:name]]
      end
    end
  end

  defmodule BetaDomain do
    @moduledoc false
    use Ash.Domain,
      otp_app: :ash_typescript,
      extensions: [AshTypescript.Rpc],
      validate_config_inclusion?: false

    typescript_rpc do
      resource AshTypescript.Rpc.ManifestGeneratorDomainGroupedTest.Widget do
        rpc_action :list_widgets, :read
      end
    end

    resources do
      resource AshTypescript.Rpc.ManifestGeneratorDomainGroupedTest.Widget
    end
  end

  defmodule AlphaDomain do
    @moduledoc false
    use Ash.Domain,
      otp_app: :ash_typescript,
      extensions: [AshTypescript.Rpc],
      validate_config_inclusion?: false

    typescript_rpc do
      resource AshTypescript.Rpc.ManifestGeneratorDomainGroupedTest.Widget do
        rpc_action :make_widget, :create, description: "Makes a widget"
        rpc_action :all_widgets, :read, deprecated: "Use listWidgets"

        typed_query :widget_names, :read do
          description "Widget names"
          fields [:id, :name]
        end
      end

      resource AshTypescript.Rpc.ManifestGeneratorDomainGroupedTest.Gadget do
        rpc_action :list_gadgets, :read
      end
    end

    resources do
      resource AshTypescript.Rpc.ManifestGeneratorDomainGroupedTest.Widget
      resource AshTypescript.Rpc.ManifestGeneratorDomainGroupedTest.Gadget
    end
  end

  setup_all do
    manifest =
      AshTypescript.Test.InlineManifest.build!(domains: [BetaDomain, AlphaDomain], body: nil)

    %{content: AshTypescript.with_manifest(manifest, &ManifestGenerator.generate_manifest/0)}
  end

  defp index!(content, text) do
    case :binary.match(content, text) do
      {index, _} -> index
      :nomatch -> flunk("#{inspect(text)} not found in:\n#{content}")
    end
  end

  test "a section per domain, sorted by domain", %{content: content} do
    refute content =~ "## Namespace:"
    refute content =~ "## Default (No Namespace)"

    alpha = index!(content, "## #{inspect(AlphaDomain)}\n")
    beta = index!(content, "## #{inspect(BetaDomain)}\n")
    assert alpha < beta
  end

  test "resources sorted by name and their functions by rpc name", %{content: content} do
    [alpha, beta] = String.split(content, "## #{inspect(BetaDomain)}\n")

    assert index!(alpha, "### Gadget\n") < index!(alpha, "### Widget\n")

    widget = alpha |> String.split("### Widget\n") |> List.last()
    assert index!(widget, "| `allWidgets` | read |") < index!(widget, "| `makeWidget` | create |")

    assert beta =~ "### Widget\n"
    assert beta =~ "| `listWidgets` | read |"
  end

  test "a blank line between a resource's details and the next resource", %{content: content} do
    assert content =~ "- **`listGadgets`**: Read Gadget records\n\n### Widget\n"
  end

  test "details, deprecations and typed queries", %{content: content} do
    assert content =~ "- **`makeWidget`**: Makes a widget\n"

    assert content =~
             "- **`allWidgets`**: Read Widget records | ⚠️ **Deprecated:** Use listWidgets\n"

    assert content =~ "**Typed Queries:**\n- `widgetNames` → `WidgetNamesResult`: Widget names\n"
  end
end
