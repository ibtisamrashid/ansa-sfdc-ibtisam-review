public with sharing class ABT_AddressAutoCompleteController {

    @AuraEnabled
    public static List<AddressSuggestion> searchAddress(String query) {
        List<AddressSuggestion> results = new List<AddressSuggestion>();

        if (String.isBlank(query) || query.length() < 3) {
            return results;
        }

        String apiKey = getApiKey();
        String endpoint = 'https://api.locationiq.com/v1/autocomplete'
            + '?key=' + EncodingUtil.urlEncode(apiKey, 'UTF-8')
            + '&q=' + EncodingUtil.urlEncode(query, 'UTF-8')
            + '&limit=5&format=json';

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(5000);

        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(res.getBody());
            for (Object o : raw) {
                Map<String, Object> item = (Map<String, Object>) o;
                Map<String, Object> addr = (Map<String, Object>) item.get('address');

                AddressSuggestion s = new AddressSuggestion();
                s.displayLabel = (String) item.get('display_name');

                if (addr != null) {
                    s.houseNumber = (String) addr.get('house_number');
                    s.road = (String) addr.get('road');
                    s.city = coalesce(addr, new List<String>{ 'city', 'town', 'village' });
                    s.state = (String) addr.get('state');
                    s.postcode = (String) addr.get('postcode');
                    s.country = (String) addr.get('country');
                    Object cc = addr.get('country_code');
                    s.countryCode = cc != null ? String.valueOf(cc).toUpperCase() : null;
                }
                results.add(s);
            }
        }
        return results;
    }

    private static String coalesce(Map<String, Object> m, List<String> keys) {
        for (String k : keys) {
            if (m.get(k) != null) {
                return (String) m.get(k);
            }
        }
        return null;
    }

    private static String getApiKey() {
        Integration_Setting__mdt setting = [
            SELECT Value__c
            FROM Integration_Setting__mdt
            WHERE DeveloperName = 'LocationIQ_API_Key'
            LIMIT 1
        ];
        return setting.Value__c;
    }

    public class AddressSuggestion {
        @AuraEnabled public String displayLabel;
        @AuraEnabled public String houseNumber;
        @AuraEnabled public String road;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postcode;
        @AuraEnabled public String country;
        @AuraEnabled public String countryCode;
    }
}