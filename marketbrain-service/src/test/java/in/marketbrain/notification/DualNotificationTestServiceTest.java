package in.marketbrain.notification;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DualNotificationTestServiceTest {

    @Test
    void provesBothChannelsReceiveOneSharedMessageBody() {
        SystemNotificationGateway telegram = gateway("TELEGRAM");
        SystemNotificationGateway whatsapp = gateway("WHATSAPP");
        DualNotificationTestService service = new DualNotificationTestService(
                new SystemNotificationFanout(List.of(telegram, whatsapp)));
        UUID testId = UUID.randomUUID();

        DualNotificationTestResult result = service.send(testId);

        assertThat(result.status()).isEqualTo("COMPLETED");
        assertThat(result.channels()).extracting(DualNotificationTestResult.ChannelResult::channel)
                .containsExactly("TELEGRAM", "WHATSAPP");
        assertThat(result.messageHash()).hasSize(64);
        assertThat(result.actionExecutionEnabled()).isFalse();
        String key = "DUAL_TEST:" + testId;
        verify(telegram).sendNote(key, DualNotificationTestService.TEST_MESSAGE);
        verify(whatsapp).sendNote(key, DualNotificationTestService.TEST_MESSAGE);
    }

    private SystemNotificationGateway gateway(String channel) {
        SystemNotificationGateway gateway = mock(SystemNotificationGateway.class);
        when(gateway.channel()).thenReturn(channel);
        return gateway;
    }
}
