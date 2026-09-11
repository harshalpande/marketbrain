package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class PrototypeSwingOllamaClientTest {

    @Test
    void sendsSingleNonStreamingGenerateRequest() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://127.0.0.1:11434");
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        PrototypeSwingOllamaClient client = new PrototypeSwingOllamaClient(builder.build());

        server.expect(once(), requestTo("http://127.0.0.1:11434/api/generate"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(content().json("""
                        {
                          "model": "llama3.1:8b",
                          "prompt": "rank only",
                          "stream": false
                        }
                        """, false))
                .andRespond(withSuccess(
                        "{\"response\":\"ranked research output\",\"done\":true}",
                        MediaType.APPLICATION_JSON));

        assertThat(client.generate("llama3.1:8b", "rank only"))
                .isEqualTo("ranked research output");
        server.verify();
    }

    @Test
    void canRequestJsonModeForHardenedResponses() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://127.0.0.1:11434");
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        PrototypeSwingOllamaClient client = new PrototypeSwingOllamaClient(builder.build());

        server.expect(once(), requestTo("http://127.0.0.1:11434/api/generate"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(content().json("""
                        {
                          "model": "gemma3:4b",
                          "prompt": "return json",
                          "stream": false,
                          "format": "json"
                        }
                        """, false))
                .andRespond(withSuccess(
                        "{\"response\":\"{\\\"ok\\\":true}\",\"done\":true}",
                        MediaType.APPLICATION_JSON));

        assertThat(client.generateJson("gemma3:4b", "return json"))
                .isEqualTo("{\"ok\":true}");
        server.verify();
    }
}
