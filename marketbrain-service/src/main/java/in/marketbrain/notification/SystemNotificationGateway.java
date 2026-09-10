package in.marketbrain.notification;

public interface SystemNotificationGateway {

    String channel();

    void sendNote(String deduplicationKey, String message);
}
