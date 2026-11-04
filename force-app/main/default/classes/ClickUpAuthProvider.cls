public with sharing class ClickUpAuthProvider extends Auth.AuthProviderPluginClass {
    private static final String AUTH_URL  = 'https://app.clickup.com/api';
    private static final String TOKEN_URL = 'https://api.clickup.com/api/v2/oauth/token';
    private static final String USER_URL  = 'https://api.clickup.com/api/v2/user';

    public String getCustomMetadataType() {
        return 'ClickUp_Auth__mdt';
    }

    public PageReference initiate(Map<String, String> cfg, String stateToPropagate) {
        String url = AUTH_URL
            + '?client_id=' + EncodingUtil.urlEncode(cfg.get('Client_Id__c'), 'UTF-8')
            + '&redirect_uri=' + EncodingUtil.urlEncode(cfg.get('Callback_Url__c'), 'UTF-8')
            + '&state=' + EncodingUtil.urlEncode(stateToPropagate, 'UTF-8');
        return new PageReference(url);
    }

    public Auth.AuthProviderTokenResponse handleCallback(
        Map<String, String> cfg,
        Auth.AuthProviderCallbackState callbackState
    ) {
        String code  = callbackState.queryParameters.get('code');
        String state = callbackState.queryParameters.get('state');
        if (String.isBlank(code)) {
            throw new Auth.AuthProviderPluginException('ClickUp did not return an authorization code.');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(TOKEN_URL);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setBody(JSON.serialize(new Map<String, String>{
            'client_id'     => cfg.get('Client_Id__c'),
            'client_secret' => cfg.get('Client_Secret__c'),
            'code'          => code
        }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new Auth.AuthProviderPluginException(
                'ClickUp token exchange failed: HTTP ' + res.getStatusCode()
            );
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String token = (String) body.get('access_token');
        if (String.isBlank(token)) {
            throw new Auth.AuthProviderPluginException('ClickUp response had no access_token.');
        }
        // ClickUp has no refresh token
        return new Auth.AuthProviderTokenResponse('ClickUp', token, null, state);
    }

    public Auth.UserData getUserInfo(
        Map<String, String> cfg,
        Auth.AuthProviderTokenResponse response
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(USER_URL);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + response.oauthToken);
        HttpResponse res = new Http().send(req);

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> user = (Map<String, Object>) root.get('user');
        String id    = String.valueOf(user.get('id'));
        String uname = (String) user.get('username');
        String email = (String) user.get('email');

        return new Auth.UserData(id, null, null, uname, email, null,
            uname, null, 'ClickUp', null, new Map<String, String>());
    }

    // Tokens don't expire, so nothing to refresh
    public override Auth.OAuthRefreshResult refresh(Map<String, String> cfg, String refreshToken) {
        return new Auth.OAuthRefreshResult(null, null);
    }
}