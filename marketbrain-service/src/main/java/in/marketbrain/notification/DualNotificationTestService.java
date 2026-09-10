package in.marketbrain.notification;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;

@Service
@ConditionalOnProperty(
        prefix = "marketbrain.notifications",
        name = "test-enabled",
        havingValue = "true")
class DualNotificationTestService {

    static final String TEST_MESSAGE = """
            [DUAL CHANNEL TEST] PAPER MODE
            This exact notification was delivered by MarketBrain to Telegram and WhatsApp.
            No action is required.
            No signal, order, or trading action was created.
            """.strip();

    private final SystemNotificationFanout notificationFanout;

    DualNotificationTestService(SystemNotificationFanout notificationFanout) {
        this.notificationFanout = notificationFanout;
    }

    DualNotificationTestResult send(UUID testId) {
        if (testId == null) {
            throw new IllegalArgumentException("A test ID is required.");
        }
        String deduplicationKey = "DUAL_TEST:" + testId;
        SystemNotificationFanout.DeliveryResult delivery =
                notificationFanout.sendNote(deduplicationKey, TEST_MESSAGE);
        List<DualNotificationTestResult.ChannelResult> results = delivery.attemptedChannels().stream()
                .map(channel -> new DualNotificationTestResult.ChannelResult(
                        channel, delivery.failedChannels().contains(channel) ? "FAILED" : "SENT"))
                .toList();
        boolean complete = results.size() == 2
                && results.stream().allMatch(result -> "SENT".equals(result.status()))
                && results.stream().map(DualNotificationTestResult.ChannelResult::channel)
                .toList().containsAll(List.of("TELEGRAM", "WHATSAPP"));
        return new DualNotificationTestResult(
                complete ? "COMPLETED" : "FAILED",
                testId,
                sha256(TEST_MESSAGE),
                results,
                false);
    }

    private String sha256(String value) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256")
                            .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable.");
        }
    }
}
