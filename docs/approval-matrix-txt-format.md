# Approval Matrix TXT handoff format

The ClickUp integration is not part of this Salesforce build. When connected, it should create one `Approval_Matrix_Request__c` record with a unique `ClickUp_Task_Id__c`, then attach the `.txt` file to that record as a Salesforce File. The ContentDocumentLink trigger detects the file and queues parsing.

The request's `ClickUp_Task_Id__c` must exactly match `TASK_ID` in the file. Salesforce ignores a repeated link to the already-processed file and blocks replacement after verification or insertion has begun. When uploading through the API, use `ContentVersion.FirstPublishLocationId` with the request record Id (or create a `ContentDocumentLink` after upload).

## Common rules

- UTF-8 text, one header per line, followed by one `---` separator.
- Header names are case-insensitive; values are trimmed.
- Blank lines are ignored.
- Keep each data row on one line and use `|` between columns.
- Use plain decimal numbers (no thousands separators, currency symbols, or percent signs).
- Unknown/duplicate headers, missing required values, malformed rows, and unsupported extensions are reported on the request or line; rows are not silently discarded.
- `RECORD_TYPE` must be `POWER` or `LIGHTING`.

## Lighting

`PRODUCT_CATEGORY` is optional and defaults to `Others`.

```text
TASK_ID: abc123
RECORD_TYPE: LIGHTING
PRODUCT_CATEGORY: Others
---
PCNM05408|4000|4080|4160
PCNM05409|3900|3950|4020
```

Rows are `ProductCode|Value1|Value2|Value3`. Values must be positive. Salesforce sorts them: highest maps to No Approval, middle to RSM, lowest to NSM. Ties are warnings for the verifier. Exactly one active Product2 must match each product code.

## Power

`PRODUCT_CATEGORY` is required.

```text
TASK_ID: def456
RECORD_TYPE: POWER
PRODUCT_CATEGORY: Cables Wires and Tapes
---
WIRES CABLES AND TAPES|WIRES|MULTICORE CABLE|0|9|10|11|2|3|4|5
```

Rows are `Division|Category|Brand|Sales Discount|Discount %|Discount Max|Above Policy %|Approval Level|Approval Max|Approval > Max|Above Policy Level`. All eight numeric values are required. The percentage must not exceed the maximum. Salesforce matches active Product2 records by exact Division, Category, and Brand fields; each match must have Product Category populated.

## Salesforce setup notes

- Deploy `manifest/approval-matrix-deploy.xml`. It deploys the staging/target objects, fields, trigger, Apex services, workbench app page/tab, verifier LWC, and permission sets.
- Open the **Approval Matrix Workbench** tab. Create a staging request using a unique task ID, select it, then upload the `.txt` file. Parsed data and validation feedback appear below before any matrix insert.
- Populate Product2 fields `Division__c`, `Category__c`, `Brand__c`, and `Product_Category__c` before relying on Power matching.
- `Approval Matrix Verification` is embedded in the workbench and can also be added to an Approval Matrix Request record page.
- Assign `Approval Matrix Verifier` only to approvers. The Apex approval endpoint additionally checks the `Approve Approval Matrix Request` custom permission; the admin and integration permission sets do not include it.
- Assign `Approval Matrix Integration` to the future integration user; it can create requests but cannot approve/reject or write matrix records.
- `Product_Approval_Hierarchy__c` was absent from the connected org at implementation time, so this source package defines it with the requested fields plus a unique source-line key to make retries safe.
- `Line_Count__c` is a Salesforce roll-up summary. `Error_Count__c` is maintained by the parser/validator because Salesforce check-only validation rejects a filtered roll-up that references a child field created in the same deployment. The processing service updates the count whenever it revalidates or inserts lines.
- Deploy and verify this package in a sandbox before production. Existing `ApprovalMatrix__c` records are not modified by this workflow.

## Sandbox validation

After deploying the package and assigning `Approval Matrix Admin` to the test user, run:

```bash
sf apex run test --target-org <sandbox-alias> --tests ApprovalMatrixTxtServiceTest --result-format human --wait 30
```

The focused test covers TXT intake, Lighting mapping, tie warnings, malformed-row errors, Power field parsing, request listing/review data, approved matrix insertion, and duplicate-insertion prevention.
