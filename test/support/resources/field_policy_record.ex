# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.FieldPolicyRecord do
  @moduledoc """
  Test resource that exercises field policies on generic actions.

  Used to verify that generic actions returning a resource have their
  return values run through an authorized load so field policies scrub
  fields the actor isn't allowed to see.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource, Ash.Policy],
    authorizers: [Ash.Policy.Authorizer]

  typescript do
    type_name "FieldPolicyRecord"
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :public_note, :string, public?: true
    attribute :admin_note, :string, public?: true
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :admin_note do
      authorize_if AshTypescript.Test.FieldPolicyRecord.AdminCheck
    end

    field_policy :* do
      authorize_if always()
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:title, :public_note, :admin_note]
    end

    action :latest, :struct do
      constraints instance_of: __MODULE__

      run fn _input, _ctx ->
        case AshTypescript.Test.FieldPolicyRecord
             |> Ash.Query.sort(title: :asc)
             |> Ash.Query.limit(1)
             |> Ash.read(authorize?: false) do
          {:ok, [record]} -> {:ok, record}
          {:ok, []} -> {:error, "no record"}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  defmodule AdminCheck do
    @moduledoc false
    use Ash.Policy.SimpleCheck

    @impl true
    def describe(_), do: "actor is admin"

    @impl true
    def match?(%{admin: true}, _ctx, _opts), do: true
    def match?(_, _, _), do: false
  end
end
