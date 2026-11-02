@RestResource(urlMapping='/accounts/*')
global with sharing class AccountsApis {
    
    // GET: Retrieve account by ID
    // URL: /services/apexrest/accounts/getById?accountId=001xx000003DGb2AAG
    // @HttpGet(urlMapping='/getById')
    // global static Account getAccount() {
    //     RestRequest req = RestContext.request;
    //     String accountId = req.params.get('accountId');
        
    //     if (String.isBlank(accountId)) {
    //         // Return an HTTP 400 Bad Request instead of throwing an Apex exception
    //         RestContext.response.statusCode = 400;
    //         RestContext.response.responseBody = Blob.valueOf('{"error":"accountId is required"}');
    //         return null;
    //     }
        
    //     try {
    //         Account acc = [
    //             SELECT Id, Name, Industry, Phone, BillingCity 
    //             FROM Account 
    //             WHERE Id = :accountId 
    //             LIMIT 1
    //         ];
    //         return acc;
    //     } catch (QueryException e) {
    //         RestContext.response.statusCode = 404;
    //         RestContext.response.responseBody = Blob.valueOf('{"error":"Account not found"}');
    //         return null;
    //     }
    // }


    // GET: Retrieve all accounts
    // URL: /services/apexrest/accounts/getAll
    @HttpGet(urlMapping='/getAll')
    global static List<Account> getAllAccounts() {
        // Use WITH SECURITY_ENFORCED to honor FLS in user context
        return [
            SELECT Id, Name, Industry, Phone, BillingCity 
            FROM Account 
            WITH SECURITY_ENFORCED
        ];
    }
    
    // POST: Create new account
    // URL: /services/apexrest/accounts
    @HttpPost
    global static String createAccount(String name, String industry, String phone) {
        if (String.isBlank(name)) {
            throw new AccountAPIException('Account name is required');
        }
        
        Account newAccount = new Account(
            Name = name,
            Industry = industry,
            Phone = phone
        );
        
        try {
            insert newAccount;
            return newAccount.Id;
        } catch (DmlException e) {
            throw new AccountAPIException('Failed to create account: ' + e.getMessage());
        }
    }
    
    // PUT: Update existing account
    // URL: /services/apexrest/accounts
    @HttpPut
    global static String updateAccount(String accountId, String name, String industry, String phone) {
        if (String.isBlank(accountId)) {
            throw new AccountAPIException('Account ID is required');
        }
        
        try {
            Account acc = [SELECT Id FROM Account WHERE Id = :accountId LIMIT 1];
            
            if (String.isNotBlank(name)) acc.Name = name;
            if (String.isNotBlank(industry)) acc.Industry = industry;
            if (String.isNotBlank(phone)) acc.Phone = phone;
            
            update acc;
            return 'Account updated successfully';
        } catch (QueryException e) {
            throw new AccountAPIException('Account not found');
        } catch (DmlException e) {
            throw new AccountAPIException('Failed to update account: ' + e.getMessage());
        }
    }
    
    // DELETE: Delete account
    // URL: /services/apexrest/accounts?accountId=001xx000003DGb2AAG
    @HttpDelete
    global static String deleteAccount() {
        RestRequest req = RestContext.request;
        String accountId = req.params.get('accountId');
        
        if (String.isBlank(accountId)) {
            throw new AccountAPIException('Account ID is required');
        }
        
        try {
            Account acc = [SELECT Id FROM Account WHERE Id = :accountId LIMIT 1];
            delete acc;
            return 'Account deleted successfully';
        } catch (QueryException e) {
            throw new AccountAPIException('Account not found');
        } catch (DmlException e) {
            throw new AccountAPIException('Failed to delete account: ' + e.getMessage());
        }
    }

    public class AccountAPIException extends Exception {}
}