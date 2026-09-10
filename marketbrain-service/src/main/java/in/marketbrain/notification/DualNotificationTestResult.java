package in.marketbrain.notification;

import java.util.List;
import java.util.UUID;

record DualNotificationTestResult(
        String status,
        UUID testId,
        String messageHash,
        List<ChannelResult> channels,
        boolean actionExecutionEnabled
) {
    record ChannelResult(String channel, String status) {
    }
}
