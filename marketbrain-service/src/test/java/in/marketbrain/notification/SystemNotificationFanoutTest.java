package in.marketbrain.notification;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SystemNotificationFanoutTest {

    @Test
    void sendsTheExactSameMessageToBothChannelsInStableOrder() {
        SystemNotificationGateway whatsapp = gateway("WHATSAPP");
        SystemNotificationGateway telegram = gateway("TELEGRAM");
        SystemNotificationFanout fanout = new SystemNotificationFanout(
                List.of(whatsapp, telegram));

        SystemNotificationFanout.DeliveryResult result =
                fanout.sendNote("DAILY:2026-09-10:COMPLETION", "identical-message");

        assertThat(result.attemptedChannels()).containsExactly("TELEGRAM", "WHATSAPP");
        assertThat(result.failedChannels()).isEmpty();
        assertThat(result.deliveredToAll()).isTrue();
        var ordered = inOrder(telegram, whatsapp);
        ordered.verify(telegram).sendNote(
                "DAILY:2026-09-10:COMPLETION", "identical-message");
        ordered.verify(whatsapp).sendNote(
                "DAILY:2026-09-10:COMPLETION", "identical-message");
    }

    @Test
    void oneChannelFailureDoesNotPreventTheOtherChannelAttempt() {
        SystemNotificationGateway telegram = gateway("TELEGRAM");
        SystemNotificationGateway whatsapp = gateway("WHATSAPP");
        doThrow(new IllegalStateException("provider unavailable"))
                .when(telegram).sendNote("key", "message");
        SystemNotificationFanout fanout = new SystemNotificationFanout(
                List.of(telegram, whatsapp));

        SystemNotificationFanout.DeliveryResult result = fanout.sendNote("key", "message");

        assertThat(result.failedChannels()).containsExactly("TELEGRAM");
        assertThat(result.deliveredToAll()).isFalse();
        verify(whatsapp).sendNote("key", "message");
    }

    private SystemNotificationGateway gateway(String channel) {
        SystemNotificationGateway gateway = mock(SystemNotificationGateway.class);
        when(gateway.channel()).thenReturn(channel);
        return gateway;
    }
}
