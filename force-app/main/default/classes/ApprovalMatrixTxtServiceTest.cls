@IsTest
private class ApprovalMatrixTxtServiceTest {
    private static Approval_Matrix_Request__c createRequest(String taskId) {
        Approval_Matrix_Request__c requestRecord = new Approval_Matrix_Request__c(
            ClickUp_Task_Id__c = taskId,
            Status__c = 'Received'
        );
        insert requestRecord;
        return requestRecord;
    }

    private static void attachTextFile(Id requestId, String title, String text) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.txt',
            VersionData = Blob.valueOf(text)
        );
        insert version;
        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
        insert new ContentDocumentLink(
            ContentDocumentId = version.ContentDocumentId,
            LinkedEntityId = requestId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    @IsTest
    static void parsesMapsAndInsertsLightingRequest() {
        Product2 firstProduct = new Product2(
            Name = 'Lighting product one',
            ProductCode = 'PCNM05408',
            IsActive = true
        );
        Product2 secondProduct = new Product2(
            Name = 'Lighting product two',
            ProductCode = 'PCNM05409',
            IsActive = true
        );
        insert new List<Product2>{ firstProduct, secondProduct };

        Approval_Matrix_Request__c requestRecord = createRequest('lighting-task-1');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            attachTextFile(
                requestRecord.Id,
                'lighting-request',
                'TASK_ID: lighting-task-1\n' +
                'RECORD_TYPE: LIGHTING\n' +
                '---\n' +
                'PCNM05408|4000|4080|4160\n' +
                'PCNM05409|3900|3950|4020'
            );
            Test.stopTest();
        }

        requestRecord = [
            SELECT Status__c, Record_Type__c, Source_File_Id__c, Processing_Error__c
            FROM Approval_Matrix_Request__c
            WHERE Id = :requestRecord.Id
        ];
        System.assertEquals('Pending Verification', requestRecord.Status__c);
        System.assertEquals('Lighting', requestRecord.Record_Type__c);
        System.assertNotEquals(null, requestRecord.Source_File_Id__c);
        System.assertEquals(null, requestRecord.Processing_Error__c);

        List<Approval_Matrix_Request_Line__c> lines = [
            SELECT Id, Line_Status__c, Mapped_No_Approval_Value__c,
                Mapped_RSM_Price_Value__c, Mapped_NSM_Price_Value__c,
                Matched_Product_Count__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestRecord.Id
            ORDER BY Product_Code__c
        ];
        System.assertEquals(2, lines.size());
        System.assertEquals('Valid', lines[0].Line_Status__c);
        System.assertEquals(4160, lines[0].Mapped_No_Approval_Value__c);
        System.assertEquals(4080, lines[0].Mapped_RSM_Price_Value__c);
        System.assertEquals(4000, lines[0].Mapped_NSM_Price_Value__c);
        System.assertEquals(1, lines[0].Matched_Product_Count__c);

        List<Approval_Matrix_Request__c> workbenchRequests =
            ApprovalMatrixVerificationController.getRequests();
        System.assertEquals(1, workbenchRequests.size());
        System.assertEquals(requestRecord.Id, workbenchRequests[0].Id);
        ApprovalMatrixVerificationController.RequestView review =
            ApprovalMatrixVerificationController.getRequest(requestRecord.Id);
        System.assertEquals(2, review.lines.size());

        ApprovalMatrixTxtService.approve(
            requestRecord.Id,
            new Set<Id>{ lines[0].Id }
        );
        List<Product_Approval_Hierarchy__c> insertedMatrices = [
            SELECT Product__c, Record_Type__c, Product_Category__c,
                No_approval_value__c, RSM_Price_value__c, NSM_Price_Value__c
            FROM Product_Approval_Hierarchy__c
        ];
        System.assertEquals(1, insertedMatrices.size());
        System.assertEquals(firstProduct.Id, insertedMatrices[0].Product__c);
        System.assertEquals('Lighting', insertedMatrices[0].Record_Type__c);
        System.assertEquals('Others', insertedMatrices[0].Product_Category__c);
        System.assertEquals(4160, insertedMatrices[0].No_approval_value__c);
        System.assertEquals(4080, insertedMatrices[0].RSM_Price_value__c);
        System.assertEquals(4000, insertedMatrices[0].NSM_Price_Value__c);

        try {
            ApprovalMatrixTxtService.approve(
                requestRecord.Id,
                new Set<Id>{ lines[0].Id }
            );
            System.assert(false, 'An already inserted line must not be inserted again.');
        } catch (ApprovalMatrixTxtService.ApprovalMatrixException expected) {
            System.assert(expected.getMessage().contains('valid'));
        }
        System.assertEquals(1, [SELECT count() FROM Product_Approval_Hierarchy__c]);
    }

    @IsTest
    static void marksLightingTiesAsWarningAndBadRowsAsErrors() {
        insert new Product2(
            Name = 'Lighting tie product',
            ProductCode = 'TIE001',
            IsActive = true
        );
        Approval_Matrix_Request__c tieRequest = createRequest('lighting-task-tie');
        Approval_Matrix_Request__c malformedRequest = createRequest('lighting-task-bad');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            attachTextFile(
                tieRequest.Id,
                'lighting-tie',
                'TASK_ID: lighting-task-tie\nRECORD_TYPE: LIGHTING\n---\nTIE001|50|50|80'
            );
            attachTextFile(
                malformedRequest.Id,
                'lighting-bad',
                'TASK_ID: lighting-task-bad\nRECORD_TYPE: LIGHTING\n---\nTIE001|50|80'
            );
            Test.stopTest();
        }

        Approval_Matrix_Request_Line__c tieLine = [
            SELECT Line_Status__c, Warnings__c, Mapped_No_Approval_Value__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :tieRequest.Id
            LIMIT 1
        ];
        System.assertEquals('Valid', tieLine.Line_Status__c);
        System.assert(tieLine.Warnings__c.contains('tied'));
        System.assertEquals(80, tieLine.Mapped_No_Approval_Value__c);

        Approval_Matrix_Request__c invalidRequest = [
            SELECT Status__c, Error_Count__c
            FROM Approval_Matrix_Request__c
            WHERE Id = :malformedRequest.Id
        ];
        System.assertEquals('Validation Error', invalidRequest.Status__c);
        System.assertEquals(1, invalidRequest.Error_Count__c);
        Approval_Matrix_Request_Line__c invalidLine = [
            SELECT Line_Status__c, Parse_Error__c, Error_Message__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :malformedRequest.Id
            LIMIT 1
        ];
        System.assertEquals('Error', invalidLine.Line_Status__c);
        System.assertEquals(true, invalidLine.Parse_Error__c);
        System.assert(invalidLine.Error_Message__c.contains('expected 4 columns, found 3'));
    }

    @IsTest
    static void parsesPowerRowAndReportsNoProductMatches() {
        Approval_Matrix_Request__c requestRecord = createRequest('power-task-1');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            attachTextFile(
                requestRecord.Id,
                'power-request',
                'TASK_ID: power-task-1\n' +
                'RECORD_TYPE: POWER\n' +
                'PRODUCT_CATEGORY: Cables Wires and Tapes\n' +
                '---\n' +
                'WIRES CABLES AND TAPES|WIRES|MULTICORE CABLE|0|9|10|11|2|3|4|5'
            );
            Test.stopTest();
        }

        Approval_Matrix_Request_Line__c line = [
            SELECT Id, Line_Status__c, Matched_Product_Count__c,
                Sales_Discount__c, Discount_Percentage__c, Discount_Max__c,
                Above_Policy_Discount_Percentage__c, Approval_Level__c,
                Approval_Max__c, Approval_grt_max__c, Above_Policy_Level__c,
                Error_Message__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestRecord.Id
            LIMIT 1
        ];
        System.assertEquals('Error', line.Line_Status__c);
        System.assertEquals(0, line.Matched_Product_Count__c);
        System.assertEquals(0, line.Sales_Discount__c);
        System.assertEquals(9, line.Discount_Percentage__c);
        System.assertEquals(10, line.Discount_Max__c);
        System.assertEquals(11, line.Above_Policy_Discount_Percentage__c);
        System.assertEquals(2, line.Approval_Level__c);
        System.assertEquals(3, line.Approval_Max__c);
        System.assertEquals(4, line.Approval_grt_max__c);
        System.assertEquals(5, line.Above_Policy_Level__c);
        System.assert(line.Error_Message__c.contains('No active products match'));
    }
}
