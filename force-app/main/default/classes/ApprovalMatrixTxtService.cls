public without sharing class ApprovalMatrixTxtService {
    private class ParsedLine {
        Approval_Matrix_Request_Line__c line;
        Boolean parseError;

        ParsedLine(Approval_Matrix_Request_Line__c line, Boolean parseError) {
            this.line = line;
            this.parseError = parseError;
        }
    }

    private class FileContents {
        Map<String, String> headers = new Map<String, String>();
        List<String> rows = new List<String>();
        String headerError;
    }

    public static void processFiles(Set<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }

        Map<Id, ContentVersion> versionsByDocumentId = new Map<Id, ContentVersion>();
        for (ContentVersion version : [
            SELECT Id, ContentDocumentId, FileExtension, PathOnClient, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = true
        ]) {
            versionsByDocumentId.put(version.ContentDocumentId, version);
        }

        List<ContentDocumentLink> requestLinks = new List<ContentDocumentLink>();
        Set<Id> requestIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocumentIds
        ]) {
            if (link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == Approval_Matrix_Request__c.SObjectType) {
                requestLinks.add(link);
                requestIds.add(link.LinkedEntityId);
            }
        }

        Map<Id, Approval_Matrix_Request__c> requestsById =
            new Map<Id, Approval_Matrix_Request__c>([
                SELECT Id, ClickUp_Task_Id__c, Record_Type__c, Status__c, Source_File_Id__c
                FROM Approval_Matrix_Request__c
                WHERE Id IN :requestIds
            ]);

        for (ContentDocumentLink link : requestLinks) {
            ContentVersion version = versionsByDocumentId.get(link.ContentDocumentId);
            Approval_Matrix_Request__c requestRecord = requestsById.get(link.LinkedEntityId);
            if (version == null || requestRecord == null) {
                continue;
            }
            processOneFile(requestRecord, version);
        }
    }

    private static void processOneFile(
        Approval_Matrix_Request__c requestRecord,
        ContentVersion version
    ) {
        String documentId = String.valueOf(version.ContentDocumentId);
        if (requestRecord.Source_File_Id__c == documentId) {
            return;
        }
        if (requestRecord.Status__c == 'Approved' ||
            requestRecord.Status__c == 'Inserted' ||
            requestRecord.Status__c == 'Rejected' ||
            requestRecord.Status__c == 'Pending Verification') {
            requestRecord.Status__c = 'Error';
            requestRecord.Processing_Error__c =
                'A different file was attached after verification began. Create a new request to submit a replacement.';
            update requestRecord;
            return;
        }

        String extension = version.FileExtension;
        if (String.isBlank(extension) && String.isNotBlank(version.PathOnClient)) {
            Integer dot = version.PathOnClient.lastIndexOf('.');
            if (dot >= 0) {
                extension = version.PathOnClient.substring(dot + 1);
            }
        }
        if (String.isBlank(extension) || !extension.equalsIgnoreCase('txt')) {
            failRequest(requestRecord, documentId, 'Only .txt files are supported.');
            return;
        }

        String text;
        try {
            text = version.VersionData.toString();
        } catch (StringException decodeError) {
            failRequest(requestRecord, documentId, 'The TXT file must contain valid UTF-8 text.');
            return;
        }

        FileContents file = parseFile(text);
        String taskId = file.headers.get('TASK_ID');
        if (String.isBlank(taskId)) {
            failRequest(requestRecord, documentId, 'TASK_ID is required in the TXT header.');
            return;
        }
        if (taskId != requestRecord.ClickUp_Task_Id__c) {
            failRequest(
                requestRecord,
                documentId,
                'The TXT TASK_ID does not match the linked request ClickUp Task Id.'
            );
            return;
        }

        String recordType = file.headers.get('RECORD_TYPE');
        if (String.isNotBlank(recordType)) {
            recordType = recordType.trim().toLowerCase();
            recordType = recordType == 'power' ? 'Power' :
                (recordType == 'lighting' ? 'Lighting' : null);
        }
        if (recordType == null) {
            failRequest(requestRecord, documentId, 'RECORD_TYPE must be POWER or LIGHTING.');
            return;
        }

        String productCategory = file.headers.get('PRODUCT_CATEGORY');
        if (recordType == 'Lighting' && String.isBlank(productCategory)) {
            productCategory = 'Others';
        }
        if (String.isBlank(productCategory)) {
            failRequest(
                requestRecord,
                documentId,
                'PRODUCT_CATEGORY is required for Power requests.'
            );
            return;
        }
        if (file.headerError != null) {
            failRequest(requestRecord, documentId, file.headerError);
            return;
        }

        List<Approval_Matrix_Request_Line__c> existingLines = [
            SELECT Id, Inserted_Matrix_Ids__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestRecord.Id
        ];
        for (Approval_Matrix_Request_Line__c existingLine : existingLines) {
            if (String.isNotBlank(existingLine.Inserted_Matrix_Ids__c)) {
                failRequest(
                    requestRecord,
                    documentId,
                    'This request already has inserted matrix records and cannot be replaced.'
                );
                return;
            }
        }
        if (!existingLines.isEmpty()) {
            delete existingLines;
        }

        List<ParsedLine> parsedLines = new List<ParsedLine>();
        Integer rowNumber = 0;
        for (String row : file.rows) {
            rowNumber++;
            if (String.isBlank(row)) {
                continue;
            }
            parsedLines.add(parseRow(row.trim(), rowNumber, recordType, productCategory, requestRecord.Id));
        }
        if (parsedLines.isEmpty()) {
            failRequest(requestRecord, documentId, 'The TXT file contains no data rows after the --- separator.');
            return;
        }

        List<Approval_Matrix_Request_Line__c> linesToInsert =
            new List<Approval_Matrix_Request_Line__c>();
        for (ParsedLine parsedLine : parsedLines) {
            linesToInsert.add(parsedLine.line);
        }

        requestRecord.Record_Type__c = recordType;
        requestRecord.Source_File_Id__c = documentId;
        requestRecord.Status__c = 'Parsed';
        update requestRecord;
        insert linesToInsert;
        validateRequest(requestRecord.Id);
    }

    private static FileContents parseFile(String text) {
        FileContents result = new FileContents();
        Boolean readingRows = false;
        for (String rawLine : text.replace('\r\n', '\n').replace('\r', '\n').split('\n')) {
            String line = rawLine.trim();
            if (line == '') {
                continue;
            }
            if (!readingRows && line == '---') {
                readingRows = true;
                continue;
            }
            if (readingRows) {
                result.rows.add(line);
                continue;
            }
            Integer separator = line.indexOf(':');
            if (separator <= 0) {
                result.headerError = 'Header lines must use KEY: value before the --- separator.';
                continue;
            }
            String key = line.substring(0, separator).trim().toUpperCase();
            String value = line.substring(separator + 1).trim();
            if (!new Set<String>{ 'TASK_ID', 'RECORD_TYPE', 'PRODUCT_CATEGORY' }.contains(key)) {
                result.headerError = 'Unsupported TXT header key: ' + key + '.';
            } else if (result.headers.containsKey(key)) {
                result.headerError = 'Duplicate TXT header key: ' + key + '.';
            } else {
                result.headers.put(key, value);
            }
        }
        if (!readingRows && result.headerError == null) {
            result.headerError = 'The TXT file is missing the --- separator.';
        }
        if (String.isBlank(result.headers.get('RECORD_TYPE')) && result.headerError == null) {
            result.headerError = 'RECORD_TYPE is required in the TXT header.';
        }
        return result;
    }

    private static ParsedLine parseRow(
        String rawRow,
        Integer rowNumber,
        String recordType,
        String productCategory,
        Id requestId
    ) {
        Approval_Matrix_Request_Line__c line = new Approval_Matrix_Request_Line__c(
            Request__c = requestId,
            Product_Category__c = productCategory,
            Raw_Input__c = rawRow,
            Line_Status__c = 'Valid'
        );
        List<String> columns = rawRow.split('\\|', -1);
        Integer expectedColumns = recordType == 'Lighting' ? 4 : 11;
        if (columns.size() != expectedColumns) {
            return parseError(line, true, 'Row ' + rowNumber + ': expected ' +
                expectedColumns + ' columns, found ' + columns.size() + '.');
        }
        for (Integer index = 0; index < columns.size(); index++) {
            columns[index] = columns[index].trim();
        }
        if (recordType == 'Lighting') {
            line.Product_Code__c = columns[0];
            line.Value_1__c = parseDecimal(columns[1]);
            line.Value_2__c = parseDecimal(columns[2]);
            line.Value_3__c = parseDecimal(columns[3]);
            if (line.Product_Code__c == '' || line.Value_1__c == null ||
                line.Value_2__c == null || line.Value_3__c == null) {
                return parseError(line, true,
                    'Row ' + rowNumber + ': product code and all three values must be present and numeric.');
            }
        } else {
            line.Division__c = columns[0];
            line.Category__c = columns[1];
            line.Brand__c = columns[2];
            line.Sales_Discount__c = parseDecimal(columns[3]);
            line.Discount_Percentage__c = parseDecimal(columns[4]);
            line.Discount_Max__c = parseDecimal(columns[5]);
            line.Above_Policy_Discount_Percentage__c = parseDecimal(columns[6]);
            line.Approval_Level__c = parseDecimal(columns[7]);
            line.Approval_Max__c = parseDecimal(columns[8]);
            line.Approval_grt_max__c = parseDecimal(columns[9]);
            line.Above_Policy_Level__c = parseDecimal(columns[10]);
            if (String.isBlank(line.Division__c) || String.isBlank(line.Category__c) ||
                String.isBlank(line.Brand__c) || line.Sales_Discount__c == null ||
                line.Discount_Percentage__c == null || line.Discount_Max__c == null ||
                line.Above_Policy_Discount_Percentage__c == null ||
                line.Approval_Level__c == null || line.Approval_Max__c == null ||
                line.Approval_grt_max__c == null || line.Above_Policy_Level__c == null) {
                return parseError(line, true,
                    'Row ' + rowNumber + ': Division, Category, Brand, and all eight numeric values are required.');
            }
        }
        return new ParsedLine(line, false);
    }

    private static ParsedLine parseError(
        Approval_Matrix_Request_Line__c line,
        Boolean isParseError,
        String message
    ) {
        line.Line_Status__c = 'Error';
        line.Parse_Error__c = isParseError;
        line.Error_Message__c = message;
        return new ParsedLine(line, isParseError);
    }

    private static Decimal parseDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Decimal.valueOf(value);
        } catch (TypeException numberError) {
            return null;
        }
    }

    private static void failRequest(
        Approval_Matrix_Request__c requestRecord,
        String documentId,
        String message
    ) {
        requestRecord.Source_File_Id__c = documentId;
        requestRecord.Status__c = 'Validation Error';
        requestRecord.Processing_Error__c = message;
        update requestRecord;
    }

    public static void validateRequest(Id requestId) {
        Approval_Matrix_Request__c requestRecord = [
            SELECT Id, Record_Type__c, From_ClickUp__c
            FROM Approval_Matrix_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        List<Approval_Matrix_Request_Line__c> lines = [
            SELECT Id, Product_Code__c, Division__c, Category__c, Brand__c,
                Product_Category__c, Value_1__c, Value_2__c, Value_3__c,
                Sales_Discount__c, Discount_Percentage__c, Discount_Max__c,
                Above_Policy_Discount_Percentage__c, Approval_Level__c,
                Approval_Max__c, Approval_grt_max__c, Above_Policy_Level__c,
                Line_Status__c, Error_Message__c, Warnings__c, Parse_Error__c,
                Matched_Product_Count__c, Existing_Matrix_Count__c,
                Mapped_No_Approval_Value__c, Mapped_RSM_Price_Value__c,
                Mapped_NSM_Price_Value__c, Inserted_Matrix_Ids__c,
                GM__c, AGM__c, RM__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestId
        ];
        if (lines.isEmpty()) {
            update new Approval_Matrix_Request__c(
                Id = requestId,
                Status__c = 'Validation Error'
            );
            return;
        }

        Set<String> productCodes = new Set<String>();
        Map<String, Integer> productCodeCountByValue = new Map<String, Integer>();
        Set<String> divisions = new Set<String>();
        Set<String> categories = new Set<String>();
        Set<String> brands = new Set<String>();
        for (Approval_Matrix_Request_Line__c line : lines) {
            if (requestRecord.Record_Type__c == 'Lighting' && line.Product_Code__c != null) {
                productCodes.add(line.Product_Code__c);
                String codeKey = line.Product_Code__c.trim().toUpperCase();
                productCodeCountByValue.put(
                    codeKey,
                    productCodeCountByValue.containsKey(codeKey)
                        ? productCodeCountByValue.get(codeKey) + 1 : 1
                );
            } else if (requestRecord.Record_Type__c == 'Power') {
                if (line.Division__c != null) divisions.add(line.Division__c);
                if (line.Category__c != null) categories.add(line.Category__c);
                if (line.Brand__c != null) brands.add(line.Brand__c);
            }
        }

        Map<Id, List<Product2>> productsByLineId = new Map<Id, List<Product2>>();
        Set<Id> productIds = new Set<Id>();
        List<Product2> candidateProducts = new List<Product2>();
        if (requestRecord.Record_Type__c == 'Lighting' && !productCodes.isEmpty()) {
            candidateProducts = [
                SELECT Id, ProductCode, Product_Category__c
                FROM Product2
                WHERE IsActive = true AND ProductCode IN :productCodes
            ];
        } else if (requestRecord.Record_Type__c == 'Power' &&
            !divisions.isEmpty() && !categories.isEmpty() && !brands.isEmpty()) {
            candidateProducts = [
                SELECT Id, ProductCode, Division__c, Category__c, Brand__c, Product_Category__c
                FROM Product2
                WHERE IsActive = true
                    AND Division__c IN :divisions
                    AND Category__c IN :categories
                    AND Brand__c IN :brands
                    AND Product_Category__c != null
            ];
        }
        for (Approval_Matrix_Request_Line__c line : lines) {
            List<Product2> matchedProducts = new List<Product2>();
            for (Product2 product : candidateProducts) {
                Boolean matched = requestRecord.Record_Type__c == 'Lighting'
                    ? product.ProductCode == line.Product_Code__c
                    : product.Division__c == line.Division__c &&
                        product.Category__c == line.Category__c &&
                        product.Brand__c == line.Brand__c;
                if (matched) {
                    matchedProducts.add(product);
                }
            }
            productsByLineId.put(line.Id, matchedProducts);
            for (Product2 product : matchedProducts) {
                productIds.add(product.Id);
            }
        }

        Map<Id, Integer> existingCountByProductId = new Map<Id, Integer>();
        Map<Id, List<String>> existingSummaryByProductId = new Map<Id, List<String>>();
        Map<String, List<ApprovalMatrix__c>> existingLightingByProductCode =
            new Map<String, List<ApprovalMatrix__c>>();
        if (requestRecord.Record_Type__c == 'Lighting' &&
            requestRecord.From_ClickUp__c == true && !productCodes.isEmpty()) {
            for (ApprovalMatrix__c matrix : [
                SELECT Id, Name, productName__c, Request_Type__c, GM__c, AGM__c, RM__c,
                    ApprovalMatrix_Key__c
                FROM ApprovalMatrix__c
                WHERE productName__c IN :productCodes AND Request_Type__c = 'Lighting'
            ]) {
                String productCode = matrix.productName__c == null
                    ? '' : matrix.productName__c.trim().toUpperCase();
                if (!existingLightingByProductCode.containsKey(productCode)) {
                    existingLightingByProductCode.put(
                        productCode,
                        new List<ApprovalMatrix__c>()
                    );
                }
                existingLightingByProductCode.get(productCode).add(matrix);
            }
        }
        if ((requestRecord.Record_Type__c == 'Power' ||
            (requestRecord.Record_Type__c == 'Lighting' &&
                requestRecord.From_ClickUp__c != true)) &&
            !productIds.isEmpty()) {
            for (Product_Approval_Hierarchy__c matrix : [
                SELECT Id, Product__c, Record_Type__c, Product_Category__c,
                    Sales_Discount__c, Discount_Percentage__c, Discount_Max__c,
                    Above_Policy_Discount_Percentage__c, Approval_Level__c,
                    Approval_Max__c, Approval_grt_max__c, Above_Policy_Level__c,
                    No_approval_value__c, RSM_Price_value__c, NSM_Price_Value__c
                FROM Product_Approval_Hierarchy__c
                WHERE Product__c IN :productIds AND Record_Type__c = :requestRecord.Record_Type__c
            ]) {
                existingCountByProductId.put(
                    matrix.Product__c,
                    existingCountByProductId.containsKey(matrix.Product__c)
                        ? existingCountByProductId.get(matrix.Product__c) + 1 : 1
                );
                if (!existingSummaryByProductId.containsKey(matrix.Product__c)) {
                    existingSummaryByProductId.put(matrix.Product__c, new List<String>());
                }
                existingSummaryByProductId.get(matrix.Product__c).add(
                    'Product Category=' + matrix.Product_Category__c +
                    ', Discount=' + matrix.Sales_Discount__c +
                    ', Discount %=' + matrix.Discount_Percentage__c +
                    ', Discount Max=' + matrix.Discount_Max__c +
                    ', Above Policy %=' + matrix.Above_Policy_Discount_Percentage__c +
                    ', Approval Level=' + matrix.Approval_Level__c +
                    ', Approval Max=' + matrix.Approval_Max__c +
                    ', Approval > Max=' + matrix.Approval_grt_max__c +
                    ', Above Policy Level=' + matrix.Above_Policy_Level__c +
                    ', No Approval=' + matrix.No_approval_value__c +
                    ', RSM=' + matrix.RSM_Price_value__c +
                    ', NSM=' + matrix.NSM_Price_Value__c
                );
            }
        }

        Boolean hasErrors = false;
        Integer errorCount = 0;
        for (Approval_Matrix_Request_Line__c line : lines) {
            if (line.Parse_Error__c == true || line.Line_Status__c == 'Inserted') {
                hasErrors = hasErrors || line.Line_Status__c == 'Error';
                if (line.Line_Status__c == 'Error') {
                    errorCount++;
                }
                continue;
            }
            line.Error_Message__c = null;
            line.Warnings__c = null;
            line.Existing_Matrix_Summary__c = null;
            line.Line_Status__c = 'Valid';
            List<Product2> matches = productsByLineId.get(line.Id);
            line.Matched_Product_Count__c = matches == null ? 0 : matches.size();
            Integer existingCount = 0;

            if (requestRecord.Record_Type__c == 'Lighting') {
                if (requestRecord.From_ClickUp__c == true &&
                    line.Product_Code__c != null &&
                    productCodeCountByValue.get(line.Product_Code__c.trim().toUpperCase()) > 1) {
                    setLineError(line, 'Each item code must appear only once in a Lighting request.');
                }
                Boolean hasRoleValues = line.GM__c != null || line.AGM__c != null ||
                    line.RM__c != null;
                if (hasRoleValues) {
                    if (line.GM__c == null || line.AGM__c == null || line.RM__c == null ||
                        line.GM__c <= 0 || line.AGM__c <= 0 || line.RM__c <= 0) {
                        setLineError(line, 'GM, AGM, and RM values must all be numeric and greater than zero.');
                    }
                } else if (line.Value_1__c == null || line.Value_2__c == null ||
                    line.Value_3__c == null || line.Value_1__c <= 0 ||
                    line.Value_2__c <= 0 || line.Value_3__c <= 0) {
                    setLineError(line, 'Lighting values must be numeric and greater than zero.');
                }
                if (matches == null || matches.size() != 1) {
                    setLineError(line, matches == null || matches.isEmpty()
                        ? 'No active Product2 matches this product code.'
                        : 'More than one active Product2 matches this product code.');
                } else {
                    if (requestRecord.From_ClickUp__c == true) {
                        String codeKey = line.Product_Code__c.trim().toUpperCase();
                        List<ApprovalMatrix__c> existingMatrices =
                            existingLightingByProductCode.get(codeKey);
                        existingCount = existingMatrices == null ? 0 : existingMatrices.size();
                        if (existingCount > 1) {
                            setLineError(
                                line,
                                'More than one Lighting ApprovalMatrix record matches this item code.'
                            );
                        }
                        if (existingMatrices != null && !existingMatrices.isEmpty()) {
                            List<String> summaries = new List<String>();
                            for (ApprovalMatrix__c matrix : existingMatrices) {
                                summaries.add(
                                    'GM=' + matrix.GM__c + ', AGM=' + matrix.AGM__c +
                                    ', RM=' + matrix.RM__c
                                );
                            }
                            line.Existing_Matrix_Summary__c = String.join(summaries, '\n');
                        }
                    } else {
                        existingCount = existingCountByProductId.containsKey(matches[0].Id)
                            ? existingCountByProductId.get(matches[0].Id) : 0;
                        line.Existing_Matrix_Summary__c = joinExistingMatrixSummaries(
                            new List<Id>{ matches[0].Id },
                            existingSummaryByProductId
                        );
                    }
                }
                if (!hasRoleValues && line.Line_Status__c != 'Error') {
                    List<Decimal> values = new List<Decimal>{
                        line.Value_1__c, line.Value_2__c, line.Value_3__c
                    };
                    values.sort();
                    if (values[0] != null && values[1] != null && values[2] != null) {
                        line.RM__c = values[0];
                        line.AGM__c = values[1];
                        line.GM__c = values[2];
                        line.Mapped_NSM_Price_Value__c = values[0];
                        line.Mapped_RSM_Price_Value__c = values[1];
                        line.Mapped_No_Approval_Value__c = values[2];
                        if (values[0] == values[1] || values[1] == values[2]) {
                            line.Warnings__c =
                                'Two or more values are tied; verify the role values before approval.';
                        }
                    }
                }
            } else if (requestRecord.Record_Type__c == 'Power') {
                if (String.isBlank(line.Product_Category__c)) {
                    setLineError(line, 'Product Category is required.');
                }
                if (line.Discount_Percentage__c > line.Discount_Max__c) {
                    setLineError(line, 'Discount Percentage must not exceed Discount Max.');
                }
                if (matches == null || matches.isEmpty()) {
                    setLineError(line, 'No active products match Division, Category, and Brand.');
                }
                for (Product2 product : matches == null ? new List<Product2>() : matches) {
                    if (String.isBlank(product.Product_Category__c)) {
                        setLineError(line, 'A matched product has no Product Category.');
                        break;
                    }
                    existingCount += existingCountByProductId.containsKey(product.Id)
                        ? existingCountByProductId.get(product.Id) : 0;
                }
                if (matches != null) {
                    List<Id> matchedIds = new List<Id>();
                    for (Product2 product : matches) {
                        matchedIds.add(product.Id);
                    }
                    line.Existing_Matrix_Summary__c = joinExistingMatrixSummaries(
                        matchedIds,
                        existingSummaryByProductId
                    );
                }
            } else {
                setLineError(line, 'Record Type must be Power or Lighting.');
            }
            line.Existing_Matrix_Count__c = existingCount;
            hasErrors = hasErrors || line.Line_Status__c == 'Error';
            if (line.Line_Status__c == 'Error') {
                errorCount++;
            }
        }
        update lines;
        update new Approval_Matrix_Request__c(
            Id = requestId,
            Status__c = hasErrors ? 'Validation Error' : 'Pending Verification',
            Error_Count__c = errorCount,
            Processing_Error__c = hasErrors ? 'One or more request lines need correction.' : null
        );
    }

    private static void setLineError(Approval_Matrix_Request_Line__c line, String message) {
        line.Line_Status__c = 'Error';
        line.Error_Message__c = String.isBlank(line.Error_Message__c)
            ? message : line.Error_Message__c + ' ' + message;
    }

    private static String joinExistingMatrixSummaries(
        List<Id> productIds,
        Map<Id, List<String>> summariesByProductId
    ) {
        List<String> summaries = new List<String>();
        for (Id productId : productIds) {
            if (summariesByProductId.containsKey(productId)) {
                for (String summary : summariesByProductId.get(productId)) {
                    summaries.add(String.valueOf(productId) + ': ' + summary);
                }
            }
        }
        String result = String.join(summaries, '\n');
        return result.length() > 32000 ? result.substring(0, 32000) : result;
    }

    public static void approve(Id requestId, Set<Id> selectedLineIds) {
        requireVerifierPermission();
        if (selectedLineIds == null || selectedLineIds.isEmpty()) {
            throw new ApprovalMatrixException('Select at least one valid line to approve.');
        }
        validateRequest(requestId);
        List<Approval_Matrix_Request_Line__c> selectedLines = [
            SELECT Id, Request__c, Line_Status__c, Product_Code__c, Division__c,
                Category__c, Brand__c, Product_Category__c, Value_1__c, Value_2__c,
                Value_3__c, Sales_Discount__c, Discount_Percentage__c, Discount_Max__c,
                Above_Policy_Discount_Percentage__c, Approval_Level__c, Approval_Max__c,
                Approval_grt_max__c, Above_Policy_Level__c, Inserted_Matrix_Ids__c,
                Mapped_No_Approval_Value__c, Mapped_RSM_Price_Value__c,
                Mapped_NSM_Price_Value__c, GM__c, AGM__c, RM__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestId AND Id IN :selectedLineIds
        ];
        if (selectedLines.size() != selectedLineIds.size()) {
            throw new ApprovalMatrixException('One or more selected lines do not belong to this request.');
        }
        List<Approval_Matrix_Request_Line__c> linesToMarkApproved =
            new List<Approval_Matrix_Request_Line__c>();
        for (Approval_Matrix_Request_Line__c line : selectedLines) {
            if (line.Line_Status__c != 'Valid') {
                throw new ApprovalMatrixException('Only valid, not-yet-inserted lines can be approved.');
            }
            linesToMarkApproved.add(new Approval_Matrix_Request_Line__c(
                Id = line.Id,
                Line_Status__c = 'Approved'
            ));
        }
        update linesToMarkApproved;
        update new Approval_Matrix_Request__c(
            Id = requestId,
            Status__c = 'Approved',
            Verified_By__c = UserInfo.getUserId(),
            Verified_On__c = System.now()
        );
        insertApprovedLines(requestId, selectedLines);
    }

    private static void insertApprovedLines(
        Id requestId,
        List<Approval_Matrix_Request_Line__c> lines
    ) {
        Approval_Matrix_Request__c requestRecord = [
            SELECT Id, Record_Type__c, From_ClickUp__c
            FROM Approval_Matrix_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        if (requestRecord.Record_Type__c == 'Lighting' &&
            requestRecord.From_ClickUp__c == true) {
            insertLightingApprovedLines(requestId, lines);
            return;
        }
        Map<Id, List<Product2>> productsByLineId = getProductsForLines(
            requestRecord.Record_Type__c,
            lines
        );
        List<Product_Approval_Hierarchy__c> targets =
            new List<Product_Approval_Hierarchy__c>();
        List<Id> targetLineIds = new List<Id>();
        for (Approval_Matrix_Request_Line__c line : lines) {
            for (Product2 product : productsByLineId.get(line.Id)) {
                Product_Approval_Hierarchy__c target =
                    new Product_Approval_Hierarchy__c(
                        Product__c = product.Id,
                        Product_Category__c = line.Product_Category__c,
                        Record_Type__c = requestRecord.Record_Type__c,
                        Source_Line_Key__c = String.valueOf(line.Id) + '-' + String.valueOf(product.Id)
                    );
                if (requestRecord.Record_Type__c == 'Lighting') {
                    target.No_approval_value__c = line.Mapped_No_Approval_Value__c;
                    target.RSM_Price_value__c = line.Mapped_RSM_Price_Value__c;
                    target.NSM_Price_Value__c = line.Mapped_NSM_Price_Value__c;
                } else {
                    target.Sales_Discount__c = line.Sales_Discount__c;
                    target.Discount_Percentage__c = line.Discount_Percentage__c;
                    target.Discount_Max__c = line.Discount_Max__c;
                    target.Above_Policy_Discount_Percentage__c =
                        line.Above_Policy_Discount_Percentage__c;
                    target.Approval_Level__c = line.Approval_Level__c;
                    target.Approval_Max__c = line.Approval_Max__c;
                    target.Approval_grt_max__c = line.Approval_grt_max__c;
                    target.Above_Policy_Level__c = line.Above_Policy_Level__c;
                }
                targets.add(target);
                targetLineIds.add(line.Id);
            }
        }

        Map<Id, List<String>> insertedIdsByLineId = new Map<Id, List<String>>();
        Map<Id, List<String>> failuresByLineId = new Map<Id, List<String>>();
        if (!targets.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(
                targets,
                Product_Approval_Hierarchy__c.Source_Line_Key__c,
                false
            );
            for (Integer index = 0; index < results.size(); index++) {
                Id lineId = targetLineIds[index];
                if (!insertedIdsByLineId.containsKey(lineId)) {
                    insertedIdsByLineId.put(lineId, new List<String>());
                }
                if (results[index].isSuccess()) {
                    insertedIdsByLineId.get(lineId).add(String.valueOf(results[index].getId()));
                } else {
                    if (!failuresByLineId.containsKey(lineId)) {
                        failuresByLineId.put(lineId, new List<String>());
                    }
                    for (Database.Error error : results[index].getErrors()) {
                        failuresByLineId.get(lineId).add(error.getMessage());
                    }
                }
            }
        }
        finishInsertion(
            requestId,
            lines,
            insertedIdsByLineId,
            failuresByLineId
        );
    }

    private static void insertLightingApprovedLines(
        Id requestId,
        List<Approval_Matrix_Request_Line__c> lines
    ) {
        Set<String> productCodes = new Set<String>();
        for (Approval_Matrix_Request_Line__c line : lines) {
            productCodes.add(line.Product_Code__c);
        }
        Map<String, List<Product2>> productsByCode = new Map<String, List<Product2>>();
        for (Product2 product : [
            SELECT Id, ProductCode
            FROM Product2
            WHERE IsActive = true AND ProductCode IN :productCodes
        ]) {
            String codeKey = product.ProductCode == null
                ? '' : product.ProductCode.trim().toUpperCase();
            if (!productsByCode.containsKey(codeKey)) {
                productsByCode.put(codeKey, new List<Product2>());
            }
            productsByCode.get(codeKey).add(product);
        }

        Map<String, List<ApprovalMatrix__c>> existingByCode =
            new Map<String, List<ApprovalMatrix__c>>();
        for (ApprovalMatrix__c matrix : [
            SELECT Id, Name, productName__c, Request_Type__c, ApprovalMatrix_Key__c
            FROM ApprovalMatrix__c
            WHERE productName__c IN :productCodes AND Request_Type__c = 'Lighting'
        ]) {
            String codeKey = matrix.productName__c == null
                ? '' : matrix.productName__c.trim().toUpperCase();
            if (!existingByCode.containsKey(codeKey)) {
                existingByCode.put(codeKey, new List<ApprovalMatrix__c>());
            }
            existingByCode.get(codeKey).add(matrix);
        }

        List<ApprovalMatrix__c> targets = new List<ApprovalMatrix__c>();
        List<Id> targetLineIds = new List<Id>();
        Map<Id, List<String>> insertedIdsByLineId = new Map<Id, List<String>>();
        Map<Id, List<String>> failuresByLineId = new Map<Id, List<String>>();
        for (Approval_Matrix_Request_Line__c line : lines) {
            String codeKey = line.Product_Code__c.trim().toUpperCase();
            List<Product2> matchedProducts = productsByCode.get(codeKey);
            if (matchedProducts == null || matchedProducts.size() != 1) {
                addInsertionFailure(
                    failuresByLineId,
                    line.Id,
                    'The active Product2 match changed after verification; reprocess the request.'
                );
                continue;
            }
            List<ApprovalMatrix__c> existingMatrices = existingByCode.get(codeKey);
            if (existingMatrices != null && existingMatrices.size() > 1) {
                addInsertionFailure(
                    failuresByLineId,
                    line.Id,
                    'More than one Lighting ApprovalMatrix record matches this item code.'
                );
                continue;
            }

            ApprovalMatrix__c target = new ApprovalMatrix__c(
                productName__c = matchedProducts[0].ProductCode,
                Request_Type__c = 'Lighting',
                GM__c = line.GM__c,
                AGM__c = line.AGM__c,
                RM__c = line.RM__c
            );
            if (existingMatrices != null && existingMatrices.size() == 1) {
                target.Id = existingMatrices[0].Id;
                target.Name = existingMatrices[0].Name;
                target.ApprovalMatrix_Key__c =
                    existingMatrices[0].ApprovalMatrix_Key__c;
                if (String.isBlank(target.ApprovalMatrix_Key__c)) {
                    target.ApprovalMatrix_Key__c =
                        lightingMatrixKey(matchedProducts[0].ProductCode);
                }
            } else {
                target.Name = buildLightingMatrixName(matchedProducts[0].ProductCode);
                target.ApprovalMatrix_Key__c =
                    lightingMatrixKey(matchedProducts[0].ProductCode);
            }
            targets.add(target);
            targetLineIds.add(line.Id);
        }

        if (!targets.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(
                targets,
                ApprovalMatrix__c.ApprovalMatrix_Key__c,
                false
            );
            for (Integer index = 0; index < results.size(); index++) {
                Id lineId = targetLineIds[index];
                if (results[index].isSuccess()) {
                    if (!insertedIdsByLineId.containsKey(lineId)) {
                        insertedIdsByLineId.put(lineId, new List<String>());
                    }
                    insertedIdsByLineId.get(lineId).add(
                        String.valueOf(results[index].getId())
                    );
                } else {
                    for (Database.Error error : results[index].getErrors()) {
                        addInsertionFailure(
                            failuresByLineId,
                            lineId,
                            error.getMessage()
                        );
                    }
                }
            }
        }
        finishInsertion(
            requestId,
            lines,
            insertedIdsByLineId,
            failuresByLineId
        );
    }

    private static void addInsertionFailure(
        Map<Id, List<String>> failuresByLineId,
        Id lineId,
        String message
    ) {
        if (!failuresByLineId.containsKey(lineId)) {
            failuresByLineId.put(lineId, new List<String>());
        }
        failuresByLineId.get(lineId).add(message);
    }

    private static void finishInsertion(
        Id requestId,
        List<Approval_Matrix_Request_Line__c> lines,
        Map<Id, List<String>> insertedIdsByLineId,
        Map<Id, List<String>> failuresByLineId
    ) {
        List<Approval_Matrix_Request_Line__c> lineUpdates =
            new List<Approval_Matrix_Request_Line__c>();
        for (Approval_Matrix_Request_Line__c line : lines) {
            List<String> insertedIds = insertedIdsByLineId.get(line.Id);
            List<String> failures = failuresByLineId.get(line.Id);
            lineUpdates.add(new Approval_Matrix_Request_Line__c(
                Id = line.Id,
                Inserted_Matrix_Ids__c = insertedIds == null
                    ? null : String.join(insertedIds, ','),
                Line_Status__c = failures == null ? 'Inserted' : 'Error',
                Error_Message__c = failures == null
                    ? null : String.join(failures, ' ')
            ));
        }
        update lineUpdates;

        List<Approval_Matrix_Request_Line__c> allLines = [
            SELECT Line_Status__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestId
        ];
        Boolean hasErrors = false;
        Boolean hasUnprocessed = false;
        Integer errorCount = 0;
        for (Approval_Matrix_Request_Line__c line : allLines) {
            hasErrors = hasErrors || line.Line_Status__c == 'Error';
            hasUnprocessed = hasUnprocessed || line.Line_Status__c == 'Valid';
            if (line.Line_Status__c == 'Error') {
                errorCount++;
            }
        }
        update new Approval_Matrix_Request__c(
            Id = requestId,
            Status__c = hasErrors ? 'Error' :
                (hasUnprocessed ? 'Pending Verification' : 'Inserted'),
            Error_Count__c = errorCount
        );
    }

    private static String lightingMatrixKey(String productCode) {
        String keyInput = JSON.serialize(
            new List<String>{ 'lighting', productCode.trim().toUpperCase() }
        );
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(keyInput))
        );
    }

    private static String buildLightingMatrixName(String productCode) {
        String name = 'Lighting - ' + productCode;
        return name.length() > 80 ? name.substring(0, 80) : name;
    }

    private static Map<Id, List<Product2>> getProductsForLines(
        String recordType,
        List<Approval_Matrix_Request_Line__c> lines
    ) {
        Map<Id, List<Product2>> result = new Map<Id, List<Product2>>();
        Set<String> productCodes = new Set<String>();
        Set<String> divisions = new Set<String>();
        Set<String> categories = new Set<String>();
        Set<String> brands = new Set<String>();
        for (Approval_Matrix_Request_Line__c line : lines) {
            if (recordType == 'Lighting') {
                productCodes.add(line.Product_Code__c);
            } else {
                divisions.add(line.Division__c);
                categories.add(line.Category__c);
                brands.add(line.Brand__c);
            }
        }
        List<Product2> products;
        if (recordType == 'Lighting') {
            products = [
                SELECT Id, ProductCode, Product_Category__c
                FROM Product2
                WHERE IsActive = true AND ProductCode IN :productCodes
            ];
        } else {
            products = [
                SELECT Id, ProductCode, Division__c, Category__c, Brand__c, Product_Category__c
                FROM Product2
                WHERE IsActive = true
                    AND Division__c IN :divisions
                    AND Category__c IN :categories
                    AND Brand__c IN :brands
                    AND Product_Category__c != null
            ];
        }
        for (Approval_Matrix_Request_Line__c line : lines) {
            List<Product2> matches = new List<Product2>();
            for (Product2 product : products) {
                Boolean matched = recordType == 'Lighting'
                    ? product.ProductCode == line.Product_Code__c
                    : product.Division__c == line.Division__c &&
                        product.Category__c == line.Category__c &&
                        product.Brand__c == line.Brand__c &&
                        String.isNotBlank(product.Product_Category__c);
                if (matched) {
                    matches.add(product);
                }
            }
            result.put(line.Id, matches);
        }
        return result;
    }

    public static void reject(Id requestId, String reason) {
        requireVerifierPermission();
        if (String.isBlank(reason)) {
            throw new ApprovalMatrixException('A rejection reason is required.');
        }
        update new Approval_Matrix_Request__c(
            Id = requestId,
            Status__c = 'Rejected',
            Rejection_Reason__c = reason.trim(),
            Verified_By__c = UserInfo.getUserId(),
            Verified_On__c = System.now()
        );
    }

    private static void requireVerifierPermission() {
        if (!FeatureManagement.checkPermission('Approve_Approval_Matrix_Request')) {
            throw new ApprovalMatrixException(
                'You are not authorized to verify approval matrix requests.'
            );
        }
    }

    public class ApprovalMatrixException extends Exception {}
}
