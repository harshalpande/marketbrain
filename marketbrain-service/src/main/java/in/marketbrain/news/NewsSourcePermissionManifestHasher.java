package in.marketbrain.news;

import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.List;

@Component
public class NewsSourcePermissionManifestHasher {

    public String hash(
            LocalDate preparedOn,
            String preparedBy,
            List<NewsSourcePermissionItemPreview> sources
    ) {
        StringBuilder canonical = new StringBuilder();
        append(canonical, NewsSourcePermissionPreviewService.CONTRACT_VERSION);
        append(canonical, preparedOn);
        append(canonical, preparedBy);
        sources.stream()
                .sorted(Comparator.comparing(NewsSourcePermissionItemPreview::sourceKey))
                .forEach(source -> {
                    append(canonical, source.sourceKey());
                    append(canonical, source.displayName());
                    append(canonical, source.sourceType());
                    append(canonical, source.permissionStatus());
                    append(canonical, source.sourceUrl());
                    append(canonical, source.permissionEvidenceReference());
                    append(canonical, source.requestedOn());
                    append(canonical, source.decidedOn());
                    append(canonical, source.retentionDays());
                    append(canonical, source.headlineStorageAllowed());
                    append(canonical, source.snippetStorageAllowed());
                    append(canonical, source.fullTextStorageAllowed());
                    append(canonical, source.localAiProcessingAllowed());
                    append(canonical, source.derivedDataRetentionAllowed());
                    append(canonical, source.attributionRequired());
                    source.permittedFields().stream().sorted().forEach(field -> append(canonical, field));
                });
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(canonical.toString().getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is unavailable", impossible);
        }
    }

    private void append(StringBuilder target, Object value) {
        String text = value == null ? "<null>" : value.toString();
        target.append(text.length()).append(':').append(text).append('|');
    }
}
