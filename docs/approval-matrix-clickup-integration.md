# ClickUp Lighting Approval Matrix Integration

The ClickUp integration uses Salesforce-initiated API polling. There is no ClickUp webhook or public Salesforce Site endpoint. The workflow stays on the separate **Approval Matrix ClickUp** page and does not replace the original TXT Workbench.

- Page/tab: `/lightning/n/Approval_Matrix_ClickUp`
- Separate deployment manifest: `manifest/approval-matrix-clickup-deploy.xml`
- ClickUp List ID from the supplied List URL: `1301030000009930`
- Suggested handoff status, based on the statuses visible in the List: `awaiting approval`
- Target: existing `ApprovalMatrix__c` records, keyed by Lighting and Item code
- Verifier approval is required before writing target records

## Important credential response

ClickUp's authorization code is a one-time input to the token exchange; do not retain it. ClickUp currently documents that OAuth access tokens do not expire, though this can change. Exchange a newly issued code in a private local/API client, then store only the resulting access token in Salesforce's protected Named Credential configuration. The client secret is needed only for the exchange and is not needed by the poller.

## Configure Salesforce

1. In Setup, create a Named Credential named `ClickUp_API` with URL `https://api.clickup.com/api`. Use a protected credential/custom-header configuration for the `Authorization` header and enter the newly issued OAuth access token as its value. Set the header to the raw token value without an additional authentication scheme prefix.
2. In Setup, manage **Approval Matrix ClickUp Settings** and set the org-default values:
   - `ClickUp_List_Id__c`: `1301030000009930`
   - `Handoff_Status__c`: `awaiting approval` (must match the ClickUp status exactly; compare is case-insensitive)
3. Assign **Approval Matrix Verifier** to users permitted to trigger a manual sync and review requests. Assign **Approval Matrix Admin** to administrators.

No Salesforce Site, guest access, webhook secret, or ClickUp webhook registration is required.

## Configure OAuth token

Use the ClickUp OAuth app authorization URL with the app's client ID and its registered redirect URI to authorize the ClickUp Workspace and obtain a fresh one-time code. Exchange that code using ClickUp's documented `POST https://api.clickup.com/api/v2/oauth/token` endpoint, with `client_id`, `client_secret`, and `code` in the request body. Perform the exchange locally using a private password manager/API client; do not paste the values into chat or source files. Store the returned `access_token` only in the `ClickUp_API` Named Credential.

Official references:

- [ClickUp authentication and OAuth flow](https://developer.clickup.com/docs/authentication)
- [ClickUp Get Access Token endpoint](https://developer.clickup.com/reference/getaccesstoken)
- [ClickUp Get Tasks endpoint](https://developer.clickup.com/reference/gettasks)
- [Salesforce Named Credentials](https://developer.salesforce.com/docs/platform/named-credentials/guide/nc-create-oauth-cred.html)

## Polling and data flow

1. **Sync ClickUp now** in the ClickUp workbench enqueues one Salesforce poll. The poller requests tasks from the configured List, filtered to the handoff status, newest-updated first, and with Markdown descriptions included.
2. Salesforce reads task IDs, status, description, URL, and `date_updated` from the ClickUp API response. It stages at most 10 new/changed tasks per poll and advances through ClickUp's 100-task pages.
3. `ApprovalMatrixClickUpIntakeService` parses one `Item | GM | AGM | RM` table per task. GM/AGM/RM are preserved exactly as provided. The existing validator checks active Product2 matches and data values.
4. The workbench shows staged tasks, parsed values, product matches, current matrix values, and errors. Only verifier approval writes the existing `ApprovalMatrix__c`.
5. Repeated polls do not duplicate requests or lines. An edited task refreshes staging until it is approved/rejected or a matrix write has begun. Approved, inserted, and rejected requests are terminal and are not silently reapplied.
6. API/configuration errors are shown in the workbench's last-poll status. A failed task parse remains visible as a staging error.

The Salesforce Scheduled Apex job can poll hourly; users can also run a poll manually at any time. To enable the hourly schedule once, run this from **Setup → Developer Console → Debug → Open Execute Anonymous** (or `sf apex run` with an anonymous Apex file):

```apex
System.schedule(
    'Approval Matrix ClickUp hourly poll',
    '0 0 * * * ?',
    new ApprovalMatrixClickUpPollScheduler()
);
```

Confirm the scheduled job is present in **Setup → Scheduled Jobs**. Avoid creating duplicate schedules with the same name.

## Deployment

From the `automation/` directory, validate and deploy the separate ClickUp bundle. The post-destructive manifest removes the obsolete webhook classes and webhook/event-key fields:

```bash
sf project deploy validate \
  --target-org <sandbox-alias> \
  --manifest manifest/approval-matrix-clickup-deploy.xml \
  --post-destructive-changes manifest/destructiveChangesPost.xml \
  --test-level RunSpecifiedTests \
  --tests ApprovalMatrixClickUpIntakeTest \
  --tests ApprovalMatrixTxtServiceTest

sf project deploy start \
  --target-org <sandbox-alias> \
  --manifest manifest/approval-matrix-clickup-deploy.xml \
  --post-destructive-changes manifest/destructiveChangesPost.xml \
  --test-level RunSpecifiedTests \
  --tests ApprovalMatrixClickUpIntakeTest \
  --tests ApprovalMatrixTxtServiceTest
```

The poller uses the `ClickUp_API` Named Credential and never stores OAuth tokens or client secrets in source code.
