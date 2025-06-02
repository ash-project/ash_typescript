defmodule AshTypescriptExample do
  @moduledoc """
  Example demonstrating how to use fields constraints with Ash TypeScript codegen
  for generic actions that return structured data.
  """

  defmodule ExampleDomain do
    use Ash.Domain

    resources do
      resource ExampleResource
    end
  end

  defmodule ExampleResource do
    use Ash.Resource,
      domain: ExampleDomain,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
      attribute :name, :string
    end

    actions do
      defaults [:create, :read, :update, :destroy]

      # Example 1: Simple map return type with fields constraints
      action :calculate_summary, :map do
        description "Calculate a summary with typed fields"
        
        argument :include_details, :boolean, default: false

        # This defines the structure of the returned map
        constraints [
          fields: [
            total_amount: [
              type: :integer,
              description: "The total amount in cents",
              allow_nil?: false
            ],
            currency: [
              type: :string,
              description: "ISO 4217 currency code",
              allow_nil?: false,
              constraints: [
                max_length: 3
              ]
            ],
            tax_amount: [
              type: :integer,
              description: "Tax amount in cents",
              allow_nil?: true
            ],
            processed_at: [
              type: Ash.Type.UtcDatetime,
              allow_nil?: false
            ]
          ]
        ]

        run fn _input, _context ->
          # In a real implementation, you would calculate these values
          {:ok, %{
            total_amount: 15000,
            currency: "USD",
            tax_amount: 1500,
            processed_at: DateTime.utc_now()
          }}
        end
      end

      # Example 2: Array of structured maps
      action :list_transactions, {:array, :map} do
        description "List transactions with typed structure"
        
        argument :status, :atom, constraints: [one_of: [:pending, :completed, :failed]]
        argument :limit, :integer, default: 10

        constraints [
          fields: [
            id: [
              type: Ash.Type.UUID,
              allow_nil?: false
            ],
            amount: [
              type: :integer,
              allow_nil?: false
            ],
            status: [
              type: Ash.Type.Atom,
              allow_nil?: false
            ],
            customer_name: [
              type: :string,
              allow_nil?: true
            ],
            metadata: [
              type: Ash.Type.Map,
              allow_nil?: true
            ]
          ]
        ]

        run fn input, _context ->
          # Example implementation
          transactions = 
            1..input.arguments.limit
            |> Enum.map(fn i ->
              %{
                id: Ash.UUID.generate(),
                amount: i * 1000,
                status: input.arguments.status || :completed,
                customer_name: "Customer #{i}",
                metadata: %{
                  source: "api",
                  version: "1.0"
                }
              }
            end)
          
          {:ok, transactions}
        end
      end

      # Example 3: Struct return type with complex nested fields
      action :get_payment_details, Ash.Type.Struct do
        description "Get detailed payment information"
        
        argument :payment_id, :uuid do
          allow_nil? false
        end

        constraints [
          fields: [
            payment_id: [
              type: Ash.Type.UUID,
              allow_nil?: false
            ],
            amount: [
              type: AshMoney.Types.Money,
              allow_nil?: false,
              description: "Payment amount with currency"
            ],
            status: [
              type: Ash.Type.Atom,
              allow_nil?: false
            ],
            payment_method: [
              type: :string,
              allow_nil?: false
            ],
            card_info: [
              type: :map,
              allow_nil?: true,
              constraints: [
                fields: [
                  last_four: [
                    type: :string,
                    allow_nil?: false
                  ],
                  brand: [
                    type: :string,
                    allow_nil?: false
                  ]
                ]
              ]
            ],
            billing_address: [
              type: :map,
              allow_nil?: true,
              constraints: [
                fields: [
                  street: [type: :string],
                  city: [type: :string],
                  postal_code: [type: :string],
                  country: [type: :string]
                ]
              ]
            ]
          ]
        ]

        run fn input, _context ->
          # Example implementation
          {:ok, %{
            payment_id: input.arguments.payment_id,
            amount: Money.new(10000, :USD),
            status: :completed,
            payment_method: "credit_card",
            card_info: %{
              last_four: "4242",
              brand: "visa"
            },
            billing_address: %{
              street: "123 Main St",
              city: "San Francisco",
              postal_code: "94105",
              country: "US"
            }
          }}
        end
      end

      # Example 4: Array of structs
      action :get_order_items, {:array, Ash.Type.Struct} do
        description "Get order items with detailed structure"
        
        argument :order_id, :uuid, allow_nil?: false

        constraints [
          fields: [
            product_id: [
              type: Ash.Type.UUID,
              allow_nil?: false
            ],
            product_name: [
              type: :string,
              allow_nil?: false
            ],
            quantity: [
              type: :integer,
              allow_nil?: false,
              constraints: [
                min: 1
              ]
            ],
            unit_price: [
              type: :decimal,
              allow_nil?: false
            ],
            discount_percentage: [
              type: :float,
              allow_nil?: true,
              constraints: [
                min: 0,
                max: 100
              ]
            ],
            subtotal: [
              type: :decimal,
              allow_nil?: false
            ]
          ]
        ]

        run fn _input, _context ->
          items = [
            %{
              product_id: Ash.UUID.generate(),
              product_name: "Widget A",
              quantity: 2,
              unit_price: Decimal.new("19.99"),
              discount_percentage: 10.0,
              subtotal: Decimal.new("35.98")
            },
            %{
              product_id: Ash.UUID.generate(),
              product_name: "Widget B",
              quantity: 1,
              unit_price: Decimal.new("29.99"),
              discount_percentage: nil,
              subtotal: Decimal.new("29.99")
            }
          ]
          
          {:ok, items}
        end
      end
    end
  end
end

# When you run the TypeScript codegen, these actions will generate types like:
#
# export type CalculateSummaryReturn = {
#   totalAmount: number;
#   currency: string;
#   taxAmount?: number;
#   processedAt: string;
# }
#
# export type ListTransactionsReturn = {
#   id: string;
#   amount: number;
#   status: string;
#   customerName?: string;
#   metadata?: Record<string, any>;
# }[]
#
# export type GetPaymentDetailsReturn = {
#   paymentId: string;
#   amount: {amount: number, currency: string};
#   status: string;
#   paymentMethod: string;
#   cardInfo?: {
#     lastFour: string;
#     brand: string;
#   };
#   billingAddress?: {
#     street?: string;
#     city?: string;
#     postalCode?: string;
#     country?: string;
#   };
# }
#
# export type GetOrderItemsReturn = {
#   productId: string;
#   productName: string;
#   quantity: number;
#   unitPrice: number;
#   discountPercentage?: number;
#   subtotal: number;
# }[]