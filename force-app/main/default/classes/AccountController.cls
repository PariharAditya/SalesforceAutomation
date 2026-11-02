public with sharing class AccountController {
    
    // Method to get all accounts
    @AuraEnabled(cacheable=true)
    public static List<Account> getAccounts() {
        return [
            SELECT Id, Name, Industry, Phone, Description, BillingCity, Site 
            FROM Account 
            ORDER BY Name
        ];
    }
    
    // Method to get single account
    @AuraEnabled(cacheable=true)
    public static Account getAccount(Id accountId) {
        return [
            SELECT Id, Name, Industry, Phone, Description, BillingCity, BillingState, Website, Site
            FROM Account 
            WHERE Id = :accountId 
            LIMIT 1
        ];
    }
    
    // Method to create account
    @AuraEnabled()
    public static String createAccount(String name, String industry, String phone, String description, String site) {
        try {
            Account newAccount = new Account(
                Name = name,
                Industry = industry,
                Phone = phone,
                Description = description,
                Site = site
            );
            insert newAccount;
            return newAccount.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // Method to update account
    @AuraEnabled
    public static void updateAccount(Id accountId, String name, String industry, String phone, String description, String site) {
        try {
            Account acc = [SELECT Id FROM Account WHERE Id = :accountId];
            acc.Name = name;
            acc.Industry = industry;
            acc.Phone = phone;
            acc.Description = description;
            acc.Site = site;
            update acc;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // Method to delete account
    @AuraEnabled
    public static void deleteAccount(Id accountId) {
        try {
            Account acc = [SELECT Id FROM Account WHERE Id = :accountId];
            delete acc;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}