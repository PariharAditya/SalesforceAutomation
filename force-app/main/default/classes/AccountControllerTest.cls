@IsTest
private class AccountControllerTest {
    @TestSetup
    static void setupData() {
        insert new Account(Name = 'Seed Acc', Industry = 'Tech', Phone = '111', BillingCity = 'Pune', BillingState = 'MH', Website = 'https://example.com');
    }

    @IsTest
    static void testGetAccounts() {
        Test.startTest();
        List<Account> accts = AccountController.getAccounts();
        Test.stopTest();

        System.assert(accts.size() > 0, 'getAccounts should return at least one Account');
        System.assertNotEquals(null, accts[0].Id, 'Returned account should have Id');
        System.assertNotEquals(null, accts[0].Name, 'Returned account should have Name');
    }

    @IsTest
    static void testGetAccount_ById() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Account got = AccountController.getAccount(a.Id);
        Test.stopTest();

        System.assertEquals(a.Id, got.Id, 'getAccount should return the requested account');
    }

    @IsTest
    static void testCreateAccount_Success() {
        Test.startTest();
        String newId = AccountController.createAccount('Created Via Controller', 'Energy', '222', 'Desc from test', 'https://example.com');
        Test.stopTest();

        System.assertNotEquals(null, newId, 'createAccount should return Id');
        Account created = [SELECT Id, Name, Industry, Phone, Description, Site FROM Account WHERE Id = :newId];
        System.assertEquals('Created Via Controller', created.Name);
        System.assertEquals('Energy', created.Industry);
        System.assertEquals('222', created.Phone);
        System.assertEquals('Desc from test', created.Description);
        System.assertEquals('https://example.com', created.Site);
    }

    @IsTest
    static void testUpdateAccount_Success() {
        Account existing = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        AccountController.updateAccount(existing.Id, 'Updated Cntrl', 'Banking', '333', 'Updated description', 'https://updated.com');
        Test.stopTest();

        Account updated = [SELECT Id, Name, Industry, Phone, Description, Site FROM Account WHERE Id = :existing.Id];
        System.assertEquals('Updated Cntrl', updated.Name);
        System.assertEquals('Banking', updated.Industry);
        System.assertEquals('333', updated.Phone);
        System.assertEquals('Updated description', updated.Description);
        System.assertEquals('https://updated.com', updated.Site);
    }

    @IsTest
    static void testDeleteAccount_Success() {
        Account a = new Account(Name = 'To Delete Controller');
        insert a;

        Test.startTest();
        AccountController.deleteAccount(a.Id);
        Test.stopTest();

        Integer countAfter = [SELECT COUNT() FROM Account WHERE Id = :a.Id];
        System.assertEquals(0, countAfter, 'Account should be deleted by controller');
    }
}