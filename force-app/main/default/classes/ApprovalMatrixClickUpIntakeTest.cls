@IsTest
private class ApprovalMatrixClickUpIntakeTest {
    private static final String LIST_ID = 'list-123';
    private static final String READY_STATUS = 'awaiting approval';

    private class TaskListMock implements HttpCalloutMock {
        private List<Map<String, Object>> tasks;
        private Integer statusCode;

        TaskListMock(List<Map<String, Object>> tasks, Integer statusCode) {
            this.tasks = tasks;
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().contains('/v2/list/' + LIST_ID + '/task'));
            System.assert(request.getEndpoint().contains('statuses%5B%5D=awaiting+approval'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(JSON.serialize(new Map<String, Object>{ 'tasks' => tasks }));
            return response;
        }
    }

    private class RawResponseMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        RawResponseMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    private static void configureClickUp() {
        insert new Approval_Matrix_ClickUp_Settings__c(
            Name = 'Org Defaults',
            SetupOwnerId = UserInfo.getOrganizationId(),
            ClickUp_List_Id__c = LIST_ID,
            Handoff_Status__c = READY_STATUS
        );
    }

    private static Map<String, Object> task(
        String taskId,
        String lastModified,
        String description,
        String status
    ) {
        return new Map<String, Object>{
            'id' => taskId,
            'date_updated' => lastModified,
            'markdown_description' => description,
            'description' => description,
            'url' => 'https://app.clickup.com/t/' + taskId,
            'status' => new Map<String, Object>{ 'status' => status }
        };
    }

    private static String taskDescription(String rows) {
        return 'Dear Team,\n\nKindly help to update the approval matrix as per below details.\n\n' +
            '| Item | GM | AGM | RM |\n' +
            '| --- | ---: | ---: | ---: |\n' +
            rows;
    }

    private static void enqueuePoll(List<Map<String, Object>> tasks, Integer statusCode) {
        Test.setMock(HttpCalloutMock.class, new TaskListMock(tasks, statusCode));
        System.enqueueJob(new ApprovalMatrixClickUpSyncQueueable());
    }

    private static Approval_Matrix_Request__c createRequest(String taskId, String status) {
        Approval_Matrix_Request__c requestRecord = new Approval_Matrix_Request__c(
            ClickUp_Task_Id__c = taskId,
            Status__c = status,
            Record_Type__c = 'Lighting',
            From_ClickUp__c = true
        );
        insert requestRecord;
        return requestRecord;
    }

    @IsTest
    static void pollsStagesAndVerifierApprovalWritesLegacyLightingMatrix() {
        configureClickUp();
        Product2 product = new Product2(
            Name = 'ClickUp Lighting product',
            ProductCode = 'PBTM28707',
            IsActive = true
        );
        insert product;
        ApprovalMatrix__c existingMatrix = new ApprovalMatrix__c(
            Name = 'Existing Lighting entry',
            productName__c = product.ProductCode,
            Request_Type__c = 'Lighting',
            ApprovalMatrix_Key__c = 'old-lighting-key-28707',
            GM__c = 100,
            AGM__c = 200,
            RM__c = 300
        );
        insert existingMatrix;
        Test.startTest();
        enqueuePoll(
            new List<Map<String, Object>>{
                task(
                    'task-28707',
                    '1793690000000',
                    taskDescription('| PBTM28707 | 900 | 920 | 940 |'),
                    READY_STATUS
                )
            },
            200
        );
        Test.stopTest();

        Approval_Matrix_Request__c requestRecord = [
            SELECT Id, Status__c, From_ClickUp__c, ClickUp_Task_Url__c,
                ClickUp_Task_Id__c, ClickUp_Last_Modified__c, Error_Count__c
            FROM Approval_Matrix_Request__c
            WHERE ClickUp_Task_Id__c = 'task-28707'
        ];
        System.assertEquals(true, requestRecord.From_ClickUp__c);
        System.assertEquals('Pending Verification', requestRecord.Status__c);
        System.assertEquals('1793690000000', requestRecord.ClickUp_Last_Modified__c);
        System.assertEquals('https://app.clickup.com/t/task-28707', requestRecord.ClickUp_Task_Url__c);

        Approval_Matrix_Request_Line__c line = [
            SELECT Id, Product_Code__c, GM__c, AGM__c, RM__c,
                Line_Status__c, Matched_Product_Count__c, Existing_Matrix_Count__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestRecord.Id
        ];
        System.assertEquals('PBTM28707', line.Product_Code__c);
        System.assertEquals(900, line.GM__c);
        System.assertEquals(920, line.AGM__c);
        System.assertEquals(940, line.RM__c);
        System.assertEquals('Valid', line.Line_Status__c);
        System.assertEquals(1, line.Matched_Product_Count__c);
        System.assertEquals(1, line.Existing_Matrix_Count__c);

        ApprovalMatrixVerificationController.approveSelected(
            requestRecord.Id,
            new List<Id>{ line.Id }
        );
        ApprovalMatrix__c savedMatrix = [
            SELECT Id, productName__c, Request_Type__c, GM__c, AGM__c, RM__c
            FROM ApprovalMatrix__c
            WHERE Id = :existingMatrix.Id
        ];
        System.assertEquals('PBTM28707', savedMatrix.productName__c);
        System.assertEquals('Lighting', savedMatrix.Request_Type__c);
        System.assertEquals(900, savedMatrix.GM__c);
        System.assertEquals(920, savedMatrix.AGM__c);
        System.assertEquals(940, savedMatrix.RM__c);
        System.assertEquals(1, [SELECT count() FROM ApprovalMatrix__c]);
    }

    @IsTest
    static void repeatedPollDoesNotDuplicateRequestsOrLines() {
        configureClickUp();
        insert new Product2(
            Name = 'Duplicate poll product',
            ProductCode = 'PELM02043',
            IsActive = true
        );
        List<Map<String, Object>> tasks = new List<Map<String, Object>>{
            task(
                'task-duplicate',
                '1793690000001',
                taskDescription('| PELM02043 | 500 | 510 | 520 |'),
                READY_STATUS
            )
        };

        Test.startTest();
        enqueuePoll(tasks, 200);
        Test.stopTest();

        Id requestId = [
            SELECT Id, ClickUp_Task_Id__c
            FROM Approval_Matrix_Request__c
            WHERE ClickUp_Task_Id__c = 'task-duplicate'
        ].Id;
        ApprovalMatrixClickUpIntakeService.processTask(
            requestId,
            'task-duplicate',
            '1793690000001',
            taskDescription('| PELM02043 | 500 | 510 | 520 |'),
            'https://app.clickup.com/t/task-duplicate'
        );
        System.assertEquals(
            1,
            [SELECT count() FROM Approval_Matrix_Request_Line__c WHERE Request__c = :requestId]
        );
        System.assertEquals(
            1,
            [SELECT count() FROM Approval_Matrix_Request__c
             WHERE ClickUp_Task_Id__c = 'task-duplicate']
        );
    }

    @IsTest
    static void editedUnapprovedTaskRefreshesItsStagingLines() {
        configureClickUp();
        insert new Product2(
            Name = 'Updated task product',
            ProductCode = 'PSTM30757',
            IsActive = true
        );
        Test.startTest();
        enqueuePoll(
            new List<Map<String, Object>>{
                task(
                    'task-updated',
                    '1793690000002',
                    taskDescription('| PSTM30757 | 2400 | 2450 | 2500 |'),
                    READY_STATUS
                )
            },
            200
        );
        Test.stopTest();

        Approval_Matrix_Request__c requestRecord = [
            SELECT Id, ClickUp_Last_Modified__c
            FROM Approval_Matrix_Request__c
            WHERE ClickUp_Task_Id__c = 'task-updated'
        ];
        ApprovalMatrixClickUpIntakeService.processTask(
            requestRecord.Id,
            'task-updated',
            '1793690000003',
            taskDescription('| PSTM30757 | 2500 | 2550 | 2600 |'),
            'https://app.clickup.com/t/task-updated'
        );
        requestRecord = [
            SELECT Id, ClickUp_Last_Modified__c
            FROM Approval_Matrix_Request__c
            WHERE Id = :requestRecord.Id
        ];
        System.assertEquals('1793690000003', requestRecord.ClickUp_Last_Modified__c);
        List<Approval_Matrix_Request_Line__c> lines = [
            SELECT GM__c, AGM__c, RM__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestRecord.Id
        ];
        System.assertEquals(1, lines.size());
        System.assertEquals(2500, lines[0].GM__c);
        System.assertEquals(2550, lines[0].AGM__c);
        System.assertEquals(2600, lines[0].RM__c);
    }

    @IsTest
    static void malformedRowsRemainVisibleAndOtherStatusesAreIgnored() {
        configureClickUp();
        Test.startTest();
        enqueuePoll(
            new List<Map<String, Object>>{
                task(
                    'task-malformed',
                    '1793690000004',
                    taskDescription('| PBTM28707 | 900 | invalid | 940 |'),
                    READY_STATUS
                ),
                task(
                    'task-not-ready',
                    '1793690000005',
                    taskDescription('| PBTM28707 | 900 | 920 | 940 |'),
                    'approved'
                )
            },
            200
        );
        Test.stopTest();
        Approval_Matrix_Request__c requestRecord = [
            SELECT Id, Status__c, Error_Count__c
            FROM Approval_Matrix_Request__c
            WHERE ClickUp_Task_Id__c = 'task-malformed'
        ];
        System.assertEquals('Validation Error', requestRecord.Status__c);
        System.assertEquals(1, requestRecord.Error_Count__c);
        Approval_Matrix_Request_Line__c line = [
            SELECT Line_Status__c, Error_Message__c, Raw_Input__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestRecord.Id
        ];
        System.assertEquals('Error', line.Line_Status__c);
        System.assert(line.Error_Message__c.contains('must be numeric'));
        System.assert(line.Raw_Input__c.contains('invalid'));
        System.assertEquals(
            0,
            [SELECT count() FROM Approval_Matrix_Request__c
             WHERE ClickUp_Task_Id__c = 'task-not-ready']
        );
    }

    @IsTest
    static void clickUpApiFailureIsShownInSyncStatus() {
        configureClickUp();
        Test.setMock(HttpCalloutMock.class, new TaskListMock(new List<Map<String, Object>>(), 401));
        Test.startTest();
        System.enqueueJob(new ApprovalMatrixClickUpSyncQueueable());
        Test.stopTest();

        Approval_Matrix_ClickUp_Settings__c settings =
            Approval_Matrix_ClickUp_Settings__c.getOrgDefaults();
        System.assertEquals('ClickUp returned HTTP 401. Check the Named Credential token and List access.',
            settings.Last_Poll_Error__c);
        System.assertNotEquals(null, settings.Last_Poll_At__c);
    }

    @IsTest
    static void clickUpApiRejectsMalformedTaskResponses() {
        Test.setMock(
            HttpCalloutMock.class,
            new RawResponseMock(200, '{"tasks":"not-an-array"}')
        );
        try {
            ApprovalMatrixClickUpApi.getTasks(LIST_ID, READY_STATUS, 0);
            System.assert(false, 'A tasks value must be an array.');
        } catch (ApprovalMatrixClickUpApi.ClickUpApiException expected) {
            System.assert(expected.getMessage().contains('tasks array'));
        }

        Test.setMock(
            HttpCalloutMock.class,
            new RawResponseMock(200, '{"tasks":["not-a-task-object"]}')
        );
        try {
            ApprovalMatrixClickUpApi.getTasks(LIST_ID, READY_STATUS, 0);
            System.assert(false, 'Every task value must be an object.');
        } catch (ApprovalMatrixClickUpApi.ClickUpApiException expected) {
            System.assert(expected.getMessage().contains('invalid task'));
        }

        Test.setMock(HttpCalloutMock.class, new RawResponseMock(200, '{invalid'));
        try {
            ApprovalMatrixClickUpApi.getTasks(LIST_ID, READY_STATUS, 0);
            System.assert(false, 'The response must be valid JSON.');
        } catch (ApprovalMatrixClickUpApi.ClickUpApiException expected) {
            System.assert(expected.getMessage().contains('invalid JSON'));
        }
    }

    @IsTest
    static void pollWithoutConfigurationStoresAnActionableError() {
        Test.startTest();
        System.enqueueJob(new ApprovalMatrixClickUpSyncQueueable());
        Test.stopTest();

        Approval_Matrix_ClickUp_Settings__c settings =
            Approval_Matrix_ClickUp_Settings__c.getOrgDefaults();
        System.assertNotEquals(null, settings);
        System.assertEquals(
            'Configure the ClickUp List ID and handoff status.',
            settings.Last_Poll_Error__c
        );
    }

    @IsTest
    static void pollMarksMissingTaskTimestampAndDoesNotReprocessTerminalRequest() {
        configureClickUp();
        Approval_Matrix_Request__c terminalRequest =
            createRequest('task-terminal', 'Inserted');
        Test.startTest();
        enqueuePoll(
            new List<Map<String, Object>>{
                task(
                    'task-terminal',
                    '1793690000006',
                    taskDescription('| PBTM28707 | 900 | 920 | 940 |'),
                    READY_STATUS
                ),
                task(
                    'task-missing-timestamp',
                    null,
                    taskDescription('| PBTM28707 | 900 | 920 | 940 |'),
                    READY_STATUS
                )
            },
            200
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT count() FROM Approval_Matrix_Request_Line__c
             WHERE Request__c = :terminalRequest.Id]
        );
        Approval_Matrix_Request__c failedRequest = [
            SELECT Status__c, Processing_Error__c
            FROM Approval_Matrix_Request__c
            WHERE ClickUp_Task_Id__c = 'task-missing-timestamp'
        ];
        System.assertEquals('Error', failedRequest.Status__c);
        System.assert(failedRequest.Processing_Error__c.contains('date_updated'));
    }

    @IsTest
    static void parserLeavesEmptyAndUnrecognizedDescriptionsVisible() {
        Approval_Matrix_Request__c emptyRequest =
            createRequest('task-empty-description', 'Received');
        Approval_Matrix_Request__c missingTableRequest =
            createRequest('task-no-table', 'Received');
        ApprovalMatrixClickUpIntakeService.processTask(
            emptyRequest.Id,
            emptyRequest.ClickUp_Task_Id__c,
            '1793690000007',
            '',
            null
        );
        ApprovalMatrixClickUpIntakeService.processTask(
            missingTableRequest.Id,
            missingTableRequest.ClickUp_Task_Id__c,
            '1793690000008',
            'There is no approval table in this task.',
            null
        );

        Set<Id> requestIds = new Set<Id>{ emptyRequest.Id, missingTableRequest.Id };
        List<Approval_Matrix_Request__c> requests = [
            SELECT Status__c, Error_Count__c
            FROM Approval_Matrix_Request__c
            WHERE Id IN :requestIds
        ];
        System.assertEquals(2, requests.size());
        for (Approval_Matrix_Request__c requestRecord : requests) {
            System.assertEquals('Validation Error', requestRecord.Status__c);
            System.assertEquals(1, requestRecord.Error_Count__c);
        }
    }

    @IsTest
    static void clickUpControllerExposesPollStatusAndClickUpOnlyRequests() {
        configureClickUp();
        Approval_Matrix_Request__c clickUpRequest =
            createRequest('task-controller-clickup', 'Pending Verification');
        insert new Approval_Matrix_Request__c(
            ClickUp_Task_Id__c = 'task-controller-manual',
            Status__c = 'Received'
        );

        System.assertEquals(1, ApprovalMatrixVerificationController.getClickUpRequests().size());
        System.assertEquals(2, ApprovalMatrixVerificationController.getRequests().size());
        ApprovalMatrixVerificationController.ClickUpSyncStatus syncStatus =
            ApprovalMatrixVerificationController.getClickUpSyncStatus();
        System.assertEquals(LIST_ID, syncStatus.listId);
        System.assertEquals(READY_STATUS, syncStatus.handoffStatus);
        System.assertEquals(true, syncStatus.configured);

        ApprovalMatrixVerificationController.RequestView requestView =
            ApprovalMatrixVerificationController.getClickUpRequest(clickUpRequest.Id);
        System.assertEquals(clickUpRequest.Id, requestView.requestRecord.Id);
        System.assertEquals(true, requestView.requestRecord.From_ClickUp__c);

        Test.setMock(
            HttpCalloutMock.class,
            new TaskListMock(new List<Map<String, Object>>(), 200)
        );
        Test.startTest();
        System.assertNotEquals(null, ApprovalMatrixVerificationController.syncClickUpNow());
        Test.stopTest();

        try {
            ApprovalMatrixVerificationController.getRequest(null);
            System.assert(false, 'A request ID is required.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
        try {
            ApprovalMatrixVerificationController.getClickUpRequest(
                [SELECT Id FROM Approval_Matrix_Request__c
                 WHERE ClickUp_Task_Id__c = 'task-controller-manual'].Id
            );
            System.assert(false, 'Manual requests are not ClickUp requests.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
        try {
            ApprovalMatrixVerificationController.approveSelected(
                clickUpRequest.Id,
                null
            );
            System.assert(false, 'At least one line must be selected.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
        try {
            ApprovalMatrixVerificationController.approveSelected(
                [SELECT Id FROM Approval_Matrix_Request__c
                 WHERE ClickUp_Task_Id__c = 'task-controller-manual'].Id,
                new List<Id>()
            );
            System.assert(false, 'A received request is not open for verification.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
        try {
            ApprovalMatrixVerificationController.rejectRequest(
                clickUpRequest.Id,
                ''
            );
            System.assert(false, 'A rejection reason is required.');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
        ApprovalMatrixVerificationController.rejectRequest(
            clickUpRequest.Id,
            'Rejected during test'
        );
        System.assertEquals(
            'Rejected',
            [SELECT Status__c FROM Approval_Matrix_Request__c
             WHERE Id = :clickUpRequest.Id].Status__c
        );
    }

    @IsTest
    static void schedulerStartsAConfiguredPoll() {
        configureClickUp();
        Test.setMock(
            HttpCalloutMock.class,
            new TaskListMock(new List<Map<String, Object>>(), 200)
        );
        Test.startTest();
        new ApprovalMatrixClickUpPollScheduler().execute(null);
        Test.stopTest();
        System.assertNotEquals(
            null,
            Approval_Matrix_ClickUp_Settings__c.getOrgDefaults().Last_Poll_At__c
        );
    }
}