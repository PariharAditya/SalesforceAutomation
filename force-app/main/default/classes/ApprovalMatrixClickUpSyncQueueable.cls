public without sharing class ApprovalMatrixClickUpSyncQueueable
    implements Queueable, Database.AllowsCallouts {
    private static final Integer MAX_TASKS_PER_RUN = 10;

    public void execute(QueueableContext context) {
        Approval_Matrix_ClickUp_Settings__c settings =
            Approval_Matrix_ClickUp_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.ClickUp_List_Id__c) ||
            String.isBlank(settings.Handoff_Status__c)) {
            savePollResult(settings, 'Configure the ClickUp List ID and handoff status.');
            return;
        }

        Integer page = settings.Next_Page__c == null
            ? 0 : Integer.valueOf(String.valueOf(settings.Next_Page__c));
        List<Map<String, Object>> tasks;
        try {
            tasks = ApprovalMatrixClickUpApi.getTasks(
                settings.ClickUp_List_Id__c,
                settings.Handoff_Status__c.trim(),
                page
            );
        } catch (ApprovalMatrixClickUpApi.ClickUpApiException apiError) {
            savePollResult(settings, apiError.getMessage());
            return;
        }

        settings.Last_Poll_At__c = System.now();
        settings.Last_Poll_Error__c = null;
        settings.Next_Page__c = tasks.size() == 100 ? page + 1 : 0;
        update settings;
        if (tasks.isEmpty()) {
            return;
        }

        Set<String> taskIds = new Set<String>();
        for (Map<String, Object> task : tasks) {
            String taskId = stringValue(task.get('id'));
            if (String.isNotBlank(taskId)) {
                taskIds.add(taskId);
            }
        }
        Map<String, Approval_Matrix_Request__c> requestsByTaskId =
            new Map<String, Approval_Matrix_Request__c>();
        if (!taskIds.isEmpty()) {
            for (Approval_Matrix_Request__c requestRecord : [
                SELECT Id, ClickUp_Task_Id__c, ClickUp_Last_Modified__c,
                    Status__c
                FROM Approval_Matrix_Request__c
                WHERE ClickUp_Task_Id__c IN :taskIds
            ]) {
                requestsByTaskId.put(requestRecord.ClickUp_Task_Id__c, requestRecord);
            }
        }

        Integer processedCount = 0;
        for (Map<String, Object> task : tasks) {
            if (processedCount >= MAX_TASKS_PER_RUN) {
                break;
            }
            String taskId = stringValue(task.get('id'));
            String taskStatus = getTaskStatus(task.get('status'));
            if (String.isBlank(taskId) || String.isBlank(taskStatus) ||
                taskStatus.toLowerCase() != settings.Handoff_Status__c.trim().toLowerCase()) {
                continue;
            }

            String lastModified = stringValue(task.get('date_updated'));
            if (String.isBlank(lastModified)) {
                markTaskError(
                    getOrCreateRequest(taskId, requestsByTaskId),
                    'ClickUp task response did not include date_updated.',
                    null
                );
                continue;
            }
            Approval_Matrix_Request__c requestRecord =
                requestsByTaskId.get(taskId);
            if (requestRecord == null) {
                requestRecord = getOrCreateRequest(taskId, requestsByTaskId);
            }
            if (isTerminal(requestRecord.Status__c) ||
                requestRecord.ClickUp_Last_Modified__c == lastModified) {
                continue;
            }

            processedCount++;
            String description = stringValue(task.get('markdown_description'));
            if (String.isBlank(description)) {
                description = stringValue(task.get('description'));
            }
            try {
                ApprovalMatrixClickUpIntakeService.processTask(
                    requestRecord.Id,
                    taskId,
                    lastModified,
                    description,
                    stringValue(task.get('url'))
                );
            } catch (Exception processingError) {
                markTaskError(
                    requestRecord,
                    'Could not stage ClickUp task. ' + processingError.getMessage(),
                    lastModified
                );
            }
        }
    }

    private static Approval_Matrix_Request__c getOrCreateRequest(
        String taskId,
        Map<String, Approval_Matrix_Request__c> requestsByTaskId
    ) {
        Approval_Matrix_Request__c requestRecord =
            new Approval_Matrix_Request__c(
                ClickUp_Task_Id__c = taskId,
                Status__c = 'Received'
            );
        Database.SaveResult result = Database.insert(requestRecord, false);
        if (result.isSuccess()) {
            requestRecord.Id = result.getId();
            requestsByTaskId.put(taskId, requestRecord);
            return requestRecord;
        }

        for (Database.Error error : result.getErrors()) {
            if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                List<Approval_Matrix_Request__c> existingRequests = [
                    SELECT Id, ClickUp_Task_Id__c, ClickUp_Last_Modified__c,
                        Status__c
                    FROM Approval_Matrix_Request__c
                    WHERE ClickUp_Task_Id__c = :taskId
                    LIMIT 1
                ];
                if (!existingRequests.isEmpty()) {
                    requestsByTaskId.put(taskId, existingRequests[0]);
                    return existingRequests[0];
                }
            }
        }
        throw new ApprovalMatrixClickUpApi.ClickUpApiException(
            'Could not create or locate the ClickUp staging request.'
        );
    }

    private static void markTaskError(
        Approval_Matrix_Request__c requestRecord,
        String message,
        String lastModified
    ) {
        update new Approval_Matrix_Request__c(
            Id = requestRecord.Id,
            Status__c = 'Error',
            Processing_Error__c = message,
            ClickUp_Last_Modified__c = lastModified
        );
    }

    private static void savePollResult(
        Approval_Matrix_ClickUp_Settings__c settings,
        String message
    ) {
        if (settings == null) {
            settings = new Approval_Matrix_ClickUp_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
        }
        settings.Last_Poll_At__c = System.now();
        settings.Last_Poll_Error__c = message;
        upsert settings;
    }

    private static Boolean isTerminal(String status) {
        return new Set<String>{ 'Approved', 'Inserted', 'Rejected' }.contains(status);
    }

    private static String getTaskStatus(Object statusValue) {
        if (statusValue == null) {
            return null;
        }
        try {
            Map<String, Object> statusMap = (Map<String, Object>) statusValue;
            return stringValue(statusMap.get('status'));
        } catch (TypeException invalidStatus) {
            return stringValue(statusValue);
        }
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}