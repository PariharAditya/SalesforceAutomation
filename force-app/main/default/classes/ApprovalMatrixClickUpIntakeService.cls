public without sharing class ApprovalMatrixClickUpIntakeService {
    private class TableRow {
        String raw;
        List<String> cells;
        Integer rowNumber;

        TableRow(String raw, List<String> cells, Integer rowNumber) {
            this.raw = raw;
            this.cells = cells;
            this.rowNumber = rowNumber;
        }
    }

    public static void processTask(
        Id requestId,
        String taskId,
        String lastModified,
        String description,
        String taskUrl
    ) {
        Approval_Matrix_Request__c requestRecord = [
            SELECT Id, ClickUp_Task_Id__c, ClickUp_Last_Modified__c,
                Status__c, Record_Type__c, From_ClickUp__c
            FROM Approval_Matrix_Request__c
            WHERE Id = :requestId
            FOR UPDATE
        ];
        if (requestRecord.ClickUp_Task_Id__c != taskId ||
            requestRecord.ClickUp_Last_Modified__c == lastModified) {
            return;
        }
        if (new Set<String>{ 'Approved', 'Inserted', 'Rejected' }.contains(
            requestRecord.Status__c
        )) {
            return;
        }

        List<Approval_Matrix_Request_Line__c> previousLines = [
            SELECT Id, Inserted_Matrix_Ids__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestId
        ];
        for (Approval_Matrix_Request_Line__c line : previousLines) {
            if (String.isNotBlank(line.Inserted_Matrix_Ids__c)) {
                failRequest(
                    requestId,
                    'A ClickUp update arrived after a matrix write began. Create a new ClickUp task for replacement values.'
                );
                return;
            }
        }
        if (!previousLines.isEmpty()) {
            delete previousLines;
        }

        List<Approval_Matrix_Request_Line__c> lines =
            parseLightingTable(requestId, description);
        requestRecord.Record_Type__c = 'Lighting';
        requestRecord.From_ClickUp__c = true;
        requestRecord.Status__c = 'Parsed';
        requestRecord.Processing_Error__c = null;
        requestRecord.ClickUp_Task_Url__c = taskUrl;
        requestRecord.ClickUp_Last_Modified__c = lastModified;
        update requestRecord;
        insert lines;
        ApprovalMatrixTxtService.validateRequest(requestId);
    }

    private static List<Approval_Matrix_Request_Line__c> parseLightingTable(
        Id requestId,
        String description
    ) {
        List<Approval_Matrix_Request_Line__c> lines =
            new List<Approval_Matrix_Request_Line__c>();
        if (String.isBlank(description)) {
            lines.add(parseFailure(
                requestId,
                '',
                'The ClickUp task description is empty.'
            ));
            return lines;
        }

        Boolean foundHeader = false;
        Boolean foundData = false;
        Integer rowNumber = 0;
        List<String> sourceLines = description.replace('\r\n', '\n')
            .replace('\r', '\n').split('\n');
        for (String sourceLine : sourceLines) {
            rowNumber++;
            String raw = sourceLine.trim();
            if (!raw.contains('|')) {
                continue;
            }
            List<String> cells = splitTableRow(raw);
            if (!foundHeader) {
                if (isLightingHeader(cells)) {
                    foundHeader = true;
                }
                continue;
            }
            if (isMarkdownSeparator(cells)) {
                continue;
            }
            if (isLightingHeader(cells)) {
                lines.add(parseFailure(
                    requestId,
                    raw,
                    'Multiple Lighting tables were found; keep one Item/GM/AGM/RM table per task.'
                ));
                continue;
            }
            foundData = true;
            lines.add(parseLightingRow(requestId, new TableRow(raw, cells, rowNumber)));
        }

        if (!foundHeader) {
            lines.add(parseFailure(
                requestId,
                description,
                'Could not find a table with the headers Item, GM, AGM, and RM.'
            ));
        } else if (!foundData) {
            lines.add(parseFailure(
                requestId,
                '',
                'The ClickUp task contains the Lighting table header but no product rows.'
            ));
        }
        return lines;
    }

    private static Approval_Matrix_Request_Line__c parseLightingRow(
        Id requestId,
        TableRow row
    ) {
        Approval_Matrix_Request_Line__c line =
            new Approval_Matrix_Request_Line__c(
                Request__c = requestId,
                Raw_Input__c = row.raw,
                Line_Status__c = 'Valid'
            );
        if (row.cells.size() != 4) {
            return parseFailure(
                requestId,
                row.raw,
                'Row ' + row.rowNumber + ': expected 4 table columns, found ' +
                row.cells.size() + '.'
            );
        }

        line.Product_Code__c = stripCellFormatting(row.cells[0]);
        line.GM__c = parseNumber(row.cells[1]);
        line.AGM__c = parseNumber(row.cells[2]);
        line.RM__c = parseNumber(row.cells[3]);
        if (String.isBlank(line.Product_Code__c) || line.GM__c == null ||
            line.AGM__c == null || line.RM__c == null) {
            line.Line_Status__c = 'Error';
            line.Parse_Error__c = true;
            line.Error_Message__c =
                'Row ' + row.rowNumber +
                ': Item, GM, AGM, and RM are required; GM, AGM, and RM must be numeric.';
        }
        return line;
    }

    private static Approval_Matrix_Request_Line__c parseFailure(
        Id requestId,
        String raw,
        String message
    ) {
        String safeRaw = raw == null ? '' : raw;
        if (safeRaw.length() > 32768) {
            safeRaw = safeRaw.substring(0, 32768);
        }
        return new Approval_Matrix_Request_Line__c(
            Request__c = requestId,
            Raw_Input__c = safeRaw,
            Line_Status__c = 'Error',
            Parse_Error__c = true,
            Error_Message__c = message
        );
    }

    private static List<String> splitTableRow(String row) {
        String content = row.trim();
        if (content.startsWith('|')) {
            content = content.substring(1);
        }
        if (content.endsWith('|')) {
            content = content.substring(0, content.length() - 1);
        }
        List<String> cells = content.split('\\|', -1);
        for (Integer index = 0; index < cells.size(); index++) {
            cells[index] = stripCellFormatting(cells[index]);
        }
        return cells;
    }

    private static String stripCellFormatting(String cell) {
        return cell == null
            ? null
            : cell.trim().replace('**', '').replace('__', '').replace('`', '');
    }

    private static Boolean isLightingHeader(List<String> cells) {
        return cells.size() == 4 &&
            cells[0].equalsIgnoreCase('Item') &&
            cells[1].equalsIgnoreCase('GM') &&
            cells[2].equalsIgnoreCase('AGM') &&
            cells[3].equalsIgnoreCase('RM');
    }

    private static Boolean isMarkdownSeparator(List<String> cells) {
        if (cells.isEmpty()) {
            return false;
        }
        Pattern separatorPattern = Pattern.compile(':?-{3,}:?');
        for (String cell : cells) {
            if (!separatorPattern.matcher(cell).matches()) {
                return false;
            }
        }
        return true;
    }

    private static Decimal parseNumber(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Decimal.valueOf(value.replace(',', '').trim());
        } catch (TypeException invalidNumber) {
            return null;
        }
    }

    public static void failRequest(Id requestId, String message) {
        update new Approval_Matrix_Request__c(
            Id = requestId,
            Status__c = 'Error',
            Processing_Error__c = message
        );
    }
}