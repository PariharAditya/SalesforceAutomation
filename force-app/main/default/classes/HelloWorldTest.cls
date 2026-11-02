@IsTest
private class HelloWorldTest {
    @TestSetup
    static void setupData() {
        // No data required for HelloWorld REST class
    }

    @IsTest
    static void testSayHello() {
        // Simulate a REST GET call
        RestRequest req = new RestRequest();
        req.httpMethod = 'GET';
        req.requestUri = '/services/apexrest/HelloWorld/';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        String result = HelloWorld.sayHello();
        Test.stopTest();

        System.assertEquals('Hello, SalesForce!', result, 'HelloWorld.sayHello should return expected greeting');
    }
}