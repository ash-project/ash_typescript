# Instructions

Ok, I would like to be able to add a filter field to the rpc_spec, which can be used to filter query results.
The types of filter fields that can be used are:

- `eq`: Equal to a specific value
- `notEq`: Not equal to a specific value
- `greaterThan`: Greater than a specific value
- `greaterThanOrEqual`: Greater than or equal to a specific value
- `lessThan`: Less than a specific value
- `lessThanOrEqual`: Less than or equal to a specific value
- `in`: In a list of values
- `notIn`: Not in a list of values

Then you can also combine multiple filter fields using the `and`, `not`, or `or` operators.

Example of a filter type and how to use it:

```typescript
export type ServicePerformerAssignmentFilterInput = {
  and?: InputMaybe<Array<ServicePerformerAssignmentFilterInput>>;
  id?: InputMaybe<ServicePerformerAssignmentFilterId>;
  not?: InputMaybe<Array<ServicePerformerAssignmentFilterInput>>;
  or?: InputMaybe<Array<ServicePerformerAssignmentFilterInput>>;
  reportState?: InputMaybe<ServicePerformerAssignmentFilterReportState>;
  servicePerformer?: InputMaybe<ServicePerformerFilterInput>;
  servicePerformerId?: InputMaybe<ServicePerformerAssignmentFilterServicePerformerId>;
  visitingServiceOrder?: InputMaybe<VisitingServiceOrderFilterInput>;
};

const filter: ServicePerformerAssignmentFilterInput = {
    servicePerformerId: { eq: params.servicePerformerId },
    visitingServiceOrder: {
      scheduledDate: { greaterThanOrEqual: new Date().toISOString().split('T')[0] },
      registrationError: { eq: false }
    },
    reportState: { notEq: ServicePerformerAssignmentReportState.Submitted }
  };
```

For each resource, a distinct filter type should be generated, and for related resources you can do nested filtering
on values in those resources as well, and the same again for the next level of relationships, and so on.

Can you help me write the Elixir code that is needed to build the typescript types for any Ash resource, and
the code that is needed to translate the incoming JSON data in the rpc action payloads so that it can be used to
filter the data when the data is being fetched?
