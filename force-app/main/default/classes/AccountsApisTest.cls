@IsTest
private class AccountsApisTest {
    @TestSetup
    static void setupData() {
        insert new Account(Name = 'Acme Co', Industry = 'Technology', Phone = '1234567890', BillingCity = 'Pune');
    }

    @IsTest
    static void testGetAllAccounts() {
        // Prepare REST GET to /accounts/getAll
        RestRequest req = new RestRequest();
        req.httpMethod = 'GET';
        req.requestUri = '/services/apexrest/accounts/getAll';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        List<Account> accts = AccountsApis.getAllAccounts();
        Test.stopTest();

        System.assertNotEquals(0, accts.size(), 'getAllAccounts should return at least the setup Account');
        // Validate key fields are accessible
        Account a = accts[0];
        System.assertNotEquals(null, a.Id, 'Returned Account should have Id populated');
        System.assertNotEquals(null, a.Name, 'Returned Account should have Name populated');
    }

    @IsTest
    static void testCreateAccount_Success() {
        Test.startTest();
        String newId = AccountsApis.createAccount('New Name', 'Banking', '9876543210');
        Test.stopTest();

        System.assertNotEquals(null, newId, 'createAccount should return a new Id');
        Account created = [SELECT Id, Name, Industry, Phone FROM Account WHERE Id = :newId];
        System.assertEquals('New Name', created.Name);
        System.assertEquals('Banking', created.Industry);
        System.assertEquals('9876543210', created.Phone);
    }

    @IsTest
    static void testCreateAccount_MissingName() {
        try {
            Test.startTest();
            AccountsApis.createAccount(null, 'Tech', '111');
            Test.stopTest();
            System.assert(false, 'Expected exception for missing name');
        } catch (AccountsApis.AccountAPIException e) {
            System.assert(e.getMessage().contains('Account name is required'));
        }
    }

    @IsTest
    static void testUpdateAccount_Success() {
        Account existing = [SELECT Id, Name, Industry, Phone FROM Account LIMIT 1];

        Test.startTest();
        String result = AccountsApis.updateAccount(existing.Id, 'Updated Name', 'Energy', '555');
        Test.stopTest();

        System.assertEquals('Account updated successfully', result);
        Account updated = [SELECT Id, Name, Industry, Phone FROM Account WHERE Id = :existing.Id];
        System.assertEquals('Updated Name', updated.Name);
        System.assertEquals('Energy', updated.Industry);
        System.assertEquals('555', updated.Phone);
    }

    @IsTest
    static void testUpdateAccount_NotFound() {
        try {
            Test.startTest();
            AccountsApis.updateAccount('001000000000000AAA', 'N', null, null);
            Test.stopTest();
            System.assert(false, 'Expected not found exception');
        } catch (AccountsApis.AccountAPIException e) {
            System.assert(e.getMessage().contains('Account not found'));
        }
    }

    @IsTest
    static void testDeleteAccount_Success() {
        Account a = new Account(Name = 'ToDelete');
        insert a;

        // Prepare REST DELETE /accounts?accountId=...
        RestRequest req = new RestRequest();
        req.httpMethod = 'DELETE';
        req.requestUri = '/services/apexrest/accounts?accountId=' + a.Id;
        req.addParameter('accountId', a.Id);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        String msg = AccountsApis.deleteAccount();
        Test.stopTest();

        System.assertEquals('Account deleted successfully', msg);
        Integer countAfter = [SELECT COUNT() FROM Account WHERE Id = :a.Id];
        System.assertEquals(0, countAfter, 'Account should be deleted');
    }

    @IsTest
    static void testDeleteAccount_NotFound() {
        // Prepare REST DELETE with bogus Id
        RestRequest req = new RestRequest();
        req.httpMethod = 'DELETE';
        req.requestUri = '/services/apexrest/accounts?accountId=001000000000000AAA';
        req.addParameter('accountId', '001000000000000AAA');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        try {
            Test.startTest();
            AccountsApis.deleteAccount();
            Test.stopTest();
            System.assert(false, 'Expected not found exception');
        } catch (AccountsApis.AccountAPIException e) {
            System.assert(e.getMessage().contains('Account not found'));
        }
    }
}