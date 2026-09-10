package in.marketbrain.notification;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

@Service
public class SystemNotificationFanout {

    private static final Logger LOGGER = LoggerFactory.getLogger(SystemNotificationFanout.class);

    private final List<SystemNotificationGateway> gateways;

    public SystemNotificationFanout(List<SystemNotificationGateway> gateways) {
        this.gateways = gateways.stream()
                .sorted(Comparator.comparing(SystemNotificationGateway::channel))
                .toList();
    }

    public DeliveryResult sendNote(String deduplicationKey, String message) {
        List<String> attemptedChannels = new ArrayList<>();
        List<String> failedChannels = new ArrayList<>();
        for (SystemNotificationGateway gateway : gateways) {
            attemptedChannels.add(gateway.channel());
            try {
                gateway.sendNote(deduplicationKey, message);
            } catch (RuntimeException exception) {
                failedChannels.add(gateway.channel());
                LOGGER.warn("System notification delivery failed safely for {}.", gateway.channel());
            }
        }
        return new DeliveryResult(
                List.copyOf(attemptedChannels), List.copyOf(failedChannels));
    }

    public boolean isConfigured() {
        return !gateways.isEmpty();
    }

    public List<String> channels() {
        return gateways.stream().map(SystemNotificationGateway::channel).toList();
    }

    public record DeliveryResult(List<String> attemptedChannels, List<String> failedChannels) {

        public boolean deliveredToAll() {
            return !attemptedChannels.isEmpty() && failedChannels.isEmpty();
        }
    }
}
