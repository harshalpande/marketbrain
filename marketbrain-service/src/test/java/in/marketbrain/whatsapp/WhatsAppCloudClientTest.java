package in.marketbrain.whatsapp;

import in.marketbrain.configuration.WhatsAppProperties;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.util.List;

import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class WhatsAppCloudClientTest {

    @Test
    void sendsOnlyTheAllowListedSandboxRecipientThreeOpaqueButtons() {
        RestClient.Builder builder = RestClient.builder().baseUrl("https://graph.facebook.com");
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        WhatsAppCloudClient client = new WhatsAppCloudClient(builder.build(), properties());

        server.expect(once(), requestTo(
                        "https://graph.facebook.com/v26.0/123456789/messages"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer local-test-token"))
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(content().json("""
                        {
                          "messaging_product": "whatsapp",
                          "recipient_type": "individual",
                          "to": "919999999999",
                          "type": "interactive",
                          "interactive": {
                            "type": "button",
                            "action": {
                              "buttons": [
                                {"type":"reply","reply":{"id":"mb:approve-token","title":"APPROVE"}},
                                {"type":"reply","reply":{"id":"mb:reject-token","title":"REJECT"}},
                                {"type":"reply","reply":{"id":"mb:details-token","title":"DETAILS"}}
                              ]
                            }
                          }
                        }
                        """, false))
                .andRespond(withSuccess(
                        "{\"messages\":[{\"id\":\"wamid.test\"}]}",
                        MediaType.APPLICATION_JSON));

        client.sendInteractiveTestAlert(List.of(
                new WhatsAppCloudClient.ReplyButton("mb:approve-token", "APPROVE"),
                new WhatsAppCloudClient.ReplyButton("mb:reject-token", "REJECT"),
                new WhatsAppCloudClient.ReplyButton("mb:details-token", "DETAILS")));

        server.verify();
    }

    @Test
    void sendsTheExactSystemNotificationTextToTheAllowListedRecipient() {
        RestClient.Builder builder = RestClient.builder().baseUrl("https://graph.facebook.com");
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        WhatsAppCloudClient client = new WhatsAppCloudClient(builder.build(), properties());

        server.expect(once(), requestTo(
                        "https://graph.facebook.com/v26.0/123456789/messages"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(content().json("""
                        {
                          "messaging_product": "whatsapp",
                          "recipient_type": "individual",
                          "to": "919999999999",
                          "type": "text",
                          "text": {
                            "preview_url": false,
                            "body": "identical-system-message"
                          }
                        }
                        """, true))
                .andRespond(withSuccess(
                        "{\"messages\":[{\"id\":\"wamid.system\"}]}",
                        MediaType.APPLICATION_JSON));

        client.sendSystemNote("identical-system-message");

        server.verify();
    }

    private WhatsAppProperties properties() {
        return new WhatsAppProperties(
                true, true, true, true, "v26.0", "123456789", "987654321",
                "local-test-token", "local-test-app-secret",
                "0123456789abcdef0123456789abcdef", "919999999999");
    }
}
