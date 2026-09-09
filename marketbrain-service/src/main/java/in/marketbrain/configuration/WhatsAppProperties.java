package in.marketbrain.configuration;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "marketbrain.whatsapp")
public record WhatsAppProperties(
        boolean enabled,
        boolean sandboxMode,
        String graphVersion,
        String phoneNumberId,
        String wabaId,
        String accessToken,
        String appSecret,
        String verifyToken,
        String allowedWaId
) {
    public boolean isWebhookConfigured() {
        return enabled
                && hasText(phoneNumberId)
                && hasText(wabaId)
                && hasText(appSecret)
                && hasMinimumLength(verifyToken, 32)
                && hasText(allowedWaId);
    }

    public boolean isOutboundConfigured() {
        return isWebhookConfigured()
                && hasText(graphVersion)
                && hasText(accessToken);
    }

    private static boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private static boolean hasMinimumLength(String value, int minimumLength) {
        return hasText(value) && value.length() >= minimumLength;
    }
}
