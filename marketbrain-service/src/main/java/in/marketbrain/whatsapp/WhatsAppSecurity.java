package in.marketbrain.whatsapp;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.HexFormat;

final class WhatsAppSecurity {

    private static final String SIGNATURE_PREFIX = "sha256=";

    private WhatsAppSecurity() {
    }

    static boolean constantTimeEquals(String left, String right) {
        if (left == null || right == null) {
            return false;
        }
        return MessageDigest.isEqual(
                left.getBytes(StandardCharsets.UTF_8),
                right.getBytes(StandardCharsets.UTF_8));
    }

    static boolean validSignature(byte[] payload, String signatureHeader, String appSecret) {
        if (payload == null || signatureHeader == null || appSecret == null
                || !signatureHeader.startsWith(SIGNATURE_PREFIX)) {
            return false;
        }
        String supplied = signatureHeader.substring(SIGNATURE_PREFIX.length());
        return MessageDigest.isEqual(
                hmacSha256Bytes(payload, appSecret),
                decodeHex(supplied));
    }

    static String hmacSha256(String value, String secret) {
        return HexFormat.of().formatHex(
                hmacSha256Bytes(value.getBytes(StandardCharsets.UTF_8), secret));
    }

    static String sha256(String value) {
        return sha256(value.getBytes(StandardCharsets.UTF_8));
    }

    static String sha256(byte[] value) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(value));
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private static byte[] hmacSha256Bytes(byte[] payload, String appSecret) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(appSecret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return mac.doFinal(payload);
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("HMAC-SHA256 is unavailable", exception);
        }
    }

    private static byte[] decodeHex(String value) {
        try {
            return HexFormat.of().parseHex(value);
        } catch (IllegalArgumentException exception) {
            return new byte[0];
        }
    }
}
