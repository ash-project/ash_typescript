# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Subscription do
  @moduledoc """
  Test resource for verifying identity field name mapping.

  This resource has fields with invalid TypeScript characters (like `?`)
  that are mapped using `field_names`, and an identity that uses those
  mapped fields. This tests that identity input/output correctly applies
  field name formatting and reverse mapping.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Subscription"
    # Map fields with invalid TypeScript characters
    field_names is_active?: "isActive", is_trial?: "isTrial"
  end

  ets do
    private? true
  end

  identities do
    # Identity using fields that have field_names mappings
    identity :by_user_and_status, [:user_id, :is_active?],
      pre_check_with: AshTypescript.Test.Domain
  end

  attributes do
    integer_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :plan, :string do
      allow_nil? false
      public? true
    end

    attribute :is_active?, :boolean do
      default true
      public? true
    end

    attribute :is_trial?, :boolean do
      default false
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    read :get_by_id do
      get_by :id
    end

    create :create do
      accept [:user_id, :plan, :is_active?, :is_trial?]

      change fn changeset, _context ->
        if Ash.Changeset.get_attribute(changeset, :id) do
          changeset
        else
          Ash.Changeset.force_change_attribute(changeset, :id, System.unique_integer([:positive]))
        end
      end
    end

    update :update do
      accept [:plan, :is_active?, :is_trial?]
    end
  end
end
