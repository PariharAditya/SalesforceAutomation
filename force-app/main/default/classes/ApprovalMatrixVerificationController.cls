public with sharing class ApprovalMatrixVerificationController {
    public class RequestView {
        @AuraEnabled public Approval_Matrix_Request__c requestRecord;
        @AuraEnabled public List<Approval_Matrix_Request_Line__c> lines;
    }

    @AuraEnabled(cacheable=true)
    public static List<Approval_Matrix_Request__c> getRequests() {
        return [
            SELECT Id, Name, ClickUp_Task_Id__c, Record_Type__c, Status__c,
                Line_Count__c, Error_Count__c, Processing_Error__c, CreatedDate
            FROM Approval_Matrix_Request__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static RequestView getRequest(Id requestId) {
        if (requestId == null) {
            throw new AuraHandledException('A request record is required.');
        }
        RequestView result = new RequestView();
        result.requestRecord = [
            SELECT Id, Name, ClickUp_Task_Id__c, Record_Type__c, Status__c,
                Source_File_Id__c, Line_Count__c, Error_Count__c, Verified_By__c,
                Verified_On__c, Rejection_Reason__c, Processing_Error__c
            FROM Approval_Matrix_Request__c
            WHERE Id = :requestId
            WITH USER_MODE
            LIMIT 1
        ];
        result.lines = [
            SELECT Id, Name, Product_Code__c, Division__c, Category__c, Brand__c,
                Product_Category__c, Raw_Input__c, Value_1__c, Value_2__c, Value_3__c,
                Sales_Discount__c, Discount_Percentage__c, Discount_Max__c,
                Above_Policy_Discount_Percentage__c, Approval_Level__c, Approval_Max__c,
                Approval_grt_max__c, Above_Policy_Level__c, Mapped_No_Approval_Value__c,
                Mapped_RSM_Price_Value__c, Mapped_NSM_Price_Value__c,
                Matched_Product_Count__c, Existing_Matrix_Count__c,
                Existing_Matrix_Summary__c, Line_Status__c, Error_Message__c,
                Warnings__c, Inserted_Matrix_Ids__c
            FROM Approval_Matrix_Request_Line__c
            WHERE Request__c = :requestId
            WITH USER_MODE
            ORDER BY CreatedDate, Id
        ];
        return result;
    }

    @AuraEnabled
    public static void approveSelected(Id requestId, List<Id> selectedLineIds) {
        requireVerifier();
        validateRequestState(requestId);
        if (selectedLineIds == null) {
            throw new AuraHandledException('Select at least one valid line to approve.');
        }
        try {
            ApprovalMatrixTxtService.approve(requestId, new Set<Id>(selectedLineIds));
        } catch (ApprovalMatrixTxtService.ApprovalMatrixException approvalError) {
            throw new AuraHandledException(approvalError.getMessage());
        }
    }

    @AuraEnabled
    public static void rejectRequest(Id requestId, String reason) {
        requireVerifier();
        validateRequestState(requestId);
        try {
            ApprovalMatrixTxtService.reject(requestId, reason);
        } catch (ApprovalMatrixTxtService.ApprovalMatrixException approvalError) {
            throw new AuraHandledException(approvalError.getMessage());
        }
    }

    private static void requireVerifier() {
        if (!FeatureManagement.checkPermission('Approve_Approval_Matrix_Request')) {
            throw new AuraHandledException('You are not authorized to verify approval matrix requests.');
        }
    }

    private static void validateRequestState(Id requestId) {
        if (requestId == null) {
            throw new AuraHandledException('A request record is required.');
        }
        Approval_Matrix_Request__c requestRecord = [
            SELECT Status__c
            FROM Approval_Matrix_Request__c
            WHERE Id = :requestId
            WITH USER_MODE
            LIMIT 1
        ];
        if (requestRecord.Status__c != 'Pending Verification' &&
            requestRecord.Status__c != 'Validation Error' &&
            requestRecord.Status__c != 'Error') {
            throw new AuraHandledException('This request is not open for verification.');
        }
    }
}
