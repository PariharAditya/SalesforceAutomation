public with sharing class ApprovalMatrixClickUpApi {
    public class ClickUpApiException extends Exception {}

    public static List<Map<String, Object>> getTasks(
        String listId,
        String status,
        Integer page
    ) {
        String endpoint = 'callout:ClickUp_API/v2/list/' +
            EncodingUtil.urlEncode(listId, 'UTF-8') +
            '/task?include_markdown_description=true&order_by=updated&reverse=true&page=' +
            String.valueOf(page) +
            '&statuses%5B%5D=' + EncodingUtil.urlEncode(status, 'UTF-8');
        HttpResponse response = sendGet(endpoint);
        Map<String, Object> payload = deserializeObject(response.getBody());
        List<Object> rawTasks;
        try {
            rawTasks = (List<Object>) payload.get('tasks');
        } catch (TypeException invalidTasks) {
            throw new ClickUpApiException(
                'ClickUp task-list response did not contain a tasks array.'
            );
        }
        if (rawTasks == null) {
            throw new ClickUpApiException(
                'ClickUp task-list response did not contain a tasks array.'
            );
        }

        List<Map<String, Object>> tasks = new List<Map<String, Object>>();
        for (Object rawTask : rawTasks) {
            try {
                tasks.add((Map<String, Object>) rawTask);
            } catch (TypeException invalidTask) {
                throw new ClickUpApiException(
                    'ClickUp task-list response contained an invalid task.'
                );
            }
        }
        return tasks;
    }

    private static HttpResponse sendGet(String endpoint) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setTimeout(20000);
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (CalloutException calloutError) {
            throw new ClickUpApiException(
                'Could not reach ClickUp. Check the ClickUp_API Named Credential.'
            );
        }
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new ClickUpApiException(
                'ClickUp returned HTTP ' + response.getStatusCode() +
                '. Check the Named Credential token and List access.'
            );
        }
        return response;
    }

    private static Map<String, Object> deserializeObject(String body) {
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (JSONException invalidJson) {
            throw new ClickUpApiException('ClickUp returned invalid JSON.');
        } catch (TypeException invalidShape) {
            throw new ClickUpApiException(
                'ClickUp response must be a JSON object.'
            );
        }
    }
}
