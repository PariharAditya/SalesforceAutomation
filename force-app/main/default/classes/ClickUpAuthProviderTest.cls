@IsTest
private class ClickUpAuthProviderTest {
    private class Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('oauth/token')) {
                res.setBody('{"access_token":"tok123","token_type":"Bearer"}');
            } else {
                res.setBody('{"user":{"id":42,"username":"jane","email":"jane@x.com"}}');
            }
            return res;
        }
    }

    private static Map<String, String> cfg() {
        return new Map<String, String>{
            'Client_Id__c' => 'id', 'Client_Secret__c' => 'secret',
            'Callback_Url__c' => 'https://example.com/cb'
        };
    }

    @IsTest
    static void fullFlow() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        ClickUpAuthProvider p = new ClickUpAuthProvider();

        System.assertEquals('ClickUp_Auth__mdt', p.getCustomMetadataType());
        System.assert(p.initiate(cfg(), 'st').getUrl().contains('client_id=id'));

        Auth.AuthProviderCallbackState cb = new Auth.AuthProviderCallbackState(
            null, null, new Map<String, String>{ 'code' => 'abc', 'state' => 'st' });
        Auth.AuthProviderTokenResponse tr = p.handleCallback(cfg(), cb);
        System.assertEquals('tok123', tr.oauthToken);

        System.assertEquals('42', p.getUserInfo(cfg(), tr).identifier);
    }
}