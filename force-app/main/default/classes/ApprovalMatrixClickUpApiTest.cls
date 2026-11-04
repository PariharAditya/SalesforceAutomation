@IsTest
private class ApprovalMatrixClickUpApiTest {
    private class Mock implements HttpCalloutMock {
        Integer code; String body;
        Mock(Integer code, String body) { this.code = code; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody(body);
            return res;
        }
    }

    @IsTest
    static void returnsTasks() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"tasks":[{"id":"1"},{"id":"2"}]}'));
        Test.startTest();
        List<Map<String, Object>> tasks = ApprovalMatrixClickUpApi.getTasks('123', 'open', 0);
        Test.stopTest();
        System.assertEquals(2, tasks.size());
    }

    @IsTest
    static void throwsOnHttpError() {
        Test.setMock(HttpCalloutMock.class, new Mock(401, '{"err":"Token invalid"}'));
        try {
            ApprovalMatrixClickUpApi.getTasks('123', 'open', 0);
            System.assert(false, 'Expected exception');
        } catch (ApprovalMatrixClickUpApi.ClickUpApiException e) {
            System.assert(e.getMessage().contains('401'));
        }
    }

    @IsTest
    static void throwsWhenTasksMissing() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"foo":1}'));
        try {
            ApprovalMatrixClickUpApi.getTasks('123', 'open', 0);
            System.assert(false, 'Expected exception');
        } catch (ApprovalMatrixClickUpApi.ClickUpApiException e) {
            System.assert(e.getMessage().contains('tasks array'));
        }
    }
}