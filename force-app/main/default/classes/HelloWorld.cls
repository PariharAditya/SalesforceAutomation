@RestResource(urlMapping='/HelloWorld/*')
global with sharing class HelloWorld {
    @HttpGet
    global static String sayHello() {
        return 'Hello, SalesForce!';
    }
}