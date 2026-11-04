# ClickUp Lighting Approval Matrix Integration

The ClickUp integration uses Salesforce-initiated API polling. There is no ClickUp webhook or public Salesforce Site endpoint. The workflow stays on the separate **Approval Matrix ClickUp** page and does not replace the original TXT Workbench.

- Page/tab: `/lightning/n/Approval_Matrix_ClickUp`
- Separate deployment manifest: `manifest/approval-matrix-clickup-deploy.xml`
- ClickUp List ID from the supplied List URL: `1301030000009930`
- Suggested handoff status, based on the statuses visible in the List: `awaiting approval`
- Target: existing `ApprovalMatrix__c` records, keyed by Lighting and Item code
- Verifier approval is required before writing target records

## Important credential response

The client ID and client secret are used by `ClickUpAuthProvider` for the one-time authorization-code exchange. Salesforce then keeps the returned access token in the External Credential principal. Apex task-polling code never reads or stores that token. ClickUp currently documents that OAuth access tokens do not expire, though this can change. The authorization code is single-use and is not stored.

The OAuth client secret must be regenerated because an earlier value was exposed. Custom Metadata is org configuration, not an encrypted credential vault: only admins should have access to its `Client_Secret__c`, and the default record file is excluded from Git. Never commit real values.

## Configure Salesforce

The Salesforce metadata definitions have been deployed:

- Auth Provider: `ClickUp_Auth`
- External Credential and named principal: `ClickUp_Ext` / `ClickUp_Principal`
- Named Credential: `ClickUp_API`, base URL `https://api.clickup.com/api`
- Custom Metadata type/record: `ClickUp_Auth__mdt` / `ClickUp_Auth.Default`
- Integration permission set: `ClickUp_Integration` (already assigned to the connected admin user)

The ClickUp OAuth custom metadata record is deployed with empty values by design. Finish the one-time OAuth setup:

1. In Salesforce Setup → **Auth. Providers** → **ClickUp**, copy the Callback URL.
2. In ClickUp Settings → Apps → your OAuth app, register that exact callback URL as its redirect URL.
3. In Salesforce Setup → Custom Metadata Types → **ClickUp Auth** → Manage Records → **Default**, set `Client_Id__c`, the regenerated `Client_Secret__c`, and `Callback_Url__c` to the copied Salesforce Callback URL. The source record is intentionally blank and Git-ignored; configure these values in the org only.
4. In Salesforce Setup → Named Credentials → **External Credentials** → **ClickUp Ext** → Principals → **ClickUp_Principal**, select **Authenticate** and authorize the ClickUp Workspace. The principal must show Configured. Salesforce stores the OAuth access token encrypted; do not paste it into a Custom Metadata record or the Named Credential.
5. In Salesforce, open the **Approval Matrix ClickUp** page and click **Sync ClickUp now**. Check Last Poll for success. The caller needs the `ClickUp_Integration` permission set; it is assigned to the connected admin user already.

No separate personal token or manual `curl` token exchange is required. The Salesforce Auth Provider executes the OAuth code exchange during Authenticate. No Salesforce Site, guest access, webhook secret, or ClickUp webhook registration is required.

The current live poll error is: “The external credential isn't fully configured.” The Named Credential now exists and resolves, but its OAuth principal has not been authenticated/configured yet. The above callback, Custom Metadata, and principal-authentication steps resolve that state. The old generic callout message was updated to include a bounded Salesforce diagnostic; the latest poll status will show it after another attempt.

In Setup, manage **Approval Matrix ClickUp Settings** and set the org-default values:
   - `ClickUp_List_Id__c`: `1301030000009930`
   - `Handoff_Status__c`: `awaiting approval` (must match the ClickUp status exactly; compare is case-insensitive)
Assign **Approval Matrix Verifier** to users permitted to review and approve requests, and **Approval Matrix Admin** to administrators.

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
6. API/configuration errors are shown in the workbench's last-poll status, including a bounded Salesforce callout exception detail. A failed task parse remains visible as a staging error.

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
  --tests ApprovalMatrixTxtServiceTest \
  --tests ApprovalMatrixClickUpApiTest \
  --tests ClickUpAuthProviderTest

sf project deploy start \
  --target-org <sandbox-alias> \
  --manifest manifest/approval-matrix-clickup-deploy.xml \
  --post-destructive-changes manifest/destructiveChangesPost.xml \
  --test-level RunSpecifiedTests \
  --tests ApprovalMatrixClickUpIntakeTest \
  --tests ApprovalMatrixTxtServiceTest \
  --tests ApprovalMatrixClickUpApiTest \
  --tests ClickUpAuthProviderTest
```

The poller uses the `ClickUp_API` Named Credential. OAuth client credentials must remain outside source control; only the External Credential stores the authenticated access token.
