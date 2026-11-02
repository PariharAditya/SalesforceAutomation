public with sharing class ParseTextFrom {
    public class Request {
        @InvocableVariable(required=true)
        public Id contentVersionId;
    }

    public class Output {
        @InvocableVariable
        public Boolean isValid;

        @InvocableVariable
        public Boolean isSaved;

        @InvocableVariable
        public Id approvalMatrixId;

        @InvocableVariable
        public String errorMessage;

        @InvocableVariable
        public String rawText;

        @InvocableVariable
        public String requestType;

        @InvocableVariable
        public String division;

        @InvocableVariable
        public String category;

        @InvocableVariable
        public String brand;

        @InvocableVariable
        public String productCategory;

        @InvocableVariable
        public Decimal salesDiscount;

        @InvocableVariable
        public Decimal discountPercentage;

        @InvocableVariable
        public Decimal discountMax;

        @InvocableVariable
        public Decimal abovePolicyDiscountPercentage;

        @InvocableVariable
        public String approvalLevel;

        @InvocableVariable
        public Decimal approvalMax;

        @InvocableVariable
        public String approvalGreaterThanMax;

        @InvocableVariable
        public String abovePolicyLevel;

        @InvocableVariable
        public Decimal gm;

        @InvocableVariable
        public Decimal agm;

        @InvocableVariable
        public Decimal rm;
    }

    @InvocableMethod(label='Parse Approval Matrix TXT' description='Reads and validates an uploaded .txt request.')
    public static List<Output> parseUploadedFiles(List<Request> requests) {
        Set<Id> contentVersionIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.contentVersionId != null) {
                contentVersionIds.add(request.contentVersionId);
            }
        }

        Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>();
        if (!contentVersionIds.isEmpty()) {
            versionsById = new Map<Id, ContentVersion>([
                SELECT Id, FileExtension, PathOnClient, VersionData
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
            ]);
        }

        List<Output> outputs = new List<Output>();
        for (Request request : requests) {
            if (request == null || request.contentVersionId == null) {
                outputs.add(invalidOutput('A ContentVersion ID is required.'));
                continue;
            }

            ContentVersion version = versionsById.get(request.contentVersionId);
            if (version == null) {
                outputs.add(invalidOutput('The uploaded file could not be found.'));
                continue;
            }

            String extension = version.FileExtension;
            if (String.isBlank(extension) && String.isNotBlank(version.PathOnClient)) {
                Integer dotPosition = version.PathOnClient.lastIndexOf('.');
                if (dotPosition >= 0) {
                    extension = version.PathOnClient.substring(dotPosition + 1);
                }
            }
            if (extension == null || !extension.equalsIgnoreCase('txt')) {
                outputs.add(invalidOutput('Only .txt files are supported.'));
                continue;
            }

            String rawText;
            try {
                rawText = version.VersionData.toString();
            } catch (StringException e) {
                outputs.add(invalidOutput('The TXT file must contain valid UTF-8 text.'));
                continue;
            }

            ParseApprovalMatrix.ParsedRequest parsed = ParseApprovalMatrix.parse(rawText);
            Output output = copyResult(parsed);
            if (parsed.isValid) {
                persist(parsed, output);
            }
            outputs.add(output);
        }
        return outputs;
    }

    private static void persist(ParseApprovalMatrix.ParsedRequest parsed, Output output) {
        String role = parsed.requestType == 'Power' ? parsed.approvalLevel : 'GM';
        Decimal discount = parsed.requestType == 'Power' ? parsed.salesDiscount : parsed.gm;
        String keyInput = JSON.serialize(
            new List<String>{
                parsed.productCategory.trim().toLowerCase(),
                role.trim().toLowerCase(),
                String.valueOf(discount)
            }
        );

        ApprovalMatrix__c recordToSave = new ApprovalMatrix__c(
            Name = buildRecordName(parsed.productCategory, role, discount),
            productName__c = parsed.productCategory,
            role__c = role,
            Discount__c = discount,
            ApprovalMatrix_Key__c = EncodingUtil.convertToHex(
                Crypto.generateDigest('SHA-256', Blob.valueOf(keyInput))
            ),
            Request_Type__c = parsed.requestType,
            Division__c = parsed.division,
            Category__c = parsed.category,
            Brand__c = parsed.brand,
            Discount_Percentage__c = parsed.discountPercentage,
            Discount_Max__c = parsed.discountMax,
            Above_Policy_Discount_Percentage__c = parsed.abovePolicyDiscountPercentage,
            Approval_Max__c = parsed.approvalMax,
            Approval_Greater_Than_Max__c = parsed.approvalGreaterThanMax,
            Above_Policy_Level__c = parsed.abovePolicyLevel,
            GM__c = parsed.gm,
            AGM__c = parsed.agm,
            RM__c = parsed.rm
        );

        if (!Schema.sObjectType.ApprovalMatrix__c.isCreateable() ||
            !Schema.sObjectType.ApprovalMatrix__c.isUpdateable()) {
            output.errorMessage =
                'The current user needs create and update access to ApprovalMatrix__c.';
            return;
        }

        SObjectAccessDecision accessDecision = Security.stripInaccessible(
            AccessType.UPSERTABLE,
            new List<SObject>{ recordToSave }
        );
        if (!accessDecision.getRemovedFields().isEmpty()) {
            output.errorMessage =
                'The current user needs edit access to all ApprovalMatrix fields used by this flow.';
            return;
        }

        ApprovalMatrix__c accessibleRecord = (ApprovalMatrix__c) accessDecision.getRecords()[0];
        Database.UpsertResult saveResult = Database.upsert(
            accessibleRecord,
            ApprovalMatrix__c.ApprovalMatrix_Key__c,
            false
        );
        if (saveResult.isSuccess()) {
            output.isSaved = true;
            output.approvalMatrixId = saveResult.getId();
            return;
        }

        output.errorMessage = 'Could not save the ApprovalMatrix record: ' +
            saveResult.getErrors()[0].getMessage();
    }

    private static String buildRecordName(String productCategory, String role, Decimal discount) {
        String name = productCategory + ' - ' + role + ' - ' + String.valueOf(discount);
        return name.length() > 80 ? name.substring(0, 80) : name;
    }

    private static Output invalidOutput(String message) {
        Output output = new Output();
        output.isValid = false;
        output.isSaved = false;
        output.errorMessage = message;
        return output;
    }

    private static Output copyResult(ParseApprovalMatrix.ParsedRequest parsed) {
        Output output = new Output();
        output.isValid = parsed.isValid;
        output.isSaved = false;
        output.errorMessage = parsed.errorMessage;
        output.rawText = parsed.rawText;
        output.requestType = parsed.requestType;
        output.division = parsed.division;
        output.category = parsed.category;
        output.brand = parsed.brand;
        output.productCategory = parsed.productCategory;
        output.salesDiscount = parsed.salesDiscount;
        output.discountPercentage = parsed.discountPercentage;
        output.discountMax = parsed.discountMax;
        output.abovePolicyDiscountPercentage = parsed.abovePolicyDiscountPercentage;
        output.approvalLevel = parsed.approvalLevel;
        output.approvalMax = parsed.approvalMax;
        output.approvalGreaterThanMax = parsed.approvalGreaterThanMax;
        output.abovePolicyLevel = parsed.abovePolicyLevel;
        output.gm = parsed.gm;
        output.agm = parsed.agm;
        output.rm = parsed.rm;
        return output;
    }
}