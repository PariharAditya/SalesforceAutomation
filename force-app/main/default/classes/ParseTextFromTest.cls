@IsTest
private class ParseTextFromTest {
    private static final String POWER_TEXT =
        'Request Type: Power\n' +
        'Division: WIRES CABLES AND TAPES\n' +
        'Category: WIRES\n' +
        'Brand: MULTICORE CABLE\n' +
        'Product Category: Cables Wires and Tapes\n' +
        'Sales Discount: 10\n' +
        'Discount Percentage: 15\n' +
        'Discount Max: 20\n' +
        'Above Policy Discount Percentage: 25\n' +
        'Approval Level: RSM\n' +
        'Approval Max: 30\n' +
        'Approval Greater Than Max: NSM\n' +
        'Above Policy Level: GM';

    @IsTest
    static void parsesPowerRequest() {
        ParseApprovalMatrix.ParsedRequest result = ParseApprovalMatrix.parse(POWER_TEXT);

        System.assertEquals(true, result.isValid);
        System.assertEquals('Power', result.requestType);
        System.assertEquals('WIRES', result.category);
        System.assertEquals('MULTICORE CABLE', result.brand);
        System.assertEquals(10, result.salesDiscount);
        System.assertEquals(15, result.discountPercentage);
        System.assertEquals(20, result.discountMax);
        System.assertEquals(25, result.abovePolicyDiscountPercentage);
        System.assertEquals('RSM', result.approvalLevel);
        System.assertEquals(30, result.approvalMax);
        System.assertEquals('NSM', result.approvalGreaterThanMax);
        System.assertEquals('GM', result.abovePolicyLevel);
    }

    @IsTest
    static void parsesLightingRequestAndNormalizesNumbers() {
        String text =
            'Request Type: Lighting\r\n' +
            'Product Category: Others\r\n' +
            'GM: $1,250.5\r\n' +
            'AGM: 75%\r\n' +
            'RM: 50';

        ParseApprovalMatrix.ParsedRequest result = ParseApprovalMatrix.parse(text);

        System.assertEquals(true, result.isValid);
        System.assertEquals('Lighting', result.requestType);
        System.assertEquals('Others', result.productCategory);
        System.assertEquals(1250.5, result.gm);
        System.assertEquals(75, result.agm);
        System.assertEquals(50, result.rm);
    }

    @IsTest
    static void reportsMalformedPowerRequest() {
        String text = POWER_TEXT
            .replace('Category: WIRES', 'Category: WIRES\nCategory: CABLES')
            .replace('Discount Max: 20', 'Discount Max: twenty');

        ParseApprovalMatrix.ParsedRequest result = ParseApprovalMatrix.parse(text);

        System.assertEquals(false, result.isValid);
        System.assert(result.errorMessage.contains('Duplicate label: Category.'));
        System.assert(result.errorMessage.contains('Discount Max must be numeric.'));
    }

    @IsTest
    static void rejectsUnsupportedLinesAndEmptyText() {
        ParseApprovalMatrix.ParsedRequest malformed = ParseApprovalMatrix.parse(
            'Request Type: Lighting\nUnexpected line'
        );
        ParseApprovalMatrix.ParsedRequest empty = ParseApprovalMatrix.parse('  \n');

        System.assertEquals(false, malformed.isValid);
        System.assert(malformed.errorMessage.contains('Label: value'));
        System.assertEquals(false, empty.isValid);
        System.assertEquals('The TXT file is empty.', empty.errorMessage);
    }

    @IsTest
    static void readsUploadedTxtAndRejectsOtherExtensions() {
        ContentVersion txtFile = new ContentVersion(
            Title = 'power-request',
            PathOnClient = 'power-request.txt',
            VersionData = Blob.valueOf(POWER_TEXT)
        );
        ContentVersion csvFile = new ContentVersion(
            Title = 'unsupported-request',
            PathOnClient = 'unsupported-request.csv',
            VersionData = Blob.valueOf('Request Type: Lighting')
        );
        insert new List<ContentVersion>{ txtFile, csvFile };

        List<ParseTextFrom.Request> requests = new List<ParseTextFrom.Request>();
        ParseTextFrom.Request txtRequest = new ParseTextFrom.Request();
        txtRequest.contentVersionId = txtFile.Id;
        requests.add(txtRequest);

        ParseTextFrom.Request csvRequest = new ParseTextFrom.Request();
        csvRequest.contentVersionId = csvFile.Id;
        requests.add(csvRequest);

        List<ParseTextFrom.Output> outputs;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            outputs = ParseTextFrom.parseUploadedFiles(requests);
        }

        System.assertEquals(2, outputs.size());
        System.assertEquals(true, outputs[0].isValid);
        System.assertEquals(
            true,
            outputs[0].isSaved,
            outputs[0].errorMessage == null ? 'No save error message was returned.' : outputs[0].errorMessage
        );
        System.assertNotEquals(null, outputs[0].approvalMatrixId);
        System.assertEquals('Power', outputs[0].requestType);
        System.assertEquals(false, outputs[1].isValid);
        System.assertEquals(false, outputs[1].isSaved);
        System.assertEquals('Only .txt files are supported.', outputs[1].errorMessage);

        ApprovalMatrix__c savedRecord = [
            SELECT
                productName__c,
                role__c,
                Discount__c,
                Request_Type__c,
                Division__c,
                Category__c,
                Brand__c,
                Discount_Percentage__c,
                Discount_Max__c,
                Above_Policy_Discount_Percentage__c,
                Approval_Max__c,
                Approval_Greater_Than_Max__c,
                Above_Policy_Level__c
            FROM ApprovalMatrix__c
            WHERE Id = :outputs[0].approvalMatrixId
        ];
        System.assertEquals('Cables Wires and Tapes', savedRecord.productName__c);
        System.assertEquals('RSM', savedRecord.role__c);
        System.assertEquals(10, savedRecord.Discount__c);
        System.assertEquals('Power', savedRecord.Request_Type__c);
        System.assertEquals('WIRES CABLES AND TAPES', savedRecord.Division__c);
        System.assertEquals('WIRES', savedRecord.Category__c);
        System.assertEquals('MULTICORE CABLE', savedRecord.Brand__c);
        System.assertEquals(15, savedRecord.Discount_Percentage__c);
        System.assertEquals(20, savedRecord.Discount_Max__c);
        System.assertEquals(25, savedRecord.Above_Policy_Discount_Percentage__c);
        System.assertEquals(30, savedRecord.Approval_Max__c);
        System.assertEquals('NSM', savedRecord.Approval_Greater_Than_Max__c);
        System.assertEquals('GM', savedRecord.Above_Policy_Level__c);

        List<ParseTextFrom.Output> repeatedOutputs;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            repeatedOutputs = ParseTextFrom.parseUploadedFiles(
                new List<ParseTextFrom.Request>{ txtRequest }
            );
        }
        System.assertEquals(true, repeatedOutputs[0].isSaved);
        System.assertEquals(outputs[0].approvalMatrixId, repeatedOutputs[0].approvalMatrixId);
        System.assertEquals(
            1,
            [SELECT count() FROM ApprovalMatrix__c WHERE Id = :outputs[0].approvalMatrixId]
        );
    }

    @IsTest
    static void persistsLightingRequestFields() {
        ContentVersion lightingFile = new ContentVersion(
            Title = 'lighting-request',
            PathOnClient = 'lighting-request.txt',
            VersionData = Blob.valueOf(
                'Request Type: Lighting\n' +
                'Product Category: Others\n' +
                'GM: 100\n' +
                'AGM: 75\n' +
                'RM: 50'
            )
        );
        insert lightingFile;

        ParseTextFrom.Request request = new ParseTextFrom.Request();
        request.contentVersionId = lightingFile.Id;
        List<ParseTextFrom.Output> outputs;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            outputs = ParseTextFrom.parseUploadedFiles(new List<ParseTextFrom.Request>{ request });
        }

        System.assertEquals(true, outputs[0].isValid);
        System.assertEquals(
            true,
            outputs[0].isSaved,
            outputs[0].errorMessage == null ? 'No save error message was returned.' : outputs[0].errorMessage
        );
        ApprovalMatrix__c savedRecord = [
            SELECT productName__c, role__c, Discount__c, Request_Type__c, GM__c, AGM__c, RM__c
            FROM ApprovalMatrix__c
            WHERE Id = :outputs[0].approvalMatrixId
        ];
        System.assertEquals('Others', savedRecord.productName__c);
        System.assertEquals('GM', savedRecord.role__c);
        System.assertEquals(100, savedRecord.Discount__c);
        System.assertEquals('Lighting', savedRecord.Request_Type__c);
        System.assertEquals(100, savedRecord.GM__c);
        System.assertEquals(75, savedRecord.AGM__c);
        System.assertEquals(50, savedRecord.RM__c);
    }
}